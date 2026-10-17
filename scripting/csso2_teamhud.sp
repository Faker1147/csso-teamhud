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
 *  平台: Counter-Strike: Global Offensive (legacy) + SourceMod 1.11 / 1.12
 *
 *  注意: SourceMod 官方至今不支持 CS2 (Counter-Strike 2)。
 *        CS2 服务器请使用 CounterStrikeSharp (C#) 版本, 本插件无法在 CS2 上运行。
 *
 *  编译: spcomp csso2_teamhud.sp      (SourceMod 1.11+, 推荐 1.12)
 * ============================================================================
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <clientprefs>

#define HUD_TAG             "CSSO 2.0"
#define CS_MAX_WEAPONS      64          // CS:GO 的 MAX_WEAPONS
#define HUD_BUFFER_SIZE     1024
#define LINE_BUFFER_SIZE    200

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
ConVar g_cvDebug;

Handle g_hTimer = null;
Handle g_hSync = null;
Handle g_hCookie = null;

StringMap g_hWeaponName = null;
StringMap g_hWeaponCat = null;

bool g_bHudPref[MAXPLAYERS + 1];

// 网络属性偏移 (查找失败为 -1)
int g_iAccountOffset = -1;
int g_iPlayerResourceAccountOffset = -1;
int g_iMyWeaponsOffset = -1;
int g_iClipOffset = -1;
int g_iReserveAmmoOffset = -1;
int g_iArmorOffset = -1;
int g_iHelmetOffset = -1;
int g_iDefuserOffset = -1;

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
bool  g_bDebug = false;

public Plugin myinfo =
{
	name        = "CSSO 2.0 - Team HUD",
	author      = "CSSO",
	description = "队友头显: 名字 / 经济 / 武器 / 道具 (CS:GO)",
	version     = "2.0.0",
	url         = ""
};

// ---------------------------------------------------------------------------
// 启动 / 卸载
// ---------------------------------------------------------------------------
public void OnPluginStart()
{
	if (GetEngineVersion() != Engine_CSGO)
	{
		SetFailState("CSSO 2.0 只能运行在 CS:GO 上 (SourceMod 目前不支持 CS2)。");
		return;
	}

	g_hWeaponName = new StringMap();
	g_hWeaponCat = new StringMap();
	BuildWeaponData();

	g_hSync = CreateHudSynchronizer();

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
	g_cvColorMode  = CreateConVar("csso_hud_color", "0", "颜色: 0=跟随队伍, 1=白, 2=绿, 3=橙, 4=青", FCVAR_NOTIFY, true, 0.0, true, 4.0);
	g_cvDebug      = CreateConVar("csso_hud_debug", "0", "1=把偏移信息输出到服务器控制台", FCVAR_NOTIFY, true, 0.0, true, 1.0);

	CreateConVar("csso_hud_version", "2.0.0", "CSSO 2.0 版本号", FCVAR_NOTIFY | FCVAR_DONTRECORD);

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
	g_cvDebug.AddChangeHook(OnConVarChanged);

	g_hCookie = RegClientCookie("csso2_hud", "CSSO 2.0 队友头显开关", CookieAccess_Private);

	RegConsoleCmd("sm_teamhud", Command_ToggleHud, "开关 CSSO 2.0 队友头显");
	RegConsoleCmd("sm_thud", Command_ToggleHud, "开关 CSSO 2.0 队友头显");
	RegAdminCmd("sm_csso_reload", Command_Reload, ADMFLAG_CONFIG, "重新载入 CSSO 2.0 头显设置");

	AutoExecConfig(true, "csso2");
	CacheOffsets();
	RefreshSettings();
}

public void OnMapStart()
{
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

	ClearAllHuds();

	delete g_hWeaponName;
	delete g_hWeaponCat;
}

// ---------------------------------------------------------------------------
// 客户端
// ---------------------------------------------------------------------------
public void OnClientPutInServer(int client)
{
	g_bHudPref[client] = true;
}

public void OnClientCookiesCached(int client)
{
	char value[8];
	GetClientCookie(client, g_hCookie, value, sizeof(value));

	if (value[0] != '\0')
	{
		g_bHudPref[client] = (value[0] == '1');
	}
}

public void OnClientDisconnect(int client)
{
	g_bHudPref[client] = true;

	if (IsClientInGame(client))
	{
		ClearSyncHud(client, g_hSync);
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

public Action Command_Reload(int client, int args)
{
	RefreshSettings();
	RestartTimer();
	ReplyToCommand(client, "[CSSO 2.0] Settings reloaded. HUD is now %s.", g_bEnabled ? "ON" : "OFF");
	return Plugin_Handled;
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
	g_bDebug      = g_cvDebug.BoolValue;
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
void CacheOffsets()
{
	g_iAccountOffset = FindSendPropInfo("CCSPlayer", "m_iAccount");
	if (g_iAccountOffset == -1)
	{
		g_iPlayerResourceAccountOffset = FindSendPropInfo("CCSPlayerResource", "m_iAccount");
	}

	g_iMyWeaponsOffset    = FindSendPropInfo("CCSPlayer", "m_hMyWeapons");
	g_iClipOffset         = FindSendPropInfo("CBaseCombatWeapon", "m_iClip1");
	g_iReserveAmmoOffset  = FindSendPropInfo("CBaseCombatWeapon", "m_iPrimaryReserveAmmoCount");
	g_iArmorOffset        = FindSendPropInfo("CCSPlayer", "m_ArmorValue");
	g_iHelmetOffset       = FindSendPropInfo("CCSPlayer", "m_bHasHelmet");
	g_iDefuserOffset      = FindSendPropInfo("CCSPlayer", "m_bHasDefuser");

	if (g_bDebug)
	{
		PrintToServer("[CSSO 2.0] offsets: account=%d prAccount=%d weapons=%d clip=%d reserve=%d armor=%d helmet=%d defuser=%d",
			g_iAccountOffset, g_iPlayerResourceAccountOffset, g_iMyWeaponsOffset,
			g_iClipOffset, g_iReserveAmmoOffset, g_iArmorOffset, g_iHelmetOffset, g_iDefuserOffset);
	}

	if (g_iAccountOffset == -1 && g_iPlayerResourceAccountOffset == -1)
	{
		LogError("[CSSO 2.0] 找不到 m_iAccount, 经济将显示为 $0。");
	}

	if (g_iMyWeaponsOffset == -1)
	{
		LogError("[CSSO 2.0] 找不到 m_hMyWeapons, 将退回武器槽位方式 (道具统计可能不完整)。");
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

int CssoGetReserveAmmo(int weapon)
{
	if (g_iReserveAmmoOffset == -1)
	{
		return -1;
	}
	return GetEntData(weapon, g_iReserveAmmoOffset);
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

bool GetWeaponDisplayName(int weapon, char[] buffer, int maxlen)
{
	char classname[64];
	if (!GetEntityClassname(weapon, classname, sizeof(classname)))
	{
		return false;
	}

	if (g_hWeaponName.GetString(classname, buffer, maxlen))
	{
		return true;
	}

	if (StrContains(classname, "weapon_knife") == 0)
	{
		strcopy(buffer, maxlen, "KNIFE");
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

void AddWeaponData(const char[] classname, const char[] display, int category)
{
	g_hWeaponName.SetString(classname, display);
	g_hWeaponCat.SetValue(classname, category);
}

void BuildWeaponData()
{
	// 主武器
	AddWeaponData("weapon_ak47", "AK-47", WPN_PRIMARY);
	AddWeaponData("weapon_m4a1", "M4A4", WPN_PRIMARY);
	AddWeaponData("weapon_m4a1_silencer", "M4A1-S", WPN_PRIMARY);
	AddWeaponData("weapon_awp", "AWP", WPN_PRIMARY);
	AddWeaponData("weapon_ssg08", "SSG08", WPN_PRIMARY);
	AddWeaponData("weapon_aug", "AUG", WPN_PRIMARY);
	AddWeaponData("weapon_sg556", "SG553", WPN_PRIMARY);
	AddWeaponData("weapon_galilar", "GALIL", WPN_PRIMARY);
	AddWeaponData("weapon_famas", "FAMAS", WPN_PRIMARY);
	AddWeaponData("weapon_g3sg1", "G3SG1", WPN_PRIMARY);
	AddWeaponData("weapon_scar20", "SCAR-20", WPN_PRIMARY);
	AddWeaponData("weapon_m249", "M249", WPN_PRIMARY);
	AddWeaponData("weapon_negev", "NEGEV", WPN_PRIMARY);
	AddWeaponData("weapon_mac10", "MAC-10", WPN_PRIMARY);
	AddWeaponData("weapon_mp9", "MP9", WPN_PRIMARY);
	AddWeaponData("weapon_mp7", "MP7", WPN_PRIMARY);
	AddWeaponData("weapon_mp5sd", "MP5-SD", WPN_PRIMARY);
	AddWeaponData("weapon_ump45", "UMP-45", WPN_PRIMARY);
	AddWeaponData("weapon_p90", "P90", WPN_PRIMARY);
	AddWeaponData("weapon_bizon", "BIZON", WPN_PRIMARY);

	// 副武器
	AddWeaponData("weapon_glock", "GLOCK", WPN_SECONDARY);
	AddWeaponData("weapon_usp_silencer", "USP-S", WPN_SECONDARY);
	AddWeaponData("weapon_hkp2000", "P2000", WPN_SECONDARY);
	AddWeaponData("weapon_elite", "DUAL", WPN_SECONDARY);
	AddWeaponData("weapon_p250", "P250", WPN_SECONDARY);
	AddWeaponData("weapon_tec9", "TEC-9", WPN_SECONDARY);
	AddWeaponData("weapon_fiveseven", "5-7", WPN_SECONDARY);
	AddWeaponData("weapon_cz75a", "CZ75", WPN_SECONDARY);
	AddWeaponData("weapon_deagle", "DEAGLE", WPN_SECONDARY);
	AddWeaponData("weapon_revolver", "R8", WPN_SECONDARY);

	// 投掷物
	AddWeaponData("weapon_flashbang", "FLASH", WPN_UTILITY);
	AddWeaponData("weapon_smokegrenade", "SMOKE", WPN_UTILITY);
	AddWeaponData("weapon_hegrenade", "HE", WPN_UTILITY);
	AddWeaponData("weapon_molotov", "MOLLY", WPN_UTILITY);
	AddWeaponData("weapon_incgrenade", "INC", WPN_UTILITY);
	AddWeaponData("weapon_decoy", "DECOY", WPN_UTILITY);
	AddWeaponData("weapon_tagrenade", "TA", WPN_UTILITY);

	// 其它
	AddWeaponData("weapon_c4", "C4", WPN_BOMB);
	AddWeaponData("weapon_taser", "ZEUS", WPN_TASER);
	AddWeaponData("weapon_healthshot", "MEDSHOT", WPN_MEDSHOT);
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
				int reserve = CssoGetReserveAmmo(weapon);

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
				if (!GetWeaponDisplayName(weapon, display, sizeof(display)))
				{
					continue;
				}

				// 手里的 1 颗 + 备弹里的额外数量 (例如 2 颗闪光)
				int extra = CssoGetReserveAmmo(weapon);
				char tag[48];

				if (extra > 0)
				{
					Format(tag, sizeof(tag), "%sx%d", display, extra + 1);
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

	if (hasKit)
	{
		if (extras[0] != '\0')
		{
			StrCat(extras, extrasLen, " ");
		}
		StrCat(extras, extrasLen, "KIT");
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
		StrCat(extras, extrasLen, "ZEUS");
	}

	if (hasMedshot)
	{
		if (extras[0] != '\0')
		{
			StrCat(extras, extrasLen, " ");
		}
		StrCat(extras, extrasLen, "MEDSHOT");
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
		StrCat(line, sizeof(line), "  [DEAD]");
		strcopy(buffer, maxlen, line);
		return;
	}

	if (g_iDetail >= 1)
	{
		if (g_bShowHealth)
		{
			char health[64];
			Format(health, sizeof(health), "  %dHP %dAP%s",
				GetEntProp(player, Prop_Data, "m_iHealth"),
				CssoGetArmor(player),
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
	else if (team == CS_TEAM_T)
	{
		red = 255; green = 176; blue = 74;      // T: 橙色
	}
	else
	{
		red = 110; green = 180; blue = 255;     // CT: 蓝色
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

	char buffer[HUD_BUFFER_SIZE];
	char teamName[8];

	if (team == CS_TEAM_T)
	{
		strcopy(teamName, sizeof(teamName), "T");
	}
	else
	{
		strcopy(teamName, sizeof(teamName), "CT");
	}

	Format(buffer, sizeof(buffer), "%s  |  %s  |  Money $%d (avg $%d)  |  Alive %d/%d",
		HUD_TAG, teamName, totalMoney, totalMoney / count, aliveCount, count);

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
