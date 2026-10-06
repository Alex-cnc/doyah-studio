//! **按类型打开**的判定（FR-EDIT-32 那一半 / 计划 2.3：文件类型识别与按类型打开）
//!
//! 由头：工作区里不只放代码 —— 还有图片、二进制、超大的日志。全都往编辑面里塞，
//! 结果是"打开一个 3 MB 的 min.js 卡住"或"一张 PNG 显示成一屏乱码"。所以打开之前
//! **先判这是什么、该怎么打开**，判不出来就**如实说判不出来**（不硬塞进编辑面）。
//!
//! 判定顺序（**先看内容，再看扩展名**）：内容里的"魔数"比扩展名可信 ——
//! 把 `.txt` 改成 `.png` 的照片、或存成 `.dat` 的图片都是真实存在的。
//!
//! 三条口径：
//! 1. **图片按内容认**（PNG / JPEG / GIF / WebP / BMP 的魔数），认出来就走图片查看；
//! 2. **前 8 KiB 含 NUL ⇒ 当二进制**（与检索那边的口径一致，别处两套判据迟早打架）；
//! 3. **太大就不往编辑面里塞**（上限与检索同一档），如实说"太大，本版不读全文"。

/// 编辑器直接打开的大小上限（与检索同一档）。
pub const MAX_EDITABLE_BYTES: u64 = 2 * 1024 * 1024;
/// 判二进制时探多少字节（与检索同一档）。
pub const PROBE_BYTES: usize = 8192;

/// 认出来的图片格式。
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ImageFormat {
    Png,
    Jpeg,
    Gif,
    Webp,
    Bmp,
}

impl ImageFormat {
    /// 给界面用的 MIME（`data:` 前缀要用它）。
    pub const fn mime(self) -> &'static str {
        match self {
            ImageFormat::Png => "image/png",
            ImageFormat::Jpeg => "image/jpeg",
            ImageFormat::Gif => "image/gif",
            ImageFormat::Webp => "image/webp",
            ImageFormat::Bmp => "image/bmp",
        }
    }

    /// 中文名（界面上说"这是一张 PNG 图"比说 `image/png` 友好）。
    pub const fn label(self) -> &'static str {
        match self {
            ImageFormat::Png => "PNG",
            ImageFormat::Jpeg => "JPEG",
            ImageFormat::Gif => "GIF",
            ImageFormat::Webp => "WebP",
            ImageFormat::Bmp => "BMP",
        }
    }
}

/// 该怎么打开这个文件。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
// 注意：`rename_all` 只管**变体名**，不管结构体变体里的**字段名** ——
// 字段要用 `rename_all_fields`（我第一版只写了前者，序列化出来是 `language_key`
// 而不是 `languageKey`，前端按 camelCase 取就会拿到 undefined）。
#[serde(rename_all = "camelCase", rename_all_fields = "camelCase", tag = "kind")]
pub enum OpenAs {
    /// 当文本打开（可编辑面 + 高亮）
    Text { language_key: String },
    /// 当图片打开（界面上走图片预览，**不进编辑面**）
    Image { format: ImageFormat },
    /// 二进制（**本版不解析**，如实说）
    Binary,
    /// 太大（如实说上限，不截断）
    TooLarge { bytes: u64, limit: u64 },
}

/// 认魔数（**只看开头几个字节**；不是完整格式校验）。
pub fn image_format(bytes: &[u8]) -> Option<ImageFormat> {
    if bytes.starts_with(&[0x89, b'P', b'N', b'G', 0x0d, 0x0a, 0x1a, 0x0a]) {
        return Some(ImageFormat::Png);
    }
    if bytes.starts_with(&[0xff, 0xd8, 0xff]) {
        return Some(ImageFormat::Jpeg);
    }
    if bytes.starts_with(b"GIF87a") || bytes.starts_with(b"GIF89a") {
        return Some(ImageFormat::Gif);
    }
    // WebP：`RIFF....WEBP`
    if bytes.len() >= 12 && bytes.starts_with(b"RIFF") && &bytes[8..12] == b"WEBP" {
        return Some(ImageFormat::Webp);
    }
    if bytes.starts_with(b"BM") {
        return Some(ImageFormat::Bmp);
    }
    None
}

/// 判二进制：前 `PROBE_BYTES` 含 NUL（与检索同一口径）。
pub fn looks_binary(bytes: &[u8]) -> bool {
    let probe = &bytes[..bytes.len().min(PROBE_BYTES)];
    probe.contains(&0)
}

/// 判定"该怎么打开"。
///
/// `whole_size` = 文件的完整大小（可能比 `head` 长得多：只读头部就够判类型，别把大文件全读进来）。
pub fn decide(head: &[u8], whole_size: u64, language_key: &str) -> OpenAs {
    // ① 图片优先（内容比扩展名可信）
    if let Some(format) = image_format(head) {
        return OpenAs::Image { format };
    }
    // ② 太大 ⇒ 如实说（**不截断、也不硬塞**）
    if whole_size > MAX_EDITABLE_BYTES {
        return OpenAs::TooLarge {
            bytes: whole_size,
            limit: MAX_EDITABLE_BYTES,
        };
    }
    // ③ 含 NUL ⇒ 二进制
    if looks_binary(head) {
        return OpenAs::Binary;
    }
    // ④ 其余当文本（语言键由调用方按路径推好；推不出就是纯文本）
    OpenAs::Text {
        language_key: language_key.to_string(),
    }
}

