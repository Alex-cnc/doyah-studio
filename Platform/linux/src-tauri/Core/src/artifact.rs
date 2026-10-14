//! 交付物身份四项（§8.6.3）：**目录 / 标签 / `sha256` / 构建时刻**。
//!
//! 为什么在领域层：它是**纯数据 + 纯校验**（不读盘、不算哈希 —— 哈希由构建入口算完再喂进来），
//! 所以四端同形、可单测。构建入口（`Platform/linux/build.sh`）与身份卡都从这里取形状，
//! 不许各自拼一份字符串（判据面 = 本模块的单测 + 构建入口收尾的打印格式）。

/// 身份四项。字段顺序 = 身份卡上的既有顺序，不另排。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ArtifactIdentity {
    pub directory: String,
    pub label: String,
    pub sha256: String,
    pub built_at: String,
}

/// 身份四项的拒收理由（**认不出就拒收，不静默兜底**）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum IdentityError {
    /// 目录为空
    EmptyDirectory,
    /// 标签（包文件名）为空
    EmptyLabel,
    /// `sha256` 不是 64 位十六进制（小写归一后判）
    MalformedSha256,
    /// 构建时刻为空（形态由构建入口给，领域层不规定时区/格式）
    EmptyBuiltAt,
}

impl ArtifactIdentity {
    /// 四项一起给、一起校验：任何一项坏 ⇒ 整份拒收（不许半份身份卡）。
    pub fn new(
        directory: &str,
        label: &str,
        sha256: &str,
        built_at: &str,
    ) -> Result<Self, IdentityError> {
        if directory.trim().is_empty() {
            return Err(IdentityError::EmptyDirectory);
        }
        if label.trim().is_empty() {
            return Err(IdentityError::EmptyLabel);
        }
        let hash = sha256.trim().to_ascii_lowercase();
        if hash.len() != 64 || !hash.bytes().all(|b| b.is_ascii_hexdigit()) {
            return Err(IdentityError::MalformedSha256);
        }
        if built_at.trim().is_empty() {
            return Err(IdentityError::EmptyBuiltAt);
        }
        Ok(Self {
            directory: directory.trim().to_string(),
            label: label.trim().to_string(),
            sha256: hash,
            built_at: built_at.trim().to_string(),
        })
    }

    /// 身份卡正文（与 `build.sh` 收尾打印的四行同款：一行一项，中文键名）。
    pub fn identity_card(&self) -> String {
        format!(
            "目录={}\n标签={}\nsha256={}\n构建时刻={}\n",
            self.directory, self.label, self.sha256, self.built_at
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const HASH: &str = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789ABCDEF";

    #[test]
    fn accepts_full_identity_and_normalizes_hash_case() {
        let id = ArtifactIdentity::new("/tmp/bundle", "doyah-studio_0.3.0_amd64.deb", HASH, "2026-10-14T10:00:00+08:00")
            .expect("四项齐且哈希合法 ⇒ 收");
        assert_eq!(id.sha256.len(), 64);
        assert!(id.sha256.chars().all(|c| !c.is_ascii_uppercase()), "哈希按小写归一");
        assert!(id.identity_card().contains("标签=doyah-studio_0.3.0_amd64.deb"));
    }

    #[test]
    fn rejects_empty_directory() {
        assert_eq!(
            ArtifactIdentity::new("  ", "a.deb", HASH, "t"),
            Err(IdentityError::EmptyDirectory)
        );
    }

    #[test]
    fn rejects_empty_label() {
        assert_eq!(
            ArtifactIdentity::new("/d", "", HASH, "t"),
            Err(IdentityError::EmptyLabel)
        );
    }

    #[test]
    fn rejects_short_or_non_hex_hash() {
        assert_eq!(
            ArtifactIdentity::new("/d", "a.deb", "abc", "t"),
            Err(IdentityError::MalformedSha256)
        );
        assert_eq!(
            ArtifactIdentity::new("/d", "a.deb", &"z".repeat(64), "t"),
            Err(IdentityError::MalformedSha256)
        );
    }

    #[test]
    fn rejects_empty_built_at() {
        assert_eq!(
            ArtifactIdentity::new("/d", "a.deb", HASH, " "),
            Err(IdentityError::EmptyBuiltAt)
        );
    }
}
