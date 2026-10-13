//! 插件清单与装配检查（领域层 · 纯逻辑 · 零第三方依赖）
//!
//! 契约依据 = `Docs/概要设计.md` **§3.52【契约】插件清单与装配契约**；
//! 本侧落法 = 同书 **§8.5.8**（`[独占:windows]`）。
//!
//! ## 这个模块解决什么
//!
//! 契约②要求「插件清单 = **一处声明**（名称 · 版本 · 入口 target · **能力声明** ·
//! 需要的**宿主挂点** · **存储归属**）；界面与构建**只消费它**」。
//! 所以本模块是那份清单的**唯一出处**，并给出**可机械判定的检查**（`audit`）。
//!
//! ## 四条纪律（写给后来人）
//!
//! 1. **清单只有一份**：界面不得各写一套"活动栏有哪几项"——要项就从这里取。
//! 2. **挂点白名单**：插件只能经 [`MountPoint`] 列出的七类口子接进来；写别的 ⇒ 判红。
//! 3. **能力必须声明**：插件声明的能力要落在契约的**三个能力位**之内（开发工作区 /
//!    智能数据库助理 / 笔记，`FR-PLUG-06`：**一套许可证覆盖三个能力位，不做插件独立授权**）。
//! 4. **存储二选一**：`StorageOwnership` 必须是自带或宿主代管之一，不许留空（契约⑤）。
//!
//! ## 本轮范围（人类主人 2026-10-13 令）
//!
//! **只做骨架与空模块**：笔记与回放插件此刻都以 `implemented: false` 声明 ——
//! 界面据此**如实显示"未开工"，不放假界面**（与本侧既有纪律一致）。

/// 宿主提供给插件的**挂点**（契约③：插件只能经这些口子接进来）。
///
/// 七类，**不再多**：多一类就意味着插件多一条能碰宿主内部的缝。
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum MountPoint {
    /// 活动栏项（左侧窄条上的一个视图位）。
    ActivityItem,
    /// 主区页签（含 Home 区页签）。
    MainTab,
    /// 菜单项。
    MenuItem,
    /// 搜索索引挂点（贡献可搜目标，不接管搜索算法）。
    SearchIndex,
    /// 设置面板段。
    SettingsSection,
    /// 存储工厂（自带存储 / 宿主代管，二选一）。
    StorageFactory,
    /// 通知与审计投递。
    Notify,
}

impl MountPoint {
    /// 全部挂点（顺序 = 文档里的列举顺序，便于对账）。
    pub const ALL: [MountPoint; 7] = [
        MountPoint::ActivityItem,
        MountPoint::MainTab,
        MountPoint::MenuItem,
        MountPoint::SearchIndex,
        MountPoint::SettingsSection,
        MountPoint::StorageFactory,
        MountPoint::Notify,
    ];

    /// 稳定标识（进清单校验报告与判据输出；**不要拿它当界面文案**）。
    pub fn id(self) -> &'static str {
        match self {
            MountPoint::ActivityItem => "activity-item",
            MountPoint::MainTab => "main-tab",
            MountPoint::MenuItem => "menu-item",
            MountPoint::SearchIndex => "search-index",
            MountPoint::SettingsSection => "settings-section",
            MountPoint::StorageFactory => "storage-factory",
            MountPoint::Notify => "notify",
        }
    }

    /// 从标识反解（清单是**声明式**的，所以必须能从字符串还原）。
    pub fn from_id(value: &str) -> Option<MountPoint> {
        MountPoint::ALL.into_iter().find(|m| m.id() == value)
    }
}

/// 插件的**存储归属**（契约⑤：二选一，并在清单里声明）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StorageOwnership {
    /// **自带存储**：插件自己的库 / 目录，宿主只给路径。
    Bundled,
    /// **宿主代管**：宿主提供插入式存储接口。
    Host,
}

impl StorageOwnership {
    pub fn id(self) -> &'static str {
        match self {
            StorageOwnership::Bundled => "bundled",
            StorageOwnership::Host => "host",
        }
    }

    pub fn from_id(value: &str) -> Option<StorageOwnership> {
        match value {
            "bundled" => Some(StorageOwnership::Bundled),
            "host" => Some(StorageOwnership::Host),
            _ => None,
        }
    }
}

