import DoyahCore
import SwiftUI

/// 星空紫「星云皮肤」（星空紫「星云皮肤」· 2026-10-01 需求提出者要的「皮肤」质感；派单 `T-20261001-031`／`T-20261001-037`；队列 `L-153`）。
///
/// **为什么要有这一层**：需求提出者 2026-10-01 要一款「比科技蓝更梦幻」的配色，
/// 参照 NASA 韦伯望远镜「宇宙悬崖」（船底座星云 NGC 3324）那种**蓝紫相间、点缀明亮星星**的观感，
/// 原话是「**我说的可能是皮肤更准确**」—— 即**不是换一组色值，而是表面要有质感**。
///
/// **设计约束（三条，缺一不可）**
/// 1. **不许干扰阅读**：主工作区（代码 / 数据表 / 终端）是**长时间注视**的地方，
///    星点必须**极克制**；本实现在 `content` 上的星点**数量与亮度都低于 `sidebar`**，
///    且**只在背景层**，绝不进入文字所在的行高范围。
/// 2. **不许随窗口大小抖动**：星点位置用**固定种子**的伪随机，
///    与窗口尺寸**无关地**落在归一化坐标上 —— 拉伸窗口时星星**不动**（只被裁切），
///    否则每次 resize 都"重新撒一遍星"，观感廉价。
/// 3. **必须可关**：`AppearancePreference` 里有开关（默认**开**，因为用户明确要它）；
///    关闭后**逐像素回到纯色表面**（与旧版完全一致），用作故障兜底与"我就想安静用"的退路。
///
/// **性能**：星点用 `Canvas` 一次性绘制（不是 N 个 `Circle` 视图）——
/// 后者会为每颗星建一个视图节点，几百颗就开始掉帧。`Canvas` 是单个绘制层，
/// 且**只在尺寸或主题变化时重绘**（`Canvas` 的固有行为），滚动 / 输入不触发重绘。
struct NebulaBackground: View {

    /// 铺在哪一层表面上（决定云气与星点的强度 —— `content` 最克制）。
    enum Layer {
        case sidebar
        case content
        case panel

        /// 星点数量（`content` 刻意最少：它是阅读区）。
        var starCount: Int {
            switch self {
            case .sidebar: return 88
            case .content: return 54
            case .panel:   return 40
            }
        }

        /// 云气透明度倍率。
        var cloudScale: Double {
            switch self {
            case .sidebar: return 1.0
            case .content: return 0.55   // 阅读区：云气只留一点点，保住"纵深"即可
            case .panel:   return 0.7
            }
        }
    }

    let layer: Layer

    @Environment(\.colorScheme) private var scheme
    /// 主题 / 皮肤开关都从 `DesignThemeManager` 现取（与令牌取色同一个理由：缓存会读到旧值）。
    @ObservedObject private var themeManager = DesignThemeManager.shared

    var body: some View {
        // **只在星空紫主题下生效** —— 别的主题逐像素回到旧观感（不能偷偷给所有主题加星星）。
        if themeManager.theme == .stardust, themeManager.isNebulaSkinEnabled {
            Canvas { context, size in
                draw(into: &context, size: size)
            }
            .allowsHitTesting(false)   // 纯装饰：绝不吃掉点击
            .accessibilityHidden(true) // 纯装饰：读屏忽略
        } else {
            Color.clear
        }
    }

    // MARK: - 绘制

    private func draw(into context: inout GraphicsContext, size: CGSize) {
        let dark = scheme == .dark
        drawClouds(into: &context, size: size, dark: dark)
        drawStars(into: &context, size: size, dark: dark)
        if dark { drawBrightStars(into: &context, size: size) }
    }

