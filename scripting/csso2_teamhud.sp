/**
 * ============================================================================
 *  CSSO 2.0  -  Team Head-Up Display / 队友头显
 * ----------------------------------------------------------------------------
 *  在 HUD 上实时显示队友的:
 *      > 名字      (Name)
 *      > 经济      (Money) + 队伍总经济 / 平均值
 *      > 生命/护甲 (HP / Armor / Helmet)
 *      > 武器      (主武器、副武器, 含 弹匣/备弹)
 *      > 道具      (闪光弹 x2、烟雾弹、高爆手雷、燃烧瓶、燃烧弹、诱饵弹、战术手雷)
 *      > 装备      (拆弹器 KIT、C4、电击枪 ZEUS)
 *
 *  适用平台:
 *      > CSSO 2.0 / Source Offensive  (Source 2013 + cstrike 内容, appID 240)
 *      > Counter-Strike: Source
 *      > Counter-Strike: Global Offensive (legacy)
 *
 *  注意: SourceMod 官方至今不支持 CS2 (Counter-Strike 2)。
 *        CS2 服务器请使用 CounterStrikeSharp (C#) 版本, 本插件无法在 CS2 上运行。
 *
 *  引擎差异处理:
 *      > 金钱/护甲/头盔/拆弹器/武器列表: CS:S 与 CS:GO 属性相同 (CCSPlayer::m_iAccount 等)
 *      > 备弹: CS:GO 用武器自带的 m_iPrimaryReserveAmmoCount;
 *              CS:S / CSSO 用玩家 m_iAmmo 数组 + 武器的 m_iPrimaryAmmoType
 *      > 手雷数量: CS:GO 是 1 + 备弹; CS:S / CSSO 是 m_iAmmo[弹药类型]
 *
 *  编译: spcomp csso2_teamhud.sp      (SourceMod 1.11+, 推荐 1.12)
 *  调试: csso_hud_debug 1 后换图, 或游戏内 sm_csso_dump 打印实测属性
 *
 *  2.2.0 新增:
 *      > 头顶名牌 (NEW): 队友名字 + 血量% 直接浮在头顶, 像 CS:GO 的队友信息牌
 *              csso_tag_enabled 1      总开关 (玩家可用 !tags 单独关掉)
 *              csso_tag_mode 0         0=名字+血量%, 1=+当前武器, 2=只有名字
 *              csso_tag_color 0        0=队伍色, 1=固定黄(截图那种), 2=按血量变色
 *              只画给同队队友看, 且可选"被墙挡住就不画", 不会变成透视
 *      > 配色: csso_hud_color 6 = CSSO 2.0 原生队伍色
 *              (取自模组 resource/clientscheme.res 的 TeamT 234 209 138 / TeamCT 181 212 238)
 *              csso_hud_color 5 = 状态色: 每行独立着色 (阵亡灰 / 残血红 / 低血橙 / 正常队伍色)
 *      > 中文: csso_hud_lang 1 = 中文标签 + 投掷物/装备, 2 = 再加武器中文名
 *      > 自检: sm_csso_fonttest 判断客户端 HUD 字体能不能渲染中文
 *              sm_csso_tagtest  打印名牌投影参数 (名牌位置不对时用它调参)
 * ============================================================================
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <clientprefs>

#define HUD_TAG             "CSSO 2.0"
#define CS_MAX_WEAPONS      64          // MAX_WEAPONS (CS:S / CSSO / CS:GO 都是 64)
#define CS_MAX_AMMO_TYPES   32          // MAX_AMMO_TYPES, m_iAmmo 数组长度上限
#define HUD_BUFFER_SIZE     1024
#define LINE_BUFFER_SIZE    200

#define MAX_HUD_ROWS        8           // 与 csso_hud_max_rows 上限一致
#define ROW_SYNC_COUNT      (MAX_HUD_ROWS + 1)   // 状态色模式: 通道 0 = 标题, 1..8 = 每名队友
#define COLOR_STATUS        5           // csso_hud_color 5 = 每行独立状态色
#define COLOR_CSSO_NATIVE   6           // csso_hud_color 6 = CSSO 2.0 原生队伍色

#define MAX_TAG_SLOTS       9           // 头顶名牌: 每个客户端最多同时绘制 9 个
#define TAG_COLOR_TEAM      0           // csso_tag_color 0 = 队伍色
#define TAG_COLOR_FIXED     1           // csso_tag_color 1 = 固定黄
#define TAG_COLOR_HEALTH    2           // csso_tag_color 2 = 按血量变色

enum WeaponCategory
{
	WPN_NONE = 0,
	WPN_PRIMARY,      // 步枪 / 狙击 / 机枪 / 冲锋枪
	WPN_SECONDARY,    // 手枪
	WPN_KNIFE,        // 刀
	WPN_UTILITY,      // 投掷物
	WPN_BOMB,         // C4
	WPN_TASER,        // 电击枪
	WPN_MEDSHOT       // 医疗针
}

// ---------------------------------------------------------------------------
// ConVar
// ---------------------------------------------------------------------------
ConVar g_cvEnabled;
ConVar g_cvInterval;
ConVar g_cvMaxRows;
ConVar g_cvDetail;
ConVar g_cvShowSelf;
ConVar g_cvAliveOnly;
ConVar g_cvShowHealth;
ConVar g_cvSort;
ConVar g_cvPosX;
ConVar g_cvPosY;
ConVar g_cvColorMode;
ConVar g_cvLang;
ConVar g_cvLineHeight;
ConVar g_cvDebug;
ConVar g_cvTagEnabled;
ConVar g_cvTagMode;
ConVar g_cvTagColorMode;
ConVar g_cvTagMaxDist;
ConVar g_cvTagHeight;
ConVar g_cvTagVisibleOnly;
ConVar g_cvTagInterval;
ConVar g_cvTagFov;
ConVar g_cvTagAspect;
ConVar g_cvTagCharWidth;

Handle g_hTimer = null;
Handle g_hSync = null;
Handle g_hCookie = null;

// 头顶名牌: 每个名牌一条独立 HUD 通道 (位置各不相同)
Handle g_hTagTimer = null;
Handle g_hTagCookie = null;
Handle g_hTagSync[MAX_TAG_SLOTS];

// 状态色模式 (csso_hud_color 5) 用: 每行一条独立 HUD 消息, 才能各行不同色
Handle g_hRowSync[ROW_SYNC_COUNT];
Handle g_hFontTestSync = null;
Handle g_hFontTestTimer = null;
int g_iFontTestTicks[MAXPLAYERS + 1];
int g_iLastMode[MAXPLAYERS + 1];
int g_iPrevRows[MAXPLAYERS + 1];

StringMap g_hWeaponName = null;      // 英文短名
StringMap g_hWeaponNameZh = null;    // 中文短名 (lang 2)
StringMap g_hWeaponCat = null;

bool g_bHudPref[MAXPLAYERS + 1];
bool g_bTagPref[MAXPLAYERS + 1];
int  g_iPrevTags[MAXPLAYERS + 1];

// 网络属性偏移 (查找失败为 -1)
int g_iAccountOffset = -1;
int g_iPlayerResourceAccountOffset = -1;
int g_iMyWeaponsOffset = -1;
int g_iClipOffset = -1;
int g_iReserveAmmoOffset = -1;
int g_iArmorOffset = -1;
int g_iHelmetOffset = -1;
int g_iDefuserOffset = -1;

// CS:S / CSSO 专用: 备弹在玩家身上 (m_iAmmo 数组), 用武器的 m_iPrimaryAmmoType 索引
int  g_iAmmoArrayOffset = -1;
int  g_iAmmoArraySize = CS_MAX_AMMO_TYPES;
int  g_iAmmoTypeOffset = -1;
bool g_bAmmoTypeTried = false;

EngineVersion g_Engine = Engine_Unknown;

// 缓存后的设置
bool  g_bEnabled = true;
float g_fInterval = 0.2;
float g_fHoldTime = 0.35;
int   g_iMaxRows = 5;
int   g_iDetail = 2;
bool  g_bShowSelf = true;
bool  g_bAliveOnly = false;
bool  g_bShowHealth = true;
int   g_iSort = 1;
float g_fPosX = 0.02;
float g_fPosY = 0.40;
int   g_iColorMode = 0;
int   g_iLang = 0;
float g_fLineHeight = 0.025;
bool  g_bDebug = false;

// 头顶名牌缓存设置
bool  g_bTagEnabled = true;
int   g_iTagMode = 0;
int   g_iTagColorMode = 0;
float g_fTagMaxDist = 3000.0;
float g_fTagHeight = 12.0;
bool  g_bTagVisibleOnly = true;
float g_fTagInterval = 0.05;
float g_fTagFov = 0.0;
float g_fTagAspect = 1.7777778;
float g_fTagCharWidth = 0.008;
float g_fTagHold = 0.2;

public Plugin myinfo =
{
	name        = "CSSO 2.0 - Team HUD",
	author      = "Faker1147",
	description = "队友头显: 名字 / 经济 / 武器 / 道具 + 头顶名牌 (CSSO 2.0 / CS:S / CS:GO)",
	version     = "2.2.0",
	url         = "https://github.com/Faker1147/csso-teamhud"
};

// ---------------------------------------------------------------------------
// 启动 / 卸载
// ---------------------------------------------------------------------------
public void OnPluginStart()
{
	g_Engine = GetEngineVersion();

	// CSSO 2.0 是自定义 gamedir (csso) 的 Source 2013 模组, 引擎识别值不一定是标准 CS 引擎,
	// 所以这里只警告、不拦载; 真正的兼容性交给 CacheOffsets() 的多类名查找和降级逻辑。
	if (g_Engine != Engine_CSGO && g_Engine != Engine_CSS
		&& g_Engine != Engine_SDK2013 && g_Engine != Engine_Unknown)
	{
		LogMessage("[CSSO 2.0] 引擎识别为 %d, 不是标准 CS 引擎; 头显仍会尝试工作。",
			view_as<int>(g_Engine));
	}

	g_hWeaponName = new StringMap();
	g_hWeaponNameZh = new StringMap();
	g_hWeaponCat = new StringMap();
	BuildWeaponData();

	g_hSync = CreateHudSynchronizer();

	for (int i = 0; i < ROW_SYNC_COUNT; i++)
	{
		g_hRowSync[i] = CreateHudSynchronizer();
	}

	g_hFontTestSync = CreateHudSynchronizer();

	for (int i = 0; i < MAX_TAG_SLOTS; i++)
	{
		g_hTagSync[i] = CreateHudSynchronizer();
	}

	g_cvEnabled    = CreateConVar("csso_hud_enabled", "1", "0=关闭头显, 1=开启头显", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvInterval   = CreateConVar("csso_hud_interval", "0.2", "头显刷新间隔 (秒), 建议 0.1 - 0.5", FCVAR_NOTIFY, true, 0.05, true, 5.0);
	g_cvMaxRows    = CreateConVar("csso_hud_max_rows", "5", "最多显示几名队友", FCVAR_NOTIFY, true, 1.0, true, 8.0);
	g_cvDetail     = CreateConVar("csso_hud_detail", "2", "显示级别: 0=名字+金钱, 1=+生命/护甲/武器, 2=+道具/装备", FCVAR_NOTIFY, true, 0.0, true, 2.0);
	g_cvShowSelf   = CreateConVar("csso_hud_show_self", "1", "是否把自己也显示在头显中", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvAliveOnly  = CreateConVar("csso_hud_alive_only", "0", "1=只显示存活队友, 0=阵亡队友也显示(标记 DEAD)", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvShowHealth = CreateConVar("csso_hud_health", "1", "是否显示生命值和护甲", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvSort       = CreateConVar("csso_hud_sort", "1", "排序方式: 0=玩家顺序, 1=金钱从高到低", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvPosX       = CreateConVar("csso_hud_x", "0.02", "头显 X 坐标 (0.0 - 1.0)", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvPosY       = CreateConVar("csso_hud_y", "0.40", "头显 Y 坐标 (0.0 - 1.0)", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvColorMode  = CreateConVar("csso_hud_color", "0", "颜色: 0=队伍色, 1=白, 2=绿, 3=橙, 4=青, 5=状态色(每行独立), 6=CSSO 2.0 原生队伍色", FCVAR_NOTIFY, true, 0.0, true, 6.0);
	g_cvLang       = CreateConVar("csso_hud_lang", "0", "HUD 语言: 0=英文, 1=中文标签+投掷物/装备, 2=再加武器中文名", FCVAR_NOTIFY, true, 0.0, true, 2.0);
	g_cvLineHeight = CreateConVar("csso_hud_line_height", "0.025", "状态色模式下每行的高度 (0.010 - 0.100), 行重叠/间隔过大时调它", FCVAR_NOTIFY, true, 0.010, true, 0.100);
	g_cvDebug      = CreateConVar("csso_hud_debug", "0", "1=把偏移信息输出到服务器控制台", FCVAR_NOTIFY, true, 0.0, true, 1.0);

	g_cvTagEnabled = CreateConVar("csso_tag_enabled", "1", "1=开启队友头顶名牌 (名字+血量%), 0=关闭", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvTagMode    = CreateConVar("csso_tag_mode", "0", "名牌内容: 0=名字+血量%, 1=再加当前武器, 2=只有名字", FCVAR_NOTIFY, true, 0.0, true, 2.0);
	g_cvTagColorMode = CreateConVar("csso_tag_color", "0", "名牌颜色: 0=队伍色, 1=固定黄, 2=按血量变色", FCVAR_NOTIFY, true, 0.0, true, 2.0);
	g_cvTagMaxDist = CreateConVar("csso_tag_max_dist", "3000", "名牌最大显示距离 (游戏单位), 0=不限", FCVAR_NOTIFY, true, 0.0, true, 20000.0);
	g_cvTagHeight  = CreateConVar("csso_tag_height", "12", "名牌距离队友眼睛的高度 (游戏单位)", FCVAR_NOTIFY, true, -32.0, true, 96.0);
	g_cvTagVisibleOnly = CreateConVar("csso_tag_visible_only", "1", "1=被墙挡住时不显示名牌 (防透视), 0=一直显示", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvTagInterval = CreateConVar("csso_tag_interval", "0.05", "名牌刷新间隔 (秒), 越小越平滑但越耗带宽, 建议 0.02 - 0.10", FCVAR_NOTIFY, true, 0.01, true, 0.5);
	g_cvTagFov     = CreateConVar("csso_tag_fov", "0", "水平视野角 (4:3 下的 fov), 0=自动读取客户端 m_iFOV, 默认 90", FCVAR_NOTIFY, true, 0.0, true, 179.0);
	g_cvTagAspect  = CreateConVar("csso_tag_aspect", "1.7778", "客户端画面宽高比: 16:9=1.7778, 16:10=1.6, 4:3=1.3333", FCVAR_NOTIFY, true, 1.0, true, 3.0);
	g_cvTagCharWidth = CreateConVar("csso_tag_char_width", "0.008", "用于居中名牌的单个字符宽度估算 (0.004 - 0.020)", FCVAR_NOTIFY, true, 0.002, true, 0.05);

	CreateConVar("csso_hud_version", "2.2.0", "CSSO 2.0 版本号", FCVAR_NOTIFY | FCVAR_DONTRECORD);

	g_cvEnabled.AddChangeHook(OnConVarChanged);
	g_cvInterval.AddChangeHook(OnConVarChanged);
	g_cvMaxRows.AddChangeHook(OnConVarChanged);
	g_cvDetail.AddChangeHook(OnConVarChanged);
	g_cvShowSelf.AddChangeHook(OnConVarChanged);
	g_cvAliveOnly.AddChangeHook(OnConVarChanged);
	g_cvShowHealth.AddChangeHook(OnConVarChanged);
	g_cvSort.AddChangeHook(OnConVarChanged);
	g_cvPosX.AddChangeHook(OnConVarChanged);
	g_cvPosY.AddChangeHook(OnConVarChanged);
	g_cvColorMode.AddChangeHook(OnConVarChanged);
	g_cvLang.AddChangeHook(OnConVarChanged);
	g_cvLineHeight.AddChangeHook(OnConVarChanged);
	g_cvDebug.AddChangeHook(OnConVarChanged);

	g_cvTagEnabled.AddChangeHook(OnConVarChanged);
	g_cvTagMode.AddChangeHook(OnConVarChanged);
	g_cvTagColorMode.AddChangeHook(OnConVarChanged);
	g_cvTagMaxDist.AddChangeHook(OnConVarChanged);
	g_cvTagHeight.AddChangeHook(OnConVarChanged);
	g_cvTagVisibleOnly.AddChangeHook(OnConVarChanged);
	g_cvTagInterval.AddChangeHook(OnConVarChanged);
	g_cvTagFov.AddChangeHook(OnConVarChanged);
	g_cvTagAspect.AddChangeHook(OnConVarChanged);
	g_cvTagCharWidth.AddChangeHook(OnConVarChanged);

	g_hCookie = RegClientCookie("csso2_hud", "CSSO 2.0 队友头显开关", CookieAccess_Private);
	g_hTagCookie = RegClientCookie("csso2_tags", "CSSO 2.0 头顶名牌开关", CookieAccess_Private);

	RegConsoleCmd("sm_teamhud", Command_ToggleHud, "开关 CSSO 2.0 队友头显");
	RegConsoleCmd("sm_thud", Command_ToggleHud, "开关 CSSO 2.0 队友头显");
	RegConsoleCmd("sm_tags", Command_ToggleTags, "开关 CSSO 2.0 头顶名牌 (名字/血量)");
	RegAdminCmd("sm_csso_reload", Command_Reload, ADMFLAG_CONFIG, "重新载入 CSSO 2.0 头显设置");
	RegAdminCmd("sm_csso_dump", Command_Dump, ADMFLAG_CONFIG, "打印本地玩家的实测属性 (排查头显不显示/数值不对)");
	RegAdminCmd("sm_csso_fonttest", Command_FontTest, ADMFLAG_CONFIG, "在 HUD 上显示中英文样张, 用来判断客户端字体能否渲染中文");
	RegAdminCmd("sm_csso_tagtest", Command_TagTest, ADMFLAG_CONFIG, "打印头顶名牌的投影参数 (位置不对时用它调参)");

	AutoExecConfig(true, "csso2");
	CacheOffsets();
	RefreshSettings();
}

public void OnMapStart()
{
	// 换图后重找: 部分属性 (datamap) 只有在武器实体存在时才能查到
	g_iAmmoTypeOffset = -1;
	g_bAmmoTypeTried = false;
	CacheOffsets();
}

public void OnConfigsExecuted()
{
	RefreshSettings();
	RestartTimer();
}

public void OnPluginEnd()
{
	if (g_hTimer != null)
	{
		delete g_hTimer;
		g_hTimer = null;
	}

	if (g_hFontTestTimer != null)
	{
		delete g_hFontTestTimer;
		g_hFontTestTimer = null;
	}

	if (g_hTagTimer != null)
	{
		delete g_hTagTimer;
		g_hTagTimer = null;
	}

	ClearAllHuds();

	delete g_hWeaponName;
	delete g_hWeaponNameZh;
	delete g_hWeaponCat;

	for (int i = 0; i < ROW_SYNC_COUNT; i++)
	{
		delete g_hRowSync[i];
	}

	for (int i = 0; i < MAX_TAG_SLOTS; i++)
	{
		delete g_hTagSync[i];
	}

	delete g_hFontTestSync;
}

// ---------------------------------------------------------------------------
// 客户端
// ---------------------------------------------------------------------------
public void OnClientPutInServer(int client)
{
	g_bHudPref[client] = true;
	g_bTagPref[client] = true;
}

public void OnClientCookiesCached(int client)
{
	char value[8];
	GetClientCookie(client, g_hCookie, value, sizeof(value));

	if (value[0] != '\0')
	{
		g_bHudPref[client] = (value[0] == '1');
	}

	GetClientCookie(client, g_hTagCookie, value, sizeof(value));

	if (value[0] != '\0')
	{
		g_bTagPref[client] = (value[0] == '1');
	}
}

public void OnClientDisconnect(int client)
{
	g_bHudPref[client] = true;
	g_bTagPref[client] = true;
	g_iPrevRows[client] = 0;
	g_iPrevTags[client] = 0;
	g_iLastMode[client] = -1;
	g_iFontTestTicks[client] = 0;

	if (IsClientInGame(client))
	{
		ClearSyncHud(client, g_hSync);
		ClearRowSyncs(client, ROW_SYNC_COUNT);
		ClearTagSyncs(client, MAX_TAG_SLOTS);
		ClearSyncHud(client, g_hFontTestSync);
	}
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	RefreshSettings();
	RestartTimer();
}

// ---------------------------------------------------------------------------
// 命令
// ---------------------------------------------------------------------------
public Action Command_ToggleHud(int client, int args)
{
	if (client == 0)
	{
		ReplyToCommand(client, "[CSSO 2.0] This command can only be used in game.");
		return Plugin_Handled;
	}

	g_bHudPref[client] = !g_bHudPref[client];

	if (g_hCookie != null)
	{
		SetClientCookie(client, g_hCookie, g_bHudPref[client] ? "1" : "0");
	}

	if (!g_bHudPref[client])
	{
		ClearSyncHud(client, g_hSync);
	}

	PrintToChat(client, "[CSSO 2.0] Team HUD: %s", g_bHudPref[client] ? "ON" : "OFF");
	return Plugin_Handled;
}

// ---------------------------------------------------------------------------
// sm_tags: 玩家自己开关头顶名牌
// ---------------------------------------------------------------------------
public Action Command_ToggleTags(int client, int args)
{
	if (client == 0)
	{
		ReplyToCommand(client, "[CSSO 2.0] This command can only be used in game.");
		return Plugin_Handled;
	}

	g_bTagPref[client] = !g_bTagPref[client];

	if (g_hTagCookie != null)
	{
		SetClientCookie(client, g_hTagCookie, g_bTagPref[client] ? "1" : "0");
	}

	if (!g_bTagPref[client])
	{
		ClearTagSyncs(client, MAX_TAG_SLOTS);
		g_iPrevTags[client] = 0;
	}

	PrintToChat(client, "[CSSO 2.0] 头顶名牌: %s", g_bTagPref[client] ? "ON" : "OFF");
	return Plugin_Handled;
}

// ---------------------------------------------------------------------------
// sm_csso_tagtest: 打印名牌投影参数
//   名牌位置偏高/偏低/偏左偏右时, 用这里的实时数值调 csso_tag_aspect / csso_tag_char_width。
// ---------------------------------------------------------------------------
public Action Command_TagTest(int client, int args)
{
	if (client == 0)
	{
		ReplyToCommand(client, "[CSSO 2.0] Run this in game.");
		return Plugin_Handled;
	}

	char buffer[256];
	DumpLine(client, "[CSSO 2.0] ===== tag test =====");

	Format(buffer, sizeof(buffer), "tag: enabled=%d mode=%d color=%d interval=%.3f height=%.1f dist=%.0f visibleOnly=%d",
		g_bTagEnabled ? 1 : 0, g_iTagMode, g_iTagColorMode, g_fTagInterval, g_fTagHeight,
		g_fTagMaxDist, g_bTagVisibleOnly ? 1 : 0);
	DumpLine(client, buffer);

	Format(buffer, sizeof(buffer), "proj: fov=%.1f (cvar %.1f, m_iFOV %d) aspect=%.4f charWidth=%.4f",
		TagGetFov(client), g_fTagFov, GetEntProp(client, Prop_Send, "m_iFOV"), g_fTagAspect, g_fTagCharWidth);
	DumpLine(client, buffer);

	float eye[3];
	GetClientEyePosition(client, eye);
	Format(buffer, sizeof(buffer), "eye: %.0f %.0f %.0f  team=%d alive=%d",
		eye[0], eye[1], eye[2], GetClientTeam(client), IsPlayerAlive(client) ? 1 : 0);
	DumpLine(client, buffer);

	int team = GetClientTeam(client);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (i == client || !IsClientInGame(i) || !IsPlayerAlive(i) || GetClientTeam(i) != team)
		{
			continue;
		}

		float head[3];
		GetTagWorldPos(i, head);

		float sx = 0.0;
		float sy = 0.0;

		if (!WorldToScreen(client, head, sx, sy))
		{
			Format(buffer, sizeof(buffer), "  #%d %N: 在身后或视野外", i, i);
			DumpLine(client, buffer);
			continue;
		}

		Format(buffer, sizeof(buffer), "  #%d %N: screen=(%.3f, %.3f) dist=%.0f visible=%d",
			i, i, sx, sy, GetVectorDistance(eye, head), TagIsVisible(client, i) ? 1 : 0);
		DumpLine(client, buffer);
	}

	DumpLine(client, "[CSSO 2.0] ===== tag test end =====");
	ReplyToCommand(client, "[CSSO 2.0] Tag params written to your console.");

	return Plugin_Handled;
}

public Action Command_Reload(int client, int args)
{
	RefreshSettings();
	RestartTimer();
	ReplyToCommand(client, "[CSSO 2.0] Settings reloaded. HUD is now %s.", g_bEnabled ? "ON" : "OFF");
	return Plugin_Handled;
}

void DumpLine(int client, const char[] text)
{
	PrintToConsole(client, "%s", text);
	LogMessage("%s", text);
}

// sm_csso_dump: 把实测的属性值打到玩家控制台 + SourceMod 日志, 用来确认引擎差异
public Action Command_Dump(int client, int args)
{
	if (client == 0)
	{
		ReplyToCommand(client, "[CSSO 2.0] Run this in game.");
		return Plugin_Handled;
	}

	char buffer[256];

	DumpLine(client, "[CSSO 2.0] ===== dump start =====");

	Format(buffer, sizeof(buffer), "engine=%d (Unknown=0, CSGO=12, CSS=13, SDK2013=14)", view_as<int>(g_Engine));
	DumpLine(client, buffer);

	Format(buffer, sizeof(buffer), "offsets: account=%d prAccount=%d weapons=%d clip=%d reserve=%d ammoArray=%d(size=%d) ammoType=%d armor=%d helmet=%d defuser=%d",
		g_iAccountOffset, g_iPlayerResourceAccountOffset, g_iMyWeaponsOffset, g_iClipOffset,
		g_iReserveAmmoOffset, g_iAmmoArrayOffset, g_iAmmoArraySize, g_iAmmoTypeOffset,
		g_iArmorOffset, g_iHelmetOffset, g_iDefuserOffset);
	DumpLine(client, buffer);

	Format(buffer, sizeof(buffer), "me: money=$%d health=%d armor=%d helmet=%d defuser=%d",
		CssoGetMoney(client), GetEntProp(client, Prop_Data, "m_iHealth"),
		CssoGetArmor(client), CssoHasHelmet(client) ? 1 : 0, CssoHasDefuser(client) ? 1 : 0);
	DumpLine(client, buffer);

	Format(buffer, sizeof(buffer), "cfg: color=%d lang=%d rows=%d detail=%d lineHeight=%.3f interval=%.2f",
		g_iColorMode, g_iLang, g_iMaxRows, g_iDetail, g_fLineHeight, g_fInterval);
	DumpLine(client, buffer);

	Format(buffer, sizeof(buffer), "tag: enabled=%d mode=%d color=%d height=%.1f dist=%.0f visibleOnly=%d fov=%.1f aspect=%.4f",
		g_bTagEnabled ? 1 : 0, g_iTagMode, g_iTagColorMode, g_fTagHeight, g_fTagMaxDist,
		g_bTagVisibleOnly ? 1 : 0, TagGetFov(client), g_fTagAspect);
	DumpLine(client, buffer);

	int weapons[CS_MAX_WEAPONS];
	int count = CollectWeapons(client, weapons, sizeof(weapons));

	Format(buffer, sizeof(buffer), "weapons=%d (m_hMyWeapons found=%d)",
		count, g_iMyWeaponsOffset != -1 ? 1 : 0);
	DumpLine(client, buffer);

	for (int i = 0; i < count; i++)
	{
		int weapon = weapons[i];
		char classname[64];
		char display[32];

		if (!GetEntityClassname(weapon, classname, sizeof(classname)))
		{
			continue;
		}

		if (!GetWeaponDisplayName(weapon, display, sizeof(display)))
		{
			strcopy(display, sizeof(display), "?");
		}

		int category = GetWeaponCategory(weapon);
		int ammoType = CssoGetAmmoType(weapon);
		int value = (category == view_as<int>(WPN_UTILITY))
			? CssoGetUtilityCount(client, weapon)
			: CssoGetReserveAmmo(client, weapon);

		Format(buffer, sizeof(buffer), "  ent=%d class=%s name=%s cat=%d clip=%d ammoType=%d reserve_or_count=%d",
			weapon, classname, display, category, CssoGetClip(weapon), ammoType, value);
		DumpLine(client, buffer);
	}

	char line[LINE_BUFFER_SIZE];
	FormatTeammateLine(client, line, sizeof(line));
	Format(buffer, sizeof(buffer), "hud line -> %s", line);
	DumpLine(client, buffer);

	DumpLine(client, "[CSSO 2.0] ===== dump end (also in SourceMod log) =====");
	ReplyToCommand(client, "[CSSO 2.0] Dump written to your console and the SourceMod log.");

	return Plugin_Handled;
}

// ---------------------------------------------------------------------------
// sm_csso_fonttest: 字体自检
//   用独立 sync 通道显示中英文样张。如果中文样张正常显示, 说明客户端 HUD 字体支持中文,
//   可以直接开 csso_hud_lang 1/2; 如果显示成方块/空白, 需要客户端字体补丁。
//   同时这也验证了"多个 sync 通道能同时显示" (状态色模式依赖这个特性)。
// ---------------------------------------------------------------------------
public Action Command_FontTest(int client, int args)
{
	if (client == 0)
	{
		ReplyToCommand(client, "[CSSO 2.0] Run this in game.");
		return Plugin_Handled;
	}

	g_iFontTestTicks[client] = 12;    // 12 秒

	if (g_hFontTestTimer == null)
	{
		g_hFontTestTimer = CreateTimer(1.0, Timer_FontTest, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}

	ShowFontTestHud(client);
	ReplyToCommand(client, "[CSSO 2.0] Font test shown for 12s. Tell me what you see.");

	return Plugin_Handled;
}

void ShowFontTestHud(int client)
{
	char buffer[512];

	Format(buffer, sizeof(buffer),
		"[FONT TEST] ASCII: CSSO 2.0  AK-47 100HP 30/90  FLASHx2  KIT\n\
[中文测试 1] 队友 名字 经济 武器 道具 闪光弹 拆弹器\n\
[中文测试 2] 阵亡 烟雾弹 高爆手雷 燃烧瓶 医疗针 诱饵弹");

	SetHudTextParams(0.02, 0.14, 1.6, 255, 255, 255, 255, 0, 0.0, 0.0, 0.0);
	ShowSyncHudText(client, g_hFontTestSync, buffer);
}

public Action Timer_FontTest(Handle timer)
{
	int active = 0;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_iFontTestTicks[i] <= 0)
		{
			continue;
		}

		g_iFontTestTicks[i]--;

		if (!IsClientInGame(i))
		{
			continue;
		}

		if (g_iFontTestTicks[i] > 0)
		{
			ShowFontTestHud(i);
			active++;
		}
		else
		{
			ClearSyncHud(i, g_hFontTestSync);
		}
	}

	if (active == 0)
	{
		g_hFontTestTimer = null;
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

// 清掉某个客户端的一批行通道
void ClearRowSyncs(int client, int upTo)
{
	if (upTo > ROW_SYNC_COUNT)
	{
		upTo = ROW_SYNC_COUNT;
	}

	for (int i = 0; i < upTo; i++)
	{
		ClearSyncHud(client, g_hRowSync[i]);
	}
}

// 清掉某个客户端的一批名牌通道
void ClearTagSyncs(int client, int upTo)
{
	if (upTo > MAX_TAG_SLOTS)
	{
		upTo = MAX_TAG_SLOTS;
	}

	for (int i = 0; i < upTo; i++)
	{
		ClearSyncHud(client, g_hTagSync[i]);
	}
}

// ---------------------------------------------------------------------------
// 设置 / 定时器
// ---------------------------------------------------------------------------
void RefreshSettings()
{
	g_bEnabled    = g_cvEnabled.BoolValue;
	g_fInterval   = g_cvInterval.FloatValue;
	g_fHoldTime   = g_fInterval + 0.15;
	g_iMaxRows    = g_cvMaxRows.IntValue;
	g_iDetail     = g_cvDetail.IntValue;
	g_bShowSelf   = g_cvShowSelf.BoolValue;
	g_bAliveOnly  = g_cvAliveOnly.BoolValue;
	g_bShowHealth = g_cvShowHealth.BoolValue;
	g_iSort       = g_cvSort.IntValue;
	g_fPosX       = g_cvPosX.FloatValue;
	g_fPosY       = g_cvPosY.FloatValue;
	g_iColorMode  = g_cvColorMode.IntValue;
	g_iLang       = g_cvLang.IntValue;
	g_fLineHeight = g_cvLineHeight.FloatValue;
	g_bDebug      = g_cvDebug.BoolValue;

	g_bTagEnabled     = g_cvTagEnabled.BoolValue;
	g_iTagMode        = g_cvTagMode.IntValue;
	g_iTagColorMode   = g_cvTagColorMode.IntValue;
	g_fTagMaxDist     = g_cvTagMaxDist.FloatValue;
	g_fTagHeight      = g_cvTagHeight.FloatValue;
	g_bTagVisibleOnly = g_cvTagVisibleOnly.BoolValue;
	g_fTagInterval    = g_cvTagInterval.FloatValue;
	g_fTagFov         = g_cvTagFov.FloatValue;
	g_fTagAspect      = g_cvTagAspect.FloatValue;
	g_fTagCharWidth   = g_cvTagCharWidth.FloatValue;
	g_fTagHold        = g_fTagInterval + 0.10;
}

void RestartTimer()
{
	if (g_hTimer != null)
	{
		delete g_hTimer;
		g_hTimer = null;
	}

	if (g_bEnabled && g_fInterval > 0.0)
	{
		g_hTimer = CreateTimer(g_fInterval, Timer_DrawHud, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}
	else
	{
		ClearAllHuds();
	}

	RestartTagTimer();
}

void RestartTagTimer()
{
	if (g_hTagTimer != null)
	{
		delete g_hTagTimer;
		g_hTagTimer = null;
	}

	if (g_bTagEnabled && g_fTagInterval > 0.0)
	{
		g_hTagTimer = CreateTimer(g_fTagInterval, Timer_DrawTags, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}
	else
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i))
			{
				ClearTagSyncs(i, MAX_TAG_SLOTS);
				g_iPrevTags[i] = 0;
			}
		}
	}
}

void ClearAllHuds()
{
	if (g_hSync == null)
	{
		return;
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			ClearSyncHud(i, g_hSync);
			ClearRowSyncs(i, ROW_SYNC_COUNT);
			ClearTagSyncs(i, MAX_TAG_SLOTS);
			g_iPrevRows[i] = 0;
			g_iPrevTags[i] = 0;
		}
	}
}

public Action Timer_DrawHud(Handle timer)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i) || !g_bHudPref[i])
		{
			continue;
		}

		DrawHudForClient(i);
	}

	return Plugin_Continue;
}

// ---------------------------------------------------------------------------
// 网络属性偏移
// ---------------------------------------------------------------------------
// 依次尝试多个类名, 返回第一个查到的偏移 (-1 = 都没找到)
int FindPropOffsetAny(const char[] prop, const char[] classA, const char[] classB = "", const char[] classC = "")
{
	int offset = FindSendPropInfo(classA, prop);

	if (offset == -1 && classB[0] != '\0')
	{
		offset = FindSendPropInfo(classB, prop);
	}

	if (offset == -1 && classC[0] != '\0')
	{
		offset = FindSendPropInfo(classC, prop);
	}

	return offset;
}

void CacheOffsets()
{
	// 金钱: CS:S (含 CSSO 2.0) 与 CS:GO 都在 CCSPlayer 上, 找不到再退回玩家资源实体
	g_iAccountOffset = FindSendPropInfo("CCSPlayer", "m_iAccount");
	g_iPlayerResourceAccountOffset = FindSendPropInfo("CCSPlayerResource", "m_iAccount");

	// 护甲 / 头盔 / 拆弹器: 两个引擎都在 CCSPlayer 上
	g_iArmorOffset   = FindPropOffsetAny("m_ArmorValue", "CCSPlayer", "CBasePlayer");
	g_iHelmetOffset  = FindPropOffsetAny("m_bHasHelmet", "CCSPlayer", "CBasePlayer");
	g_iDefuserOffset = FindPropOffsetAny("m_bHasDefuser", "CCSPlayer", "CBasePlayer");

	// 武器列表: 定义在 CBaseCombatCharacter, CCSPlayer 的发送表里同样能查到
	g_iMyWeaponsOffset = FindPropOffsetAny("m_hMyWeapons", "CCSPlayer", "CBaseCombatCharacter", "CBasePlayer");

	// 弹匣 / CS:GO 的备弹属性
	g_iClipOffset        = FindPropOffsetAny("m_iClip1", "CBaseCombatWeapon", "CCSWeaponBase");
	g_iReserveAmmoOffset = FindPropOffsetAny("m_iPrimaryReserveAmmoCount", "CBaseCombatWeapon", "CCSWeaponBase");

	// CS:S / CSSO 的备弹: 玩家身上的 m_iAmmo 数组, 用武器的弹药类型索引
	PropFieldType fieldType = view_as<PropFieldType>(0);
	int numBits = 0;
	int localOffset = 0;
	int arraySize = 0;

	g_iAmmoArrayOffset = FindSendPropInfo("CBasePlayer", "m_iAmmo", fieldType, numBits, localOffset, arraySize);
	if (g_iAmmoArrayOffset == -1)
	{
		g_iAmmoArrayOffset = FindSendPropInfo("CCSPlayer", "m_iAmmo", fieldType, numBits, localOffset, arraySize);
	}

	if (arraySize > 0 && arraySize <= CS_MAX_AMMO_TYPES)
	{
		g_iAmmoArraySize = arraySize;
	}

	// 武器的弹药类型 (CS:S 里常是 datamap, 需要武器实体存在时才能定位 -> 懒加载)
	g_iAmmoTypeOffset = FindPropOffsetAny("m_iPrimaryAmmoType", "CBaseCombatWeapon", "CCSWeaponBase");
	if (g_iAmmoTypeOffset == -1)
	{
		g_bAmmoTypeTried = false;
	}

	if (g_bDebug)
	{
		PrintToServer("[CSSO 2.0] engine=%d (CSGO=12,CSS=13,SDK2013=14) | account=%d prAccount=%d weapons=%d clip=%d reserve=%d ammoArray=%d(size %d) armor=%d helmet=%d defuser=%d",
			view_as<int>(g_Engine), g_iAccountOffset, g_iPlayerResourceAccountOffset, g_iMyWeaponsOffset,
			g_iClipOffset, g_iReserveAmmoOffset, g_iAmmoArrayOffset, g_iAmmoArraySize,
			g_iArmorOffset, g_iHelmetOffset, g_iDefuserOffset);
	}

	if (g_iAccountOffset == -1 && g_iPlayerResourceAccountOffset == -1)
	{
		LogError("[CSSO 2.0] 找不到 m_iAccount, 经济将显示为 $0。");
	}

	if (g_iMyWeaponsOffset == -1)
	{
		LogError("[CSSO 2.0] 找不到 m_hMyWeapons, 将退回武器槽位方式 (道具统计可能不完整)。");
	}

	if (g_iReserveAmmoOffset == -1 && g_iAmmoArrayOffset == -1)
	{
		LogError("[CSSO 2.0] 找不到备弹属性 (m_iPrimaryReserveAmmoCount 和 m_iAmmo 都没有), 备弹与手雷数量将不显示。");
	}
}

// ---------------------------------------------------------------------------
// 数据读取
// ---------------------------------------------------------------------------
int CssoGetMoney(int client)
{
	if (g_iAccountOffset != -1)
	{
		return GetEntData(client, g_iAccountOffset);
	}

	if (g_iPlayerResourceAccountOffset != -1)
	{
		int resource = GetPlayerResourceEntity();
		if (resource != -1)
		{
			return GetEntData(resource, g_iPlayerResourceAccountOffset + (client * 4));
		}
	}

	return 0;
}

int CssoGetArmor(int client)
{
	if (g_iArmorOffset == -1)
	{
		return 0;
	}
	return GetEntData(client, g_iArmorOffset);
}

bool CssoHasHelmet(int client)
{
	if (g_iHelmetOffset == -1)
	{
		return false;
	}
	return GetEntData(client, g_iHelmetOffset) != 0;
}

bool CssoHasDefuser(int client)
{
	if (g_iDefuserOffset == -1)
	{
		return false;
	}
	return GetEntData(client, g_iDefuserOffset) != 0;
}

int CssoGetClip(int weapon)
{
	if (g_iClipOffset == -1)
	{
		return -1;
	}
	return GetEntData(weapon, g_iClipOffset);
}

// 武器的弹药类型索引 (CS:S 里 m_iPrimaryAmmoType 通常是 datamap, 需要真实实体才能定位)
int CssoGetAmmoType(int weapon)
{
	if (g_iAmmoTypeOffset != -1)
	{
		return GetEntData(weapon, g_iAmmoTypeOffset);
	}

	if (!g_bAmmoTypeTried)
	{
		g_bAmmoTypeTried = true;
		g_iAmmoTypeOffset = FindDataMapInfo(weapon, "m_iPrimaryAmmoType");

		if (g_bDebug && g_iAmmoTypeOffset != -1)
		{
			PrintToServer("[CSSO 2.0] m_iPrimaryAmmoType (datamap) offset = %d", g_iAmmoTypeOffset);
		}
	}

	if (g_iAmmoTypeOffset != -1)
	{
		return GetEntData(weapon, g_iAmmoTypeOffset);
	}

	return -1;
}

// 备弹: 优先玩家 m_iAmmo 数组 (CS:S / CSSO / CS:GO 都通用), 再退回 CS:GO 的武器自带备弹
int CssoGetReserveAmmo(int player, int weapon)
{
	int ammoType = CssoGetAmmoType(weapon);

	if (ammoType >= 0 && ammoType < g_iAmmoArraySize && g_iAmmoArrayOffset != -1)
	{
		int reserve = GetEntData(player, g_iAmmoArrayOffset + (ammoType * 4));
		if (reserve >= 0)
		{
			return reserve;
		}
	}

	if (g_iReserveAmmoOffset != -1)
	{
		int reserve = GetEntData(weapon, g_iReserveAmmoOffset);
		if (reserve >= 0)
		{
			return reserve;
		}
	}

	return -1;
}

// 投掷物数量: CS:S / CSSO 直接读 m_iAmmo[弹药类型]; CS:GO 退回 1 + 武器备弹
int CssoGetUtilityCount(int player, int weapon)
{
	int ammoType = CssoGetAmmoType(weapon);

	if (ammoType >= 0 && ammoType < g_iAmmoArraySize && g_iAmmoArrayOffset != -1)
	{
		int count = GetEntData(player, g_iAmmoArrayOffset + (ammoType * 4));
		if (count > 0)
		{
			return count;
		}
	}

	if (g_iReserveAmmoOffset != -1)
	{
		int extra = GetEntData(weapon, g_iReserveAmmoOffset);
		if (extra > 0)
		{
			return extra + 1;
		}
	}

	// 至少手里这一颗
	return 1;
}

// ---------------------------------------------------------------------------
// 武器
// ---------------------------------------------------------------------------
int CollectWeapons(int player, int[] weapons, int maxlen)
{
	int count = 0;

	if (g_iMyWeaponsOffset != -1)
	{
		// m_hMyWeapons 是 CBaseHandle 数组, 每个句柄 4 字节 (32/64 位服务器都是 4 字节)
		for (int i = 0; i < CS_MAX_WEAPONS && count < maxlen; i++)
		{
			int weapon = GetEntDataEnt2(player, g_iMyWeaponsOffset + (i * 4));
			if (weapon > 0 && IsValidEntity(weapon))
			{
				weapons[count++] = weapon;
			}
		}
	}
	else
	{
		// 退回武器槽位: 0=主武器 1=副武器 2=刀 3=投掷物 4=C4
		for (int slot = 0; slot <= 4 && count < maxlen; slot++)
		{
			int weapon = GetPlayerWeaponSlot(player, slot);
			if (weapon > 0 && IsValidEntity(weapon))
			{
				weapons[count++] = weapon;
			}
		}
	}

	return count;
}

int GetWeaponCategory(int weapon)
{
	char classname[64];
	if (!GetEntityClassname(weapon, classname, sizeof(classname)))
	{
		return WPN_NONE;
	}

	if (StrContains(classname, "weapon_knife") == 0)
	{
		return WPN_KNIFE;
	}

	int category = 0;
	if (g_hWeaponCat.GetValue(classname, category))
	{
		return category;
	}

	return WPN_NONE;
}

// ---------------------------------------------------------------------------
// 语言 (csso_hud_lang): 0=英文  1=中文标签+投掷物/装备  2=再加武器中文名
// ---------------------------------------------------------------------------
void PickText(char[] buffer, int maxlen, const char[] english, const char[] chinese)
{
	if (g_iLang > 0)
	{
		strcopy(buffer, maxlen, chinese);
	}
	else
	{
		strcopy(buffer, maxlen, english);
	}
}

bool GetWeaponDisplayName(int weapon, char[] buffer, int maxlen, int zhMinLang = 2)
{
	char classname[64];
	if (!GetEntityClassname(weapon, classname, sizeof(classname)))
	{
		return false;
	}

	if (g_iLang >= zhMinLang && g_hWeaponNameZh.GetString(classname, buffer, maxlen))
	{
		return true;
	}

	if (g_hWeaponName.GetString(classname, buffer, maxlen))
	{
		return true;
	}

	if (StrContains(classname, "weapon_knife") == 0)
	{
		PickText(buffer, maxlen, "KNIFE", "刀");
		return true;
	}

	if (StrContains(classname, "weapon_") == 0)
	{
		strcopy(buffer, maxlen, classname);
		ReplaceString(buffer, maxlen, "weapon_", "");
		return true;
	}

	return false;
}

void AddWeaponData(const char[] classname, const char[] display, int category, const char[] displayZh = "")
{
	g_hWeaponName.SetString(classname, display);

	if (displayZh[0] != '\0')
	{
		g_hWeaponNameZh.SetString(classname, displayZh);
	}

	g_hWeaponCat.SetValue(classname, category);
}

void BuildWeaponData()
{
	// 主武器
	AddWeaponData("weapon_ak47", "AK-47", WPN_PRIMARY, "AK47");
	AddWeaponData("weapon_m4a1", "M4A4", WPN_PRIMARY, "M4");
	AddWeaponData("weapon_m4a4", "M4A4", WPN_PRIMARY, "M4");          // CSSO 2.0 用的类名
	AddWeaponData("weapon_m4a1_silencer", "M4A1-S", WPN_PRIMARY, "M4消音");
	AddWeaponData("weapon_awp", "AWP", WPN_PRIMARY, "大狙");
	AddWeaponData("weapon_ssg08", "SSG08", WPN_PRIMARY, "鸟狙");
	AddWeaponData("weapon_aug", "AUG", WPN_PRIMARY, "AUG");
	AddWeaponData("weapon_sg556", "SG553", WPN_PRIMARY, "SG");
	AddWeaponData("weapon_sg553", "SG553", WPN_PRIMARY, "SG");        // CSSO 2.0 用的类名
	AddWeaponData("weapon_galilar", "GALIL", WPN_PRIMARY, "加利尔");
	AddWeaponData("weapon_famas", "FAMAS", WPN_PRIMARY, "法玛斯");
	AddWeaponData("weapon_g3sg1", "G3SG1", WPN_PRIMARY, "G3");
	AddWeaponData("weapon_scar20", "SCAR-20", WPN_PRIMARY, "SCAR");
	AddWeaponData("weapon_m249", "M249", WPN_PRIMARY, "M249");
	AddWeaponData("weapon_negev", "NEGEV", WPN_PRIMARY, "内格夫");
	AddWeaponData("weapon_mac10", "MAC-10", WPN_PRIMARY, "MAC10");
	AddWeaponData("weapon_mp9", "MP9", WPN_PRIMARY, "MP9");
	AddWeaponData("weapon_mp7", "MP7", WPN_PRIMARY, "MP7");
	AddWeaponData("weapon_mp5sd", "MP5-SD", WPN_PRIMARY, "MP5");
	AddWeaponData("weapon_ump45", "UMP-45", WPN_PRIMARY, "UMP");
	AddWeaponData("weapon_p90", "P90", WPN_PRIMARY, "P90");
	AddWeaponData("weapon_bizon", "BIZON", WPN_PRIMARY, "野牛");

	// 霰弹枪 (之前漏了, CS:GO 和 CSSO 2.0 都有)
	AddWeaponData("weapon_nova", "NOVA", WPN_PRIMARY, "新星");
	AddWeaponData("weapon_xm1014", "XM1014", WPN_PRIMARY, "XM1014");
	AddWeaponData("weapon_mag7", "MAG-7", WPN_PRIMARY, "MAG7");
	AddWeaponData("weapon_sawedoff", "SAWEDOFF", WPN_PRIMARY, "截短");

	// 副武器
	AddWeaponData("weapon_glock", "GLOCK", WPN_SECONDARY, "格洛克");
	AddWeaponData("weapon_glock18", "GLOCK", WPN_SECONDARY, "格洛克");    // CSSO 2.0 用的类名
	AddWeaponData("weapon_usp_silencer", "USP-S", WPN_SECONDARY, "USP");
	AddWeaponData("weapon_hkp2000", "P2000", WPN_SECONDARY, "P2000");
	AddWeaponData("weapon_elite", "DUAL", WPN_SECONDARY, "双枪");
	AddWeaponData("weapon_p250", "P250", WPN_SECONDARY, "P250");
	AddWeaponData("weapon_tec9", "TEC-9", WPN_SECONDARY, "TEC9");
	AddWeaponData("weapon_fiveseven", "5-7", WPN_SECONDARY, "57");
	AddWeaponData("weapon_cz75a", "CZ75", WPN_SECONDARY, "CZ75");
	AddWeaponData("weapon_deagle", "DEAGLE", WPN_SECONDARY, "沙鹰");
	AddWeaponData("weapon_revolver", "R8", WPN_SECONDARY, "R8");

	// 投掷物 (中文名很短, lang 1 就启用)
	AddWeaponData("weapon_flashbang", "FLASH", WPN_UTILITY, "闪");
	AddWeaponData("weapon_smokegrenade", "SMOKE", WPN_UTILITY, "烟");
	AddWeaponData("weapon_hegrenade", "HE", WPN_UTILITY, "雷");
	AddWeaponData("weapon_molotov", "MOLLY", WPN_UTILITY, "火");
	AddWeaponData("weapon_incgrenade", "INC", WPN_UTILITY, "燃");
	AddWeaponData("weapon_incendiarygrenade", "INC", WPN_UTILITY, "燃");  // CSSO 2.0 用的类名
	AddWeaponData("weapon_decoy", "DECOY", WPN_UTILITY, "诱");
	AddWeaponData("weapon_tagrenade", "TA", WPN_UTILITY, "战");

	// 其它
	AddWeaponData("weapon_c4", "C4", WPN_BOMB, "C4");
	AddWeaponData("weapon_taser", "ZEUS", WPN_TASER, "电击枪");
	AddWeaponData("weapon_healthshot", "MEDSHOT", WPN_MEDSHOT, "针");
}

// ---------------------------------------------------------------------------
// 装备汇总
// ---------------------------------------------------------------------------
void CollectEquipment(int player, char[] primary, int primaryLen, char[] secondary, int secondaryLen,
	char[] utility, int utilityLen, char[] extras, int extrasLen, bool detailed)
{
	int weapons[CS_MAX_WEAPONS];
	int count = CollectWeapons(player, weapons, sizeof(weapons));

	bool hasBomb = false;
	bool hasZeus = false;
	bool hasMedshot = false;
	bool hasKit = detailed ? CssoHasDefuser(player) : false;

	for (int i = 0; i < count; i++)
	{
		int weapon = weapons[i];
		int category = GetWeaponCategory(weapon);

		switch (category)
		{
			case WPN_PRIMARY, WPN_SECONDARY:
			{
				char display[32];
				char entry[64];

				if (!GetWeaponDisplayName(weapon, display, sizeof(display)))
				{
					continue;
				}

				int clip = CssoGetClip(weapon);
				int reserve = CssoGetReserveAmmo(player, weapon);

				if (clip >= 0 && reserve >= 0)
				{
					Format(entry, sizeof(entry), "%s %d/%d", display, clip, reserve);
				}
				else if (clip >= 0)
				{
					Format(entry, sizeof(entry), "%s %d", display, clip);
				}
				else
				{
					strcopy(entry, sizeof(entry), display);
				}

				if (category == view_as<int>(WPN_PRIMARY))
				{
					strcopy(primary, primaryLen, entry);
				}
				else
				{
					strcopy(secondary, secondaryLen, entry);
				}

				break;
			}
			case WPN_UTILITY:
			{
				if (!detailed)
				{
					continue;
				}

				char display[32];
				if (!GetWeaponDisplayName(weapon, display, sizeof(display), 1))
				{
					continue;
				}

				// CS:S / CSSO: m_iAmmo[弹药类型] 就是颗数; CS:GO: 1 + 武器备弹
				int grenadeCount = CssoGetUtilityCount(player, weapon);
				char tag[48];

				if (grenadeCount > 1)
				{
					Format(tag, sizeof(tag), "%sx%d", display, grenadeCount);
				}
				else
				{
					strcopy(tag, sizeof(tag), display);
				}

				if (utility[0] != '\0')
				{
					StrCat(utility, utilityLen, " ");
				}
				StrCat(utility, utilityLen, tag);
				break;
			}
			case WPN_BOMB:
			{
				hasBomb = true;
				break;
			}
			case WPN_TASER:
			{
				hasZeus = true;
				break;
			}
			case WPN_MEDSHOT:
			{
				hasMedshot = true;
				break;
			}
		}
	}

	if (!detailed)
	{
		return;
	}

	char label[24];

	if (hasKit)
	{
		if (extras[0] != '\0')
		{
			StrCat(extras, extrasLen, " ");
		}
		PickText(label, sizeof(label), "KIT", "钳");
		StrCat(extras, extrasLen, label);
	}

	if (hasBomb)
	{
		if (extras[0] != '\0')
		{
			StrCat(extras, extrasLen, " ");
		}
		StrCat(extras, extrasLen, "C4");
	}

	if (hasZeus)
	{
		if (extras[0] != '\0')
		{
			StrCat(extras, extrasLen, " ");
		}
		PickText(label, sizeof(label), "ZEUS", "电击");
		StrCat(extras, extrasLen, label);
	}

	if (hasMedshot)
	{
		if (extras[0] != '\0')
		{
			StrCat(extras, extrasLen, " ");
		}
		PickText(label, sizeof(label), "MEDSHOT", "针");
		StrCat(extras, extrasLen, label);
	}
}

// ---------------------------------------------------------------------------
// 单行文本
// ---------------------------------------------------------------------------
void FormatTeammateLine(int player, char[] buffer, int maxlen)
{
	char name[MAX_NAME_LENGTH];
	char line[LINE_BUFFER_SIZE];

	GetClientName(player, name, sizeof(name));

	Format(line, sizeof(line), "> %s  $%d", name, CssoGetMoney(player));

	if (!IsPlayerAlive(player))
	{
		char dead[24];
		PickText(dead, sizeof(dead), "  [DEAD]", "  [阵亡]");
		StrCat(line, sizeof(line), dead);
		strcopy(buffer, maxlen, line);
		return;
	}

	if (g_iDetail >= 1)
	{
		if (g_bShowHealth)
		{
			char hpLabel[8];
			char apLabel[8];
			char health[64];
			PickText(hpLabel, sizeof(hpLabel), "HP", "血");
			PickText(apLabel, sizeof(apLabel), "AP", "甲");
			Format(health, sizeof(health), "  %d%s %d%s%s",
				GetEntProp(player, Prop_Data, "m_iHealth"),
				hpLabel,
				CssoGetArmor(player),
				apLabel,
				CssoHasHelmet(player) ? "+" : "");
			StrCat(line, sizeof(line), health);
		}

		char primary[64];
		char secondary[64];
		char utility[160];
		char extras[64];
		primary[0] = '\0';
		secondary[0] = '\0';
		utility[0] = '\0';
		extras[0] = '\0';

		CollectEquipment(player, primary, sizeof(primary), secondary, sizeof(secondary),
			utility, sizeof(utility), extras, sizeof(extras), g_iDetail >= 2);

		if (primary[0] != '\0')
		{
			StrCat(line, sizeof(line), "  ");
			StrCat(line, sizeof(line), primary);
		}

		if (secondary[0] != '\0')
		{
			StrCat(line, sizeof(line), "  ");
			StrCat(line, sizeof(line), secondary);
		}

		if (utility[0] != '\0')
		{
			StrCat(line, sizeof(line), "  ");
			StrCat(line, sizeof(line), utility);
		}

		if (extras[0] != '\0')
		{
			StrCat(line, sizeof(line), "  ");
			StrCat(line, sizeof(line), extras);
		}
	}

	strcopy(buffer, maxlen, line);
}

// CSSO 2.0 原生队伍色 (取自模组 resource/clientscheme.res 的 TeamT / TeamCT)
void GetCssoTeamColor(int team, int &red, int &green, int &blue)
{
	if (team == CS_TEAM_T)
	{
		red = 234; green = 209; blue = 138;
	}
	else if (team == CS_TEAM_CT)
	{
		red = 181; green = 212; blue = 238;
	}
	else
	{
		red = 230; green = 230; blue = 230;
	}
}

void GetHudColor(int team, int &red, int &green, int &blue)
{
	if (g_iColorMode == 1)
	{
		red = 255; green = 255; blue = 255;
	}
	else if (g_iColorMode == 2)
	{
		red = 120; green = 255; blue = 120;
	}
	else if (g_iColorMode == 3)
	{
		red = 255; green = 190; blue = 80;
	}
	else if (g_iColorMode == 4)
	{
		red = 130; green = 230; blue = 255;
	}
	else if (g_iColorMode == COLOR_CSSO_NATIVE)
	{
		GetCssoTeamColor(team, red, green, blue);
	}
	else if (team == CS_TEAM_T)
	{
		red = 255; green = 176; blue = 74;      // T: 橙色
	}
	else
	{
		red = 110; green = 180; blue = 255;     // CT: 蓝色
	}
}

// 状态色 (csso_hud_color 5): 每行按这名队友自己的状态取色
void GetRowColor(int player, int &red, int &green, int &blue)
{
	if (!IsPlayerAlive(player))
	{
		red = 130; green = 130; blue = 130;      // 阵亡: 灰
		return;
	}

	int health = GetEntProp(player, Prop_Data, "m_iHealth");

	if (health <= 25)
	{
		red = 255; green = 80; blue = 80;        // 残血: 红
	}
	else if (health <= 60)
	{
		red = 255; green = 180; blue = 60;       // 掉血: 橙
	}
	else
	{
		GetCssoTeamColor(GetClientTeam(player), red, green, blue);
	}
}

// ---------------------------------------------------------------------------
// 头显绘制
// ---------------------------------------------------------------------------
void DrawHudForClient(int client)
{
	if (g_hSync == null)
	{
		return;
	}

	int team = GetClientTeam(client);
	if (team != CS_TEAM_T && team != CS_TEAM_CT)
	{
		// 观察者 / SourceTV / 未加入队伍
		ClearSyncHud(client, g_hSync);
		return;
	}

	int players[MAXPLAYERS + 1];
	int count = 0;
	int totalMoney = 0;
	int aliveCount = 0;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}

		if (GetClientTeam(i) != team)
		{
			continue;
		}

		if (i == client && !g_bShowSelf)
		{
			continue;
		}

		bool alive = IsPlayerAlive(i);
		if (!alive && g_bAliveOnly)
		{
			continue;
		}

		players[count++] = i;
		totalMoney += CssoGetMoney(i);

		if (alive)
		{
			aliveCount++;
		}
	}

	if (count == 0)
	{
		ClearSyncHud(client, g_hSync);
		ClearRowSyncs(client, 1 + g_iPrevRows[client]);
		g_iPrevRows[client] = 0;
		return;
	}

	if (g_iSort == 1)
	{
		// 按金钱从高到低 (插入排序)
		for (int i = 1; i < count; i++)
		{
			int key = players[i];
			int keyMoney = CssoGetMoney(key);
			int j = i - 1;

			while (j >= 0 && CssoGetMoney(players[j]) < keyMoney)
			{
				players[j + 1] = players[j];
				j--;
			}

			players[j + 1] = key;
		}
	}

	int rows = count;
	if (rows > g_iMaxRows)
	{
		rows = g_iMaxRows;
	}

	char header[HUD_BUFFER_SIZE];
	BuildHeader(team, totalMoney, count, aliveCount, header, sizeof(header));

	if (g_iColorMode == COLOR_STATUS)
	{
		// 状态色模式: 标题 + 每行各发一条独立消息, 才能各画各的颜色
		int red = 255;
		int green = 255;
		int blue = 255;

		ClearSyncHud(client, g_hSync);

		SetHudTextParams(g_fPosX, g_fPosY, g_fHoldTime, red, green, blue, 255, 0, 0.0, 0.0, 0.0);
		ShowSyncHudText(client, g_hRowSync[0], header);

		for (int i = 0; i < rows; i++)
		{
			char line[LINE_BUFFER_SIZE];
			FormatTeammateLine(players[i], line, sizeof(line));
			GetRowColor(players[i], red, green, blue);

			SetHudTextParams(g_fPosX, g_fPosY + float(i + 1) * g_fLineHeight, g_fHoldTime,
				red, green, blue, 255, 0, 0.0, 0.0, 0.0);
			ShowSyncHudText(client, g_hRowSync[1 + i], line);
		}

		for (int i = 1 + rows; i <= g_iPrevRows[client] && i < ROW_SYNC_COUNT; i++)
		{
			ClearSyncHud(client, g_hRowSync[i]);
		}

		g_iPrevRows[client] = rows;
		return;
	}

	if (g_iPrevRows[client] > 0)
	{
		ClearRowSyncs(client, 1 + g_iPrevRows[client]);
		g_iPrevRows[client] = 0;
	}

	char buffer[HUD_BUFFER_SIZE];
	strcopy(buffer, sizeof(buffer), header);

	for (int i = 0; i < rows; i++)
	{
		char line[LINE_BUFFER_SIZE];
		FormatTeammateLine(players[i], line, sizeof(line));
		StrCat(buffer, sizeof(buffer), "\n");
		StrCat(buffer, sizeof(buffer), line);
	}

	int red = 255;
	int green = 255;
	int blue = 255;
	GetHudColor(team, red, green, blue);

	SetHudTextParams(g_fPosX, g_fPosY, g_fHoldTime, red, green, blue, 255, 0, 0.0, 0.0, 0.0);
	ShowSyncHudText(client, g_hSync, buffer);
}

// 标题行: CSSO 2.0  |  T  |  经济 $1000 (平均 $500)  |  存活 3/5
void BuildHeader(int team, int totalMoney, int count, int aliveCount, char[] buffer, int maxlen)
{
	char teamName[8];
	char lblMoney[16];
	char lblAvg[16];
	char lblAlive[16];

	if (team == CS_TEAM_T)
	{
		strcopy(teamName, sizeof(teamName), "T");
	}
	else
	{
		strcopy(teamName, sizeof(teamName), "CT");
	}

	PickText(lblMoney, sizeof(lblMoney), "Money", "经济");
	PickText(lblAvg, sizeof(lblAvg), "avg", "平均");
	PickText(lblAlive, sizeof(lblAlive), "Alive", "存活");

	Format(buffer, maxlen, "%s  |  %s  |  %s $%d (%s $%d)  |  %s %d/%d",
		HUD_TAG, teamName, lblMoney, totalMoney, lblAvg, count > 0 ? totalMoney / count : 0,
		lblAlive, aliveCount, count);
}

// ---------------------------------------------------------------------------
// 头顶名牌 (Overhead Name Tag)
// ---------------------------------------------------------------------------
// 原理: CSSO 2.0 (Source 2013) 引擎里既没有世界坐标文字实体 (point_worldtext),
//       也没有 CS:GO 的 cl_teamid_overhead_always, 所以只能自己算投影:
//         1. 取队友头顶的世界坐标
//         2. 用观察者的眼位 / 视角 / FOV 投影成屏幕坐标 (0.0 - 1.0)
//         3. 每个名牌用一条独立 HUD 通道画在那个坐标上
//       名牌只发给同队的人, 并且可选"被墙挡住就不画", 所以不会变成透视挂。
// ---------------------------------------------------------------------------

// 队友头顶的世界坐标 (以眼睛为基准, 蹲下时也会跟着降低)
void GetTagWorldPos(int target, float pos[3])
{
	GetClientEyePosition(target, pos);
	pos[2] += g_fTagHeight;
}

// 观察者当前的水平视野角 (4:3 基准); 0 表示读取客户端 m_iFOV
float TagGetFov(int client)
{
	if (g_fTagFov > 0.0)
	{
		return g_fTagFov;
	}

	int fov = GetEntProp(client, Prop_Send, "m_iFOV");

	if (fov <= 0)
	{
		fov = 90;
	}

	return float(fov);
}

// 世界坐标 -> 屏幕坐标 (0.0 - 1.0)。返回 false = 在身后 / 贴脸 / 视野外
bool WorldToScreen(int client, const float world[3], float &sx, float &sy)
{
	float eye[3];
	float angles[3];
	float fwd[3];
	float right[3];
	float up[3];

	GetClientEyePosition(client, eye);
	GetClientEyeAngles(client, angles);
	GetAngleVectors(angles, fwd, right, up);

	float delta[3];
	delta[0] = world[0] - eye[0];
	delta[1] = world[1] - eye[1];
	delta[2] = world[2] - eye[2];

	float depth = delta[0] * fwd[0] + delta[1] * fwd[1] + delta[2] * fwd[2];

	if (depth <= 1.0)
	{
		// 身后或贴在镜头上
		return false;
	}

	float side = delta[0] * right[0] + delta[1] * right[1] + delta[2] * right[2];
	float high = delta[0] * up[0] + delta[1] * up[1] + delta[2] * up[2];

	// Source 的 fov 是 4:3 下的水平视野角, 垂直视野固定; 宽屏只是横向看到更多。
	float halfFov = DegToRad(TagGetFov(client)) * 0.5;
	float tanH = Tangent(halfFov);

	if (tanH <= 0.0001)
	{
		return false;
	}

	float tanV = tanH * (3.0 / 4.0);
	float scaleY = 0.5 / tanV;
	float scaleX = 0.5 / (tanV * g_fTagAspect);

	sx = 0.5 + (side / depth) * scaleX;
	sy = 0.5 - (high / depth) * scaleY;

	return true;
}

// 估算文本宽度 (用于水平居中): 中文 / 全角算 2 个单位, 其它算 1 个单位
float EstimateTextWidth(const char[] text)
{
	int units = 0;
	int i = 0;

	while (text[i] != '\0')
	{
		int c = text[i];

		if ((c & 0xC0) == 0x80)              // UTF-8 续字节, 前导字节已经计过
		{
			i++;
			continue;
		}

		if (c >= 0xF0)                       // 4 字节字符
		{
			units += 2;
			i += 4;
		}
		else if (c >= 0xE0)                  // 3 字节字符 (中文)
		{
			units += 2;
			i += 3;
		}
		else if (c >= 0xC0)                  // 2 字节字符
		{
			units += 1;
			i += 2;
		}
		else                                 // ASCII
		{
			units += 1;
			i++;
		}
	}

	return float(units) * g_fTagCharWidth;
}

// 只跳过"观察者自己"; 墙 / 门 / 玻璃都算遮挡
public bool TraceFilter_Tag(int entity, int contentsMask, any data)
{
	return entity != data;
}

// 视线判定: MASK_VISIBLE 不含玩家碰撞体, 所以只挡墙不挡人。
// 从观察者眼睛打到队友眼睛, 中间什么都没打到 = 看得见。
bool TagIsVisible(int viewer, int target)
{
	float eye[3];
	float targetEye[3];

	GetClientEyePosition(viewer, eye);
	GetClientEyePosition(target, targetEye);

	TR_TraceRayFilter(eye, targetEye, MASK_VISIBLE, RayType_EndPoint, TraceFilter_Tag, viewer);

	return !TR_DidHit();
}

// 名牌正文: 名字 + 血量% [+ 当前武器]
void BuildTagText(int target, char[] buffer, int maxlen)
{
	char name[MAX_NAME_LENGTH];
	GetClientName(target, name, sizeof(name));

	if (g_iTagMode == 2)
	{
		strcopy(buffer, maxlen, name);
		return;
	}

	int health = GetEntProp(target, Prop_Data, "m_iHealth");
	if (health < 0)
	{
		health = 0;
	}

	if (g_iTagMode == 1)
	{
		// 99 = 强制英文, 只有 csso_hud_lang 2 才用中文武器名
		int zhMin = (g_iLang >= 2) ? 2 : 99;
		char weapon[32];
		weapon[0] = '\0';

		int slot = GetPlayerWeaponSlot(target, CS_SLOT_PRIMARY);
		if (slot <= 0)
		{
			slot = GetPlayerWeaponSlot(target, CS_SLOT_SECONDARY);
		}

		if (slot > 0 && GetWeaponDisplayName(slot, weapon, sizeof(weapon), zhMin))
		{
			Format(buffer, maxlen, "%s %d%% %s", name, health, weapon);
			return;
		}
	}

	Format(buffer, maxlen, "%s %d%%", name, health);
}

void GetTagColor(int target, int &red, int &green, int &blue)
{
	if (g_iTagColorMode == TAG_COLOR_HEALTH)
	{
		int health = GetEntProp(target, Prop_Data, "m_iHealth");

		if (health > 60)
		{
			red = 140; green = 255; blue = 140;
		}
		else if (health > 30)
		{
			red = 255; green = 220; blue = 90;
		}
		else
		{
			red = 255; green = 90; blue = 90;
		}
		return;
	}

	if (g_iTagColorMode == TAG_COLOR_FIXED)
	{
		red = 255; green = 214; blue = 70;       // 截图那种黄
		return;
	}

	GetCssoTeamColor(GetClientTeam(target), red, green, blue);
}

void DrawTagsForClient(int client)
{
	if (!g_bTagEnabled || !g_bTagPref[client] || IsFakeClient(client))
	{
		if (g_iPrevTags[client] > 0)
		{
			ClearTagSyncs(client, g_iPrevTags[client]);
			g_iPrevTags[client] = 0;
		}
		return;
	}

	int team = GetClientTeam(client);

	if (!IsClientInGame(client) || (team != CS_TEAM_T && team != CS_TEAM_CT))
	{
		if (g_iPrevTags[client] > 0)
		{
			ClearTagSyncs(client, g_iPrevTags[client]);
			g_iPrevTags[client] = 0;
		}
		return;
	}

	float eye[3];
	GetClientEyePosition(client, eye);

	int drawn = 0;

	for (int i = 1; i <= MaxClients && drawn < MAX_TAG_SLOTS; i++)
	{
		if (i == client || !IsClientInGame(i) || !IsPlayerAlive(i))
		{
			continue;
		}

		if (GetClientTeam(i) != team)
		{
			continue;
		}

		float pos[3];
		GetTagWorldPos(i, pos);

		if (g_fTagMaxDist > 0.0 && GetVectorDistance(eye, pos) > g_fTagMaxDist)
		{
			continue;
		}

		float sx = 0.0;
		float sy = 0.0;

		if (!WorldToScreen(client, pos, sx, sy))
		{
			continue;
		}

		if (sx < -0.05 || sx > 1.05 || sy < -0.05 || sy > 1.05)
		{
			continue;
		}

		if (g_bTagVisibleOnly && !TagIsVisible(client, i))
		{
			continue;
		}

		char text[128];
		BuildTagText(i, text, sizeof(text));

		// 水平居中: 估算文本宽度后把左上角往左挪半个宽度
		float width = EstimateTextWidth(text);
		float x = sx - (width * 0.5);

		// HUD 文本以左上角为锚点, 往上抬一个字高, 名牌才是"浮在头顶"而不是盖住脑袋
		sy -= g_fTagCharWidth * 2.5;

		if (x < 0.0)
		{
			x = 0.0;
		}
		else if (x > 1.0 - width)
		{
			x = (1.0 - width > 0.0) ? (1.0 - width) : 0.0;
		}

		int red = 255;
		int green = 255;
		int blue = 255;
		GetTagColor(i, red, green, blue);

		SetHudTextParams(x, sy, g_fTagHold, red, green, blue, 255, 0, 0.0, 0.0, 0.0);
		ShowSyncHudText(client, g_hTagSync[drawn], text);

		drawn++;
	}

	for (int i = drawn; i < g_iPrevTags[client] && i < MAX_TAG_SLOTS; i++)
	{
		ClearSyncHud(client, g_hTagSync[i]);
	}

	g_iPrevTags[client] = drawn;
}

public Action Timer_DrawTags(Handle timer)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
		{
			continue;
		}

		DrawTagsForClient(i);
	}

	return Plugin_Continue;
}