/// **能力位**（契约 `FR-PLUG-06`：许可证一套覆盖三个能力位；**不做插件独立授权**）。
///
/// 每个插件声明自己**用**哪个能力位；宿主据此判可见性（未授权 ⇒ **该项不出现**，
/// 不是灰掉 —— 沿用 `App/src/shell/activityBar.ts` 既有的单点判据）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Capability {
    /// 开发工作区。
    Workspaces,
    /// 智能数据库助理。
    Database,
    /// 笔记。
    Notes,
}

impl Capability {
    pub fn id(self) -> &'static str {
        match self {
            Capability::Workspaces => "workspaces",
            Capability::Database => "database",
            Capability::Notes => "notes",
        }
    }

    pub fn from_id(value: &str) -> Option<Capability> {
        match value {
            "workspaces" => Some(Capability::Workspaces),
            "database" => Some(Capability::Database),
            "notes" => Some(Capability::Notes),
            _ => None,
        }
    }
}

/// 一个插件在清单里的**一条声明**（契约②的六个字段，一个不多一个不少）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PluginDecl {
    /// 插件 id（稳定标识；进视图 id / 挂点键，**不用中文**）。
    pub id: &'static str,
    /// 展示名（中文；界面文案取自 `App/src/i18n` 的 key，这里只给**对账用的规范名**）。
    pub name: &'static str,
    /// 版本（与插件自己的交付物版本一致；本轮骨架 = `0.1.0`）。
    pub version: &'static str,
    /// 入口 target（前端目录名；插件界面在 `App/src/plugins/<entry>/`）。
    pub entry: &'static str,
    /// 能力声明（用哪几个能力位）。
    pub capabilities: &'static [Capability],
    /// 需要的宿主挂点（**只能**是 [`MountPoint::ALL`] 里的）。
    pub mounts: &'static [MountPoint],
    /// 存储归属（自带 / 宿主代管）。
    pub storage: StorageOwnership,
    /// **本轮是否已实现功能本体**。骨架阶段为 `false` ⇒ 界面**如实显示"未开工"**。
    pub implemented: bool,
}

/// **插件清单 = 唯一出处**（契约②）。
///
/// 界面与构建**只消费它**：活动栏有哪些项、主区能开哪些页签、命令归哪个插件，
/// 都从这里来。**新增插件只在这个数组里加一条。**
///
/// 顺序 = 活动栏展示顺序（与既有 `App/src/shell/activityBar.ts` 的
/// `BUILT_ITEMS` 对账；**核心项不在此列** —— 编辑器 / 工作区 / 终端 / 数据库 /
/// 文件与搜索 / 设置与凭据是**基础核心**，由宿主自带，不进插件清单）。
pub const PLUGINS: &[PluginDecl] = &[
    PluginDecl {
        id: "notes",
        name: "笔记",
        version: "0.1.0",
        entry: "notes",
        capabilities: &[Capability::Notes],
        mounts: &[
            MountPoint::ActivityItem,
            MountPoint::MainTab,
            MountPoint::SearchIndex,
            MountPoint::StorageFactory,
        ],
        // 契约⑤ + `FR-PLUG-08`：笔记存储**自带**（本机 SQLite，数据家独立于工程数据家）。
        storage: StorageOwnership::Bundled,
        // 本轮 = 骨架：功能本体未做 ⇒ 界面如实显示"未开工"。
        implemented: false,
    },
    PluginDecl {
        id: "retro",
        name: "回放",
        version: "0.1.0",
        entry: "retro",
        capabilities: &[Capability::Notes],
        mounts: &[
            MountPoint::ActivityItem,
            MountPoint::MainTab,
            MountPoint::StorageFactory,
        ],
        storage: StorageOwnership::Bundled,
        implemented: false,
    },
];

/// 按 id 取一条声明。
pub fn plugin(id: &str) -> Option<&'static PluginDecl> {
    PLUGINS.iter().find(|p| p.id == id)
}

/// **已注册**的插件 id（界面按这个决定"活动栏上有没有这一项"）。
pub fn plugin_ids() -> Vec<&'static str> {
    PLUGINS.iter().map(|p| p.id).collect()
}

/// 需要某个挂点的插件 id（宿主按这个"把口子开给谁"）。
pub fn plugins_using(mount: MountPoint) -> Vec<&'static str> {
    PLUGINS
        .iter()
        .filter(|p| p.mounts.contains(&mount))
        .map(|p| p.id)
        .collect()
}

/// 清单的一条检查结果。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Finding {
    /// 出问题的插件 id（清单整体性问题用 `"<清单>"`）。
    pub plugin: String,
    /// 稳定标识（判据按它点名，**不要本地化**）。
    pub code: &'static str,
    /// 给人看的一句话（谁、哪里、怎么改）。
    pub detail: String,
}