/// 给界面的一句说明（**说出下一步**，不只说"不支持"）。
pub fn explain(open_as: &OpenAs) -> Option<String> {
    match open_as {
        OpenAs::Text { .. } => None,
        OpenAs::Image { format } => Some(format!("这是一张 {} 图，按图片查看（不进编辑面）。", format.label())),
        OpenAs::Binary => Some(
            "这看起来是二进制文件（内容里有 NUL 字节），本版不解析它。要看的话用「在终端打开」或系统工具。"
                .to_string(),
        ),
        OpenAs::TooLarge { bytes, limit } => Some(format!(
            "这个文件太大（{bytes} 字节，上限 {limit} 字节），本版不读全文 —— **不截断给你看半份**。"
        )),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn images_are_recognised_by_magic_bytes_not_by_extension() {
        // 各种真实文件头
        assert_eq!(
            image_format(&[0x89, b'P', b'N', b'G', 0x0d, 0x0a, 0x1a, 0x0a, 0, 0]),
            Some(ImageFormat::Png)
        );
        assert_eq!(image_format(&[0xff, 0xd8, 0xff, 0xe0]), Some(ImageFormat::Jpeg));
        assert_eq!(image_format(b"GIF89a...."), Some(ImageFormat::Gif));
        assert_eq!(image_format(b"RIFF____WEBPVP8 "), Some(ImageFormat::Webp));
        assert_eq!(image_format(b"BM______"), Some(ImageFormat::Bmp));
        // 不是图片的
        assert_eq!(image_format(b"plain text"), None);
        assert_eq!(image_format(b""), None);
        // RIFF 但不是 WEBP（比如 wav）⇒ **不认**（免得把音频当图片）
        assert_eq!(image_format(b"RIFF____WAVEfmt "), None);
        // MIME 与中文名
        assert_eq!(ImageFormat::Png.mime(), "image/png");
        assert_eq!(ImageFormat::Jpeg.label(), "JPEG");
    }

    #[test]
    fn decide_prefers_content_over_extension() {
        // `.txt` 里装的是 PNG ⇒ 按图片打开（扩展名会说谎，内容不会）
        let png_header = [0x89, b'P', b'N', b'G', 0x0d, 0x0a, 0x1a, 0x0a];
        assert_eq!(
            decide(&png_header, 100, "lang.plainText"),
            OpenAs::Image {
                format: ImageFormat::Png
            }
        );
        // 普通文本
        assert_eq!(
            decide(b"fn main() {}", 12, "lang.rust"),
            OpenAs::Text {
                language_key: "lang.rust".to_string()
            }
        );
    }

    #[test]
    fn binary_and_too_large_are_reported_truthfully() {
        // 含 NUL ⇒ 二进制
        assert_eq!(decide(b"abc\0def", 7, "lang.plainText"), OpenAs::Binary);
        assert!(looks_binary(&[0u8; 4]));
        assert!(!looks_binary(b"no nul here"));
        // 空文件当文本（不是二进制）
        assert_eq!(
            decide(b"", 0, "lang.plainText"),
            OpenAs::Text {
                language_key: "lang.plainText".to_string()
            }
        );
        // 太大 ⇒ 报出真实大小与上限（**不截断**）
        let decision = decide(b"small head", MAX_EDITABLE_BYTES + 1, "lang.json");
        match decision {
            OpenAs::TooLarge { bytes, limit } => {
                assert_eq!(bytes, MAX_EDITABLE_BYTES + 1);
                assert_eq!(limit, MAX_EDITABLE_BYTES);
            }
            other => panic!("应当是 TooLarge，实际 {other:?}"),
        }
        // 恰好等于上限 ⇒ 还是文本（上限是"≤"）
        assert!(matches!(
            decide(b"x", MAX_EDITABLE_BYTES, "lang.json"),
            OpenAs::Text { .. }
        ));
        // 图片即使很大也按图片走（不因为大小拒掉图片）
        let png = [0x89, b'P', b'N', b'G', 0x0d, 0x0a, 0x1a, 0x0a];
        assert!(matches!(
            decide(&png, MAX_EDITABLE_BYTES * 10, "lang.plainText"),
            OpenAs::Image { .. }
        ));
    }

    #[test]
    fn explanations_say_what_to_do_next() {
        // 文本不需要解释（**不打扰**）
        assert!(explain(&OpenAs::Text {
            language_key: "lang.rust".into()
        })
        .is_none());
        // 其余三类都要说清并给出下一步
        let image = explain(&OpenAs::Image {
            format: ImageFormat::Gif,
        })
        .unwrap();
        assert!(image.contains("GIF") && image.contains("图片查看"));
        let binary = explain(&OpenAs::Binary).unwrap();
        assert!(binary.contains("二进制") && binary.contains("终端"), "要给出下一步");
        let large = explain(&OpenAs::TooLarge {
            bytes: 5_000_000,
            limit: MAX_EDITABLE_BYTES,
        })
        .unwrap();
        assert!(large.contains("太大") && large.contains("不截断"));
    }

    #[test]
    fn decision_serialises_with_a_kind_tag() {
        let text = serde_json::to_string(&OpenAs::Text {
            language_key: "lang.rust".into(),
        })
        .unwrap();
        assert!(text.contains("\"kind\":\"text\""), "{text}");
        assert!(text.contains("\"languageKey\""), "{text}");
        let back: OpenAs = serde_json::from_str(&text).unwrap();
        assert!(matches!(back, OpenAs::Text { .. }));
        let image = serde_json::to_string(&OpenAs::Image {
            format: ImageFormat::Png,
        })
        .unwrap();
        assert!(image.contains("\"png\""), "{image}");
    }
}
