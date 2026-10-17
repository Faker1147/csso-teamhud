# CSSO 2.0 — 队友头显 (Team HUD)

> CS 服务器插件（**CSSO 2.0** / CS:S / CS:GO）：在 HUD 上实时显示**队友的名字 / 经济 / 武器 / 道具**。

[![Build](https://github.com/Faker1147/csso-teamhud/actions/workflows/build.yml/badge.svg)](https://github.com/Faker1147/csso-teamhud/actions/workflows/build.yml)
[![Release](https://img.shields.io/github/v/release/Faker1147/csso-teamhud?include_prereleases&label=release)](https://github.com/Faker1147/csso-teamhud/releases)
[![License](https://img.shields.io/github/license/Faker1147/csso-teamhud?label=license)](LICENSE)
![SourceMod](https://img.shields.io/badge/SourceMod-1.11%2B-blue)
![Platform](https://img.shields.io/badge/platform-CSSO%202.0%20%7C%20CS%3AS%20%7C%20CS%3AGO-orange)

---

## 效果预览

```
CSSO 2.0  |  T  |  Money $12450 (avg $2490)  |  Alive 3/5
> PlayerOne  $4750  100HP 100AP+  AK-47 30/90  USP-S 12/24  FLASHx2 SMOKE HE KIT
> Two  $3200  87HP 100AP  AWP 10/30  GLOCK 20/120  SMOKE MOLLY
> Three  $0  [DEAD]
```

| 片段 | 含义 |
| --- | --- |
| `Money $12450 (avg $2490)` | 队伍总经济 + 人均，一眼看出该 eco 还是全买 |
| `100HP 100AP+` | 血量 / 护甲（`+` = 有头盔） |
| `AK-47 30/90` | 主武器（弹匣 / 备弹） |
| `USP-S 12/24` | 副武器 |
| `FLASHx2 SMOKE HE` | 道具，`x2` = 身上两颗 |
| `KIT / C4 / ZEUS / MEDSHOT` | 拆弹器 / C4 / 电击枪 / 医疗针 |
| `[DEAD]` | 阵亡队友（默认保留，方便看下一局经济） |

---

## ⚠️ 平台说明（重要）

| 平台 | 能否使用 | 备注 |
| --- | --- | --- |
| **CSSO 2.0**（Source Offensive，Source 2013 + cstrike 内容） | ✅ | 本插件的主要适配目标，属性映射已按其武器脚本核对 |
| **Counter-Strike: Source** | ✅ | 与 CSSO 2.0 同一套属性（`CCSPlayer`） |
| **CS:GO**（legacy 服务器） | ✅ | 备弹走 CS:GO 专用属性，两套逻辑都保留 |
| **CS2**（Counter-Strike 2） | ❌ | SourceMod 官方**至今不支持 CS2**，需改用 CounterStrikeSharp (C#) |

核对依据：SourceMod 官方仓库 `master` 分支（2026-10 仍在更新）中，CS 系列 gamedata 只有
[`engine "csgo"` 和 `game "cstrike"`](https://github.com/alliedmodders/sourcemod/blob/master/gamedata/sm-cstrike.games/master.games.txt)，
最新稳定版 1.12 也未加入 CS2。因此"SourceMod + CS2"目前不存在。

插件**不做硬性引擎拦截**：CSSO 2.0 用的是自定义 gamedir（`csso`），引擎识别值不保证是标准
CS 引擎，所以插件只把识别结果写进日志，真正的兼容性交给属性查找的多类名回退 + 降级逻辑。

### 引擎差异怎么处理的

| 数据 | CSSO 2.0 / CS:S | CS:GO |
| --- | --- | --- |
| 金钱 | `CCSPlayer::m_iAccount` | 同左 |
| 护甲 / 头盔 / 拆弹器 | `m_ArmorValue` / `m_bHasHelmet` / `m_bHasDefuser` | 同左 |
| 武器列表 | `m_hMyWeapons`（4 字节 `CBaseHandle` 数组） | 同左 |
| 弹匣 | `m_iClip1` | 同左 |
| 备弹 | 玩家 `m_iAmmo[武器的 m_iPrimaryAmmoType]` | `m_iPrimaryReserveAmmoCount` |
| 手雷数量 | 直接是 `m_iAmmo[弹药类型]` | 1 + 武器备弹 |

备弹优先读 `m_iAmmo` 数组（两种引擎都通用），读不到才退回 `m_iPrimaryReserveAmmoCount`；
`m_iAmmo` 的元素偏移靠武器的 `m_iPrimaryAmmoType`（CS:S 里是 datamap，插件会在第一次拿到
武器实体时懒加载定位）。全部失败时备弹自动省略，不影响其它字段。

---

## 功能

- **经济**：每人当前金钱 + 队伍总经济 + 人均
- **武器**：主武器 / 副武器，带 `弹匣/备弹`（读不到备弹时自动省略）
- **道具**：闪光弹、烟雾弹、高爆手雷、燃烧瓶、燃烧弹、诱饵弹、战术手雷，支持 `x2` 计数
- **装备**：拆弹器 KIT、C4、电击枪 ZEUS、医疗针 MEDSHOT、护甲与头盔
- **排序**：默认按金钱从高到低，最多显示 N 名队友
- **玩家开关**：`!teamhud` 自己关掉，用 Cookie 持久化，换图不掉
- **配置丰富**：坐标 / 刷新间隔 / 显示级别 / 颜色 / 生死过滤，共 12 个 CVar，改完即时生效
- **健壮性**：所有网络属性偏移查找失败都有降级路径；`csso_hud_debug 1`（偏移）与
  `sm_csso_dump`（单个玩家的完整实测数据）双通道排错

---

## 安装

1. 服务器安装 **Metamod:Source** + **SourceMod 1.11 或更高（推荐 1.12）**。
2. 到 [Releases](https://github.com/Faker1147/csso-teamhud/releases) 下载 `csso2_teamhud.smx`，放到服务器对应目录：

   ```
   CSSO 2.0 :  <服务器>/csso/addons/sourcemod/plugins/csso2_teamhud.smx
   CS:S     :  <服务器>/cstrike/addons/sourcemod/plugins/csso2_teamhud.smx
   CS:GO    :  <服务器>/csgo/addons/sourcemod/plugins/csso2_teamhud.smx
   ```

3. （可选）配置文件放到 `addons/sourcemod/../cfg/sourcemod/csso2.cfg`（即 `<游戏目录>/cfg/sourcemod/csso2.cfg`）；不放也行，插件首次加载会自动生成。
4. 换图生效，或控制台执行 `sm plugins load csso2_teamhud`。
5. `sm plugins list` 里出现 `CSSO 2.0 - Team HUD` 即成功。

---

## 编译

### 方法一：GitHub Actions 自动编译（推荐）

把代码推上去，[workflow](.github/workflows/build.yml) 会自动拉取最新的 SourceMod 并编译：

- 每次 push / PR → 编译结果作为 **Artifact** 上传
- 打 `v*` 标签 → 自动创建 Release 并把 `.smx` 挂上去

发布新版本：

```bash
git tag v2.1.0 && git push origin v2.1.0
```

### 方法二：本地 spcomp

```bash
# Windows
addons\sourcemod\scripting\spcomp.exe scripting\csso2_teamhud.sp -ocompiled\csso2_teamhud.smx

# Linux
./addons/sourcemod/scripting/spcomp scripting/csso2_teamhud.sp -ocompiled/csso2_teamhud.smx
```

### 方法三：双击 `compile.bat`

会自动去几个常见位置找 `spcomp.exe`；找不到就用记事本打开，把 `set "SPC="` 改成完整路径。

### 方法四：服务器自带

把 `.sp` 丢进服务器的 `addons/sourcemod/scripting/`，Windows 双击 `compile.exe`，
Linux 执行 `./compile.sh`，输出在 `scripting/compiled/`。

> ⚠️ 注意：如果报 `sourcemod.inc(81): expected token "function", but found "-identifier-"`
> 之类"看不懂 include"的错，说明**服务器的 `scripting/include` 与 `spcomp.exe` 版本不一致**
> （常见于手工覆盖过 include 的安装）。用版本匹配的编译器，或直接用上面的 GitHub Actions 产物。

---

## 命令

| 命令 | 权限 | 说明 |
| --- | --- | --- |
| `sm_teamhud` / `sm_thud` | 所有人 | 开关自己的头显（Cookie 保存，换图/重进仍生效） |
| `sm_csso_reload` | 服务器管理 | 重新加载配置并重启刷新定时器 |
| `sm_csso_dump` | 服务器管理 | 把**你本人**的实测数据（引擎识别值、所有属性偏移、每把武器的类名/弹匣/弹药类型/备弹、当前 HUD 行）打到控制台和 SourceMod 日志，用来排错 |

---

## CVar

| CVar | 默认 | 说明 |
| --- | --- | --- |
| `csso_hud_enabled` | 1 | 总开关 |
| `csso_hud_interval` | 0.2 | 刷新间隔（秒），建议 0.1 ~ 0.5 |
| `csso_hud_max_rows` | 5 | 最多显示几名队友（1 ~ 8） |
| `csso_hud_detail` | 2 | 0 = 名字+钱 / 1 = +血甲武器 / 2 = +道具装备 |
| `csso_hud_show_self` | 1 | 是否显示自己 |
| `csso_hud_alive_only` | 0 | 1 = 只显示活人 |
| `csso_hud_health` | 1 | 显示血量 / 护甲 / 头盔 |
| `csso_hud_sort` | 1 | 0 = 玩家顺序，1 = 按金钱排序 |
| `csso_hud_x` / `csso_hud_y` | 0.02 / 0.40 | 屏幕坐标（0 ~ 1），默认避开雷达和血条 |
| `csso_hud_color` | 0 | 0 = 队伍色(T橙/CT蓝)，1 白，2 绿，3 橙，4 青 |
| `csso_hud_debug` | 0 | 1 = 把引擎识别值和所有属性偏移打到服务器控制台 |

---

## 项目结构

```
csso-teamhud/
├─ .github/workflows/build.yml   # CI：自动编译 + Tag 自动发 Release
├─ cfg/sourcemod/csso2.cfg       # 参考配置（插件也会自动生成）
├─ scripting/csso2_teamhud.sp    # 源码，单文件
├─ compile.bat                   # 本地一键编译
├─ LICENSE                       # MIT
└─ README.md
```

---

## 实现要点

- **不是**用旧的 usermessage 硬拼文本，而是 `CreateHudSynchronizer()` +
  `SetHudTextParams()` + `ShowSyncHudText()`；一个定时器刷全部玩家，使用独立 sync 通道，
  不会和别的插件抢 HUD。
- **队友列表**：`GetClientTeam()` 比对，默认按金钱插入排序，取前 `max_rows` 名。
- **金钱**：`FindSendPropInfo("CCSPlayer", "m_iAccount")`（CS:S / CSSO 2.0 实测同类名可用）；
  找不到自动退回 `CCSPlayerResource` 的 `m_iAccount + client*4`。偏移在 `OnPluginStart` / `OnMapStart` 缓存。
- **武器**：遍历 `m_hMyWeapons`（64 格，`CBaseHandle` 每个 4 字节，32/64 位服务器都是 4 字节），
  用 `GetEntDataEnt2()` 取实体；找不到偏移时退回 `GetPlayerWeaponSlot()`。
  `weapon_*` 类名经 `StringMap` 映射为 `AK-47 / AWP / USP-S` 这类短名；
  类名表同时收录 CS:GO 与 CSSO 2.0 两套写法（如 `weapon_m4a1` / `weapon_m4a4`、
  `weapon_glock` / `weapon_glock18`、`weapon_sg556` / `weapon_sg553`、
  `weapon_incgrenade` / `weapon_incendiarygrenade`），外加四把霰弹枪。
- **道具**：`m_iAmmo[武器的 m_iPrimaryAmmoType]` 直接就是颗数（CSSO 2.0 / CS:S），
  CS:GO 则退回"1 + `m_iPrimaryReserveAmmoCount`"；两种情况都输出 `FLASHx2` 这种格式。
- **护甲/头盔/拆弹器**：`m_ArmorValue` / `m_bHasHelmet` / `m_bHasDefuser`（两平台同类名）。
- **属性查找全部多类名回退**：`CCSPlayer` → `CBasePlayer` / `CCSWeaponBase` / `CBaseCombatWeapon`，
  某个属性整条链都找不到时只影响对应字段并写一条 `LogError`，不会让插件失效。
- **HUD 只输出 ASCII**：CS:GO 的 HUD 字体渲染中文会乱码或丢失，因此画面内全部英文缩写；
  中文只出现在注释、配置、聊天提示和本文档中。
- 客户端开关用 `clientprefs` Cookie 持久化。

---

## FAQ

**装上去 HUD 不显示？**

1. `sm plugins list` 看插件有没有加载成功（CSSO 2.0 / CS:S / CS:GO 都支持，CS2 不支持）。
2. 看 `addons/sourcemod/logs/errors_*.log` 和最新的 `L<日期>.log`。
3. 进游戏执行 `sm_csso_dump`：会在 SourceMod 日志里留下一份完整实测数据，
   能直接看出是哪个属性没读到（偏移全 `-1` 就是属性名不对）。
4. 控制台 `csso_hud_debug 1` 后换图，检查偏移是否都打印出有效值。
5. 位置可能被雷达/血条挡住，调 `csso_hud_x` / `csso_hud_y`。

**为什么旧版本在 CSSO 2.0 上直接报错不加载？**
2.0.0 版本硬编码了"只在 CS:GO 上运行"，而 CSSO 2.0 是 Source 2013 + `csso` gamedir，
所以被 `SetFailState` 拦下。2.1.0 起改成只警告、不拦载，并按引擎差异走不同的备弹/道具读法。

**手雷数量或备弹不对？**
`sm_csso_dump` 会打印每把武器的 `ammoType` 和 `reserve_or_count`。
若 `ammoType=-1`，说明这把武器读不到 `m_iPrimaryAmmoType`（datamap 未定位），
此时备弹会省略、手雷按 1 颗显示 —— 其它字段仍然正常。

**金钱显示 `$0`？**
两个 `m_iAccount` 偏移都没找到（游戏大更新可能改属性名）。开 `csso_hud_debug 1` 确认后，
在 `CacheOffsets()` 里改属性名。

**能显示敌人的吗？**
刻意不做 —— 那就是透视外挂，比赛服必然违规。本插件只显示同队。

**为什么没有中文？**
CS:GO 的 HUD 字体对 UTF-8 中文支持很差。若你服务器换了支持中文的 HUD 字体，
把 `BuildWeaponData()` 里的显示名改成中文即可。

---

## 许可证

[MIT](LICENSE) © 2026 Faker1147