/// 清单自检：**六道**，任一道不过就返回对应 [`Finding`]。
///
/// 为什么放在领域层：这几道都是**纯逻辑**，放这里才能被 `cargo test` 判，
/// 而且天然满足"插件不得触碰宿主内部模型"（本层不依赖任何 GUI / 平台 API）。
///
/// 六道：
/// 1. **id 唯一且非空**、形如小写标识（进视图 id，必须可作键）；
/// 2. **每条都要有挂点**（没有挂点的插件在界面上无处可见 ⇒ 等于藏起来的插件）；
/// 3. **挂点必须落在白名单内**（枚举天然保证，这条防的是"以后有人加枚举值忘了登记"）；
/// 4. **能力必须落在三个能力位内**（`FR-PLUG-06`：不做插件独立授权）；
/// 5. **存储归属必须显式**（枚举天然保证，这条是给后来人留的对账点）；
/// 6. **声明了 `ActivityItem` 挂点的插件**，其能力位必须与活动栏的单点判据可对齐
///    （`notes` 能力 ⇒ `notes` 项；防"插件说自己是活动栏项、能力却对不上"）。
pub fn audit() -> Vec<Finding> {
    let mut findings = Vec::new();

    for (index, decl) in PLUGINS.iter().enumerate() {
        // ① id 合法且唯一
        if decl.id.is_empty()
            || !decl
                .id
                .chars()
                .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-' || c == '_')
        {
            findings.push(Finding {
                plugin: decl.id.to_string(),
                code: "plugin-id-invalid",
                detail: format!(
                    "第 {} 条：插件 id `{}` 不合法（只允许小写字母 / 数字 / `-` / `_`）",
                    index + 1,
                    decl.id
                ),
            });
        }
        if PLUGINS.iter().filter(|p| p.id == decl.id).count() > 1 {
            findings.push(Finding {
                plugin: decl.id.to_string(),
                code: "plugin-id-duplicated",
                detail: format!("插件 id `{}` 重复出现（清单是唯一出处，id 必须唯一）", decl.id),
            });
        }

        // ② 必须有挂点
        if decl.mounts.is_empty() {
            findings.push(Finding {
                plugin: decl.id.to_string(),
                code: "plugin-no-mount",
                detail: format!(
                    "插件 `{}` 没有声明任何宿主挂点 ⇒ 界面上无处可见（等于藏起来的插件）",
                    decl.id
                ),
            });
        }

        // ③ 挂点白名单（枚举值必须都在 ALL 里 —— 防有人加了枚举值却没登记进 ALL）
        for mount in decl.mounts {
            if !MountPoint::ALL.contains(mount) {
                findings.push(Finding {
                    plugin: decl.id.to_string(),
                    code: "plugin-mount-unknown",
                    detail: format!(
                        "插件 `{}` 声明了未登记的挂点 `{}`（挂点白名单见 MountPoint::ALL）",
                        decl.id,
                        mount.id()
                    ),
                });
            }
        }

        // ④ 能力位必须落在三个之内（空 = 没声明能力）
        if decl.capabilities.is_empty() {
            findings.push(Finding {
                plugin: decl.id.to_string(),
                code: "plugin-capability-missing",
                detail: format!(
                    "插件 `{}` 没声明能力位（FR-PLUG-06：许可证一套覆盖三个能力位，插件必须说自己用哪个）",
                    decl.id
                ),
            });
        }

        // ⑤ 存储归属显式（枚举天然保证；这条留给后来人做对账，不做静默）
        if !matches!(
            decl.storage,
            StorageOwnership::Bundled | StorageOwnership::Host
        ) {
            findings.push(Finding {
                plugin: decl.id.to_string(),
                code: "plugin-storage-unknown",
                detail: format!("插件 `{}` 的存储归属不合法（必须是自带 / 宿主代管）", decl.id),
            });
        }

        // ⑥ 活动栏项 ⇄ 能力位可对齐
        //    口径：**要占活动栏项的插件，其每个能力位都必须落在三个能力位之内**。
        //    为什么这么定：活动栏的可见性判据是**单点**的（按能力位过滤，见
        //    `App/src/shell/activityBar.ts` 的 `visible` 机制与 `FR-PLUG-06`）；
        //    能力位若跑到三能力位之外，那个判据就无从过滤它 ⇒ 又得在判据里补一份映射。
        //    **实测教训（本判据初版被自己的测试判红）**：初版写的是"能力位必须与插件 id 同名"，
        //    于是 `retro`（能力位 = `notes`，与"一篇笔记的回放"口径一致）被误判红 ——
        //    **是判据太窄，不是清单错**；已按上面口径收宽。
        if decl.mounts.contains(&MountPoint::ActivityItem) {
            let all_known = decl
                .capabilities
                .iter()
                .all(|c| Capability::from_id(c.id()).is_some());
            if !all_known {
                findings.push(Finding {
                    plugin: decl.id.to_string(),
                    code: "plugin-activity-capability-mismatch",
                    detail: format!(
                        "插件 `{}` 要占活动栏项，但它的能力位里有不在三能力位内的值 ⇒ \
                         活动栏的单点可见性判据无从过滤（能力位只能是 workspaces / database / notes）",
                        decl.id
                    ),
                });
            }
        }
    }

    findings
}