    /// 星云云气：几团大半径、极低透明度的径向渐变叠加 —— 要的是"云气"，不是"色块"。
    ///
    /// 位置用**归一化坐标**（0~1），与窗口尺寸解耦（约束 2）。
    private func drawClouds(into context: inout GraphicsContext, size: CGSize, dark: Bool) {
        // (中心 x, 中心 y, 半径占长边比例, 色值, 基础透明度)
        // 色相取自 NASA 原图实测：靛蓝 `#1E3A6E` 为主，边缘透出紫 `#3A2F6B` / `#4A3D7A`。
        let clouds: [(Double, Double, Double, UInt32, Double)] = dark ? [
            (0.12, 0.88, 0.62, 0x1E3A6E, 0.50),
            (0.48, 0.72, 0.55, 0x2A4A82, 0.34),
            (0.88, 0.92, 0.52, 0x3A2F6B, 0.30),
            (0.30, 0.30, 0.48, 0x16264A, 0.44),
            (0.78, 0.26, 0.42, 0x4A3D7A, 0.22),
        ] : [
            (0.12, 0.88, 0.62, 0xD8E0F5, 0.55),
            (0.48, 0.72, 0.55, 0xC8D4F0, 0.38),
            (0.88, 0.92, 0.52, 0xE0D8F0, 0.32),
            (0.30, 0.30, 0.48, 0xE8EDF8, 0.42),
        ]

        let scale = layer.cloudScale
        for (cx, cy, r, hex, alpha) in clouds {
            let center = CGPoint(x: size.width * cx, y: size.height * cy)
            let radius = max(size.width, size.height) * r
            let a = alpha * scale
            let color = Color(nsColor: Theme.nsColor(hex: hex))
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                       width: radius * 2, height: radius * 2)),
                with: .radialGradient(
                    Gradient(colors: [color.opacity(a), color.opacity(0)]),
                    center: center, startRadius: 0, endRadius: radius
                )
            )
        }
    }

    /// 星点：固定种子的伪随机 —— **与窗口尺寸无关**（约束 2），resize 时星星不动。
    private func drawStars(into context: inout GraphicsContext, size: CGSize, dark: Bool) {
        var seed: UInt64 = 0x5EED_1234 &+ UInt64(layer.starCount &* 7919)
        func rnd() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double((seed >> 33) & 0xFFFFFF) / Double(0xFFFFFF)
        }

        // 星点铺在**归一化坐标**上，再乘当前尺寸 —— 这样 resize 时相对位置不变。
        for _ in 0..<layer.starCount {
            let x = size.width * rnd()
            let y = size.height * rnd()
            let r = rnd()
            // 绝大多数是小暗星，少数亮星（克制的关键：>0.94 才给 1.6pt）
            let (radius, alpha): (Double, Double) = r > 0.94 ? (1.6, dark ? 0.90 : 0.45)
                                                 : r > 0.80 ? (1.05, dark ? 0.68 : 0.34)
                                                 : (0.65, dark ? 0.38 : 0.20)
            // 星光带紫（NASA 原图实测高光 `#E4D7F8`）
            let tint: UInt32 = r > 0.88 ? 0xE4D7F8 : (r > 0.5 ? 0xD8E0FA : 0xC0CCE8)
            context.fill(
                Path(ellipseIn: CGRect(x: x - radius, y: y - radius,
                                       width: radius * 2, height: radius * 2)),
                with: .color(Color(nsColor: Theme.nsColor(hex: tint)).opacity(alpha))
            )
        }
    }

    /// 少数亮星加十字星芒 —— NASA 图的标志性特征。只在深色下加（浅色下会显得脏）。
    private func drawBrightStars(into context: inout GraphicsContext, size: CGSize) {
        var seed: UInt64 = 0xC0FF_EE01
        func rnd() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double((seed >> 33) & 0xFFFFFF) / Double(0xFFFFFF)
        }
        // 数量 = 每 400pt 见方一颗，上限 3 颗 —— 多了就不是"点缀"了。
        let count = min(3, max(1, Int(size.width * size.height / 400 / 400)))
        for _ in 0..<count {
            let cx = size.width * rnd()
            let cy = size.height * rnd()
            let len: Double = 13
            var path = Path()
            path.move(to: CGPoint(x: cx - len, y: cy)); path.addLine(to: CGPoint(x: cx + len, y: cy))
            path.move(to: CGPoint(x: cx, y: cy - len)); path.addLine(to: CGPoint(x: cx, y: cy + len))
            context.stroke(path, with: .color(Color(nsColor: Theme.nsColor(hex: 0xE4D7F8)).opacity(0.42)), lineWidth: 0.7)
            // 中心一颗小亮点
            context.fill(
                Path(ellipseIn: CGRect(x: cx - 1.4, y: cy - 1.4, width: 2.8, height: 2.8)),
                with: .color(Color(nsColor: Theme.nsColor(hex: 0xE4D7F8)).opacity(0.75))
            )
        }
    }
}

// MARK: - 便捷包装

/// 给任意表面铺「该表面色 + 星云背景」。
///
/// 视图里写 `NebulaSurface(.sidebar) { ... }` 即可 ——
/// 它**先铺表面令牌色，再叠星云**，所以关掉皮肤时就是纯表面色（约束 3）。
struct NebulaSurface<Content: View>: View {

    let surface: Surface
    let layer: NebulaBackground.Layer
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Theme.surface(surface)
            NebulaBackground(layer: layer)
            content()
        }
    }
}