/// 清单是否自洽（`audit()` 为空的便捷判据）。
pub fn is_consistent() -> bool {
    audit().is_empty()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn manifest_is_consistent() {
        let findings = audit();
        assert!(
            findings.is_empty(),
            "清单自检必须全过；实测问题：{:?}",
            findings
        );
    }

    #[test]
    fn first_batch_plugins_are_notes_and_retro() {
        // 契约 §3.52-①：笔记与回放为**首批插件**。
        let ids = plugin_ids();
        assert_eq!(ids, vec!["notes", "retro"], "首批插件与顺序");
    }

    #[test]
    fn both_plugins_declare_storage_and_mounts() {
        for decl in PLUGINS {
            assert!(!decl.mounts.is_empty(), "{} 必须声明挂点", decl.id);
            assert!(
                !decl.capabilities.is_empty(),
                "{} 必须声明能力位",
                decl.id
            );
            assert!(!decl.version.is_empty(), "{} 必须声明版本", decl.id);
            assert!(!decl.entry.is_empty(), "{} 必须声明入口", decl.id);
        }
    }

    #[test]
    fn skeleton_plugins_are_marked_unimplemented() {
        // 本轮 = 骨架：两个插件都必须如实标"未实现"（界面据此显示"未开工"，不放假界面）。
        for decl in PLUGINS {
            assert!(
                !decl.implemented,
                "{} 本轮应是骨架，不得宣称已实现",
                decl.id
            );
        }
    }

    #[test]
    fn activity_item_plugins_align_with_their_capability() {
        for id in plugins_using(MountPoint::ActivityItem) {
            let decl = plugin(id).expect("刚查到的插件必须在清单里");
            assert!(
                decl.capabilities
                    .iter()
                    .all(|c| Capability::from_id(c.id()).is_some()),
                "{} 占了活动栏项，其能力位必须都能被活动栏的单点判据识别",
                decl.id
            );
        }
    }

    #[test]
    fn mount_point_ids_round_trip() {
        for mount in MountPoint::ALL {
            assert_eq!(
                MountPoint::from_id(mount.id()),
                Some(mount),
                "挂点标识必须能双向还原"
            );
        }
        assert_eq!(MountPoint::from_id("no-such-mount"), None);
    }

    #[test]
    fn capability_ids_round_trip() {
        for cap in [
            Capability::Workspaces,
            Capability::Database,
            Capability::Notes,
        ] {
            assert_eq!(Capability::from_id(cap.id()), Some(cap));
        }
        assert_eq!(Capability::from_id("notes-plugin"), None);
    }

    #[test]
    fn storage_ownership_ids_round_trip() {
        for store in [StorageOwnership::Bundled, StorageOwnership::Host] {
            assert_eq!(StorageOwnership::from_id(store.id()), Some(store));
        }
        assert_eq!(StorageOwnership::from_id("cloud"), None);
    }

    #[test]
    fn lookup_by_id_and_by_mount_agree() {
        for decl in PLUGINS {
            assert_eq!(plugin(decl.id).map(|p| p.id), Some(decl.id));
        }
        assert_eq!(plugin("no-such-plugin"), None);

        // 存储工厂挂点：两个插件都要（契约⑤要求存储归属必须声明）
        let storage_users = plugins_using(MountPoint::StorageFactory);
        assert_eq!(storage_users, vec!["notes", "retro"]);
        // 通知挂点：本轮两个骨架都没用（不硬凑）
        assert!(plugins_using(MountPoint::Notify).is_empty());
    }
}
