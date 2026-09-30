import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// **【临时探针 · 用完即删】** 量「5,000 行 SQL 上每个按键的延迟」。
///
/// 为什么要有它：`verify-all` 判不到运行时时序，而 `sample` 抓到的窗口里应用 92% 时间是空闲的
/// （采不到用户打字那几秒）。这个探针把「真视图 + 真编辑路径 + 人手速」放进离屏宿主里，
/// 直接给出**每键同步耗时**与**键间间隔**（后者超出模拟手速的部分 = 主线程被占住的时间）。
///
/// 跑法：`DOYAH_UI_SNAPSHOT=1 swift test --filter PerfTypingProbeTests`
final class PerfTypingProbeTests: XCTestCase {

    private struct Harness: View {
        /// 权威副本（模拟 `AppState.tabs[i].sql`）。
        let authoritative: String
        let tabID = UUID()
        /// 编辑器缓冲（队列 `L-148`）—— 与产品接线同形：每键只写它。
        @StateObject private var buffer = QueryEditorBuffer()
        var body: some View {
            SQLEditorView(
                text: buffer.displayText(for: tabID, authoritative: authoritative),
                databaseType: .postgresql,
                diagnostics: [],
                tabID: tabID,
                onTextChange: { buffer.noteEdit($0, for: tabID) }
            )
        }
    }

    /// 与交给需求提出者的那份素材同形（宽 INSERT + 每 50 行一条注释）。
    private static func bigDocument(lines: Int) -> String {
        var s = ""
        s.reserveCapacity(lines * 150)
        for i in 1...lines {
            if i % 50 == 0 {
                s += "-- 第 \(i) 行是注释：这条也该着色成注释色\n"
            } else {
                s += "INSERT INTO orders (id, customer_id, status, amount, created_at, note) "
                    + "VALUES (\(i), \(1000 + i), 'paid', \(i).25, '2026-01-01 00:00:00', 'order-\(i)-east');\n"
            }
        }
        return s
    }

    private func stat(_ name: String, _ xs: [Double]) {
        let s = xs.sorted()
        print(String(format: "PERF %@: min=%.1f p50=%.1f p90=%.1f max=%.1f (n=%d)",
                     name, s.first ?? 0, s[s.count / 2], s[Int(Double(s.count) * 0.9)], s.last ?? 0, s.count))
    }

    @MainActor
    private func timeIt(_ label: String, rounds: Int = 5, _ body: () -> Void) {
        var best = Double.greatestFiniteMagnitude
        for _ in 0..<rounds {
            let t = CFAbsoluteTimeGetCurrent()
            body()
            best = min(best, CFAbsoluteTimeGetCurrent() - t)
        }
        print(String(format: "PERF %-46@ %8.2f ms", label as NSString, best * 1000))
    }

    /// 拆开那 33 ms：是「取出 string」的代价，还是「在 foreign 存储上逐行扫」的代价？
    @MainActor
    func testBreakdownOfPerKeyCost() throws {
        guard ProcessInfo.processInfo.environment["DOYAH_UI_SNAPSHOT"] == "1" else {
            throw XCTSkip("要 DOYAH_UI_SNAPSHOT=1")
        }
        let text = Self.bigDocument(lines: 5000)
        let host = UISnapshot.LiveHost(Harness(authoritative: text), size: CGSize(width: 900, height: 600))
        host.pump(1.0)
        let tv = try XCTUnwrap(
            UISnapshot.LiveHost<Harness>.findViews(ofType: SQLTextView.self, in: host.hosting).first
        )

        timeIt("① textView.string（foreign 桥接）") { _ = tv.string }
        timeIt("② CodeLines.lineStarts(tv.string)  [foreign]") { _ = CodeLines.lineStarts(in: tv.string) }
        timeIt("③ textStorage.length（O(1) 对照）") { _ = tv.textStorage?.length }

        // 同一份文本的 native 副本（一次性拷出去，之后走 Swift 原生存储）
        let native = String(decoding: Array(tv.string.utf16), as: UTF16.self)
        timeIt("④ Array(tv.string.utf16) 一次拷贝") { _ = Array(tv.string.utf16) }
        timeIt("⑤ CodeLines.lineStarts(native)     [native]") { _ = CodeLines.lineStarts(in: native) }
        print("PERF 两者行数应相同: foreign=\(CodeLines.lineStarts(in: tv.string).count) native=\(CodeLines.lineStarts(in: native).count)")

        // 真编辑路径里各段
        let at = NSRange(location: tv.textStorage?.length ?? 0, length: 0)
        timeIt("⑥ 只 replaceCharacters（不含通知）", rounds: 5) {
            let r = NSRange(location: tv.textStorage?.length ?? 0, length: 0)
            tv.textStorage?.replaceCharacters(in: r, with: "z")
            tv.textStorage?.replaceCharacters(in: NSRange(location: (tv.textStorage?.length ?? 1) - 1, length: 1), with: "")
        }
        _ = at
        timeIt("⑦ 整条 didChangeText（含协调器 textDidChange）", rounds: 5) {
            let r = NSRange(location: tv.textStorage?.length ?? 0, length: 0)
            if tv.shouldChangeText(in: r, replacementString: "q") {
                tv.textStorage?.replaceCharacters(in: r, with: "q")
                tv.didChangeText()
            }
        }

        // ⑧ updateNSView 里的字体判断：不相等就会重设字体 ⇒ 5,000 行全量重排？
        print("PERF font: tv.font=\(tv.font?.fontName ?? "nil")/\(tv.font?.pointSize ?? -1)"
              + "  baseFont=\(SQLEditorView.baseFont.fontName)/\(SQLEditorView.baseFont.pointSize)")
        print("PERF font 判断会走「要换字体」分支吗: "
              + "\(tv.font?.fontName != SQLEditorView.baseFont.fontName || tv.font?.pointSize != SQLEditorView.baseFont.pointSize)")
        timeIt("⑧ textView.font = baseFont（全量重排的代价）", rounds: 3) {
            tv.font = SQLEditorView.baseFont
        }
        timeIt("⑨ 设完字体后再走一次真编辑（看是否替它付账）", rounds: 3) {
            let r = NSRange(location: tv.textStorage?.length ?? 0, length: 0)
            if tv.shouldChangeText(in: r, replacementString: "w") {
                tv.textStorage?.replaceCharacters(in: r, with: "w")
                tv.didChangeText()
            }
        }
    }

    /// 判决实验：全量排版的代价，以及 `allowsNonContiguousLayout` 开/关对每键耗时的影响。
    @MainActor
    func testLayoutCostAndNonContiguousAB() throws {
        guard ProcessInfo.processInfo.environment["DOYAH_UI_SNAPSHOT"] == "1" else {
            throw XCTSkip("要 DOYAH_UI_SNAPSHOT=1")
        }
        let text = Self.bigDocument(lines: 5000)
        let host = UISnapshot.LiveHost(Harness(authoritative: text), size: CGSize(width: 900, height: 600))
        host.pump(1.0)
        let tv = try XCTUnwrap(
            UISnapshot.LiveHost<Harness>.findViews(ofType: SQLTextView.self, in: host.hosting).first
        )

        print("PERF allowsNonContiguousLayout = \(String(describing: tv.layoutManager?.allowsNonContiguousLayout))")
        timeIt("⑩ ensureLayout(for: textContainer) 全量排版", rounds: 3) {
            tv.layoutManager?.ensureLayout(for: tv.textContainer!)
        }

        func burst(_ label: String, keys: Int = 15) {
            var xs: [Double] = []
            for k in 0..<keys {
                let ch = String(UnicodeScalar(UInt8(97 + k % 26)))
                let at = NSRange(location: tv.textStorage?.length ?? 0, length: 0)
                let t = CFAbsoluteTimeGetCurrent()
                if tv.shouldChangeText(in: at, replacementString: ch) {
                    tv.textStorage?.replaceCharacters(in: at, with: ch)
                    tv.didChangeText()
                }
                xs.append((CFAbsoluteTimeGetCurrent() - t) * 1000)
                host.pump(0.08)
            }
            let s = xs.sorted()
            print(String(format: "PERF [%@] 每键 p50=%.1f max=%.1f (n=%d)", label as NSString,
                         s[s.count / 2], s.last ?? 0, s.count))
        }

        tv.layoutManager?.allowsNonContiguousLayout = true
        host.pump(0.3)
        burst("nonContiguous = true（产品默认）")

        tv.layoutManager?.allowsNonContiguousLayout = false
        host.pump(0.3)
        burst("nonContiguous = false")
    }

    @MainActor
    func testPerKeystrokeLatency5000Lines() throws {
        guard ProcessInfo.processInfo.environment["DOYAH_UI_SNAPSHOT"] == "1" else {
            throw XCTSkip("要 DOYAH_UI_SNAPSHOT=1")
        }
        let text = Self.bigDocument(lines: 5000)
        print("PERF doc: utf16=\(text.utf16.count) bytes=\(text.utf8.count)")

        let host = UISnapshot.LiveHost(Harness(authoritative: text), size: CGSize(width: 900, height: 600))
        host.pump(1.0)
        let tv = try XCTUnwrap(
            UISnapshot.LiveHost<Harness>.findViews(ofType: SQLTextView.self, in: host.hosting).first,
            "真编辑器不在视图树里"
        )
        XCTAssertEqual(tv.textStorage?.length, text.utf16.count)

        var shouldT: [Double] = []
        var replaceT: [Double] = []
        var didT: [Double] = []
        var pumpT: [Double] = []
        var sync: [Double] = []
        let pumpPerKey = 0.08                     // 模拟人手速 ~80 ms/键

        for k in 0..<40 {
            let ch = String(UnicodeScalar(UInt8(97 + k % 26)))
            let at = NSRange(location: tv.textStorage?.length ?? 0, length: 0)
            let t0 = CFAbsoluteTimeGetCurrent()

            var t = CFAbsoluteTimeGetCurrent()
            let ok = tv.shouldChangeText(in: at, replacementString: ch)
            shouldT.append((CFAbsoluteTimeGetCurrent() - t) * 1000)

            t = CFAbsoluteTimeGetCurrent()
            if ok { tv.textStorage?.replaceCharacters(in: at, with: ch) }
            replaceT.append((CFAbsoluteTimeGetCurrent() - t) * 1000)

            t = CFAbsoluteTimeGetCurrent()
            if ok { tv.didChangeText() }             // ← 走协调器的 textDidChange（真路）
            didT.append((CFAbsoluteTimeGetCurrent() - t) * 1000)

            sync.append((CFAbsoluteTimeGetCurrent() - t0) * 1000)

            t = CFAbsoluteTimeGetCurrent()
            host.pump(pumpPerKey)
            pumpT.append((CFAbsoluteTimeGetCurrent() - t) * 1000)
        }

        // 停手之后那一次 debounce 重着色要多久
        let t1 = CFAbsoluteTimeGetCurrent()
        host.pump(1.5)
        let settle = (CFAbsoluteTimeGetCurrent() - t1) * 1000

        stat("sync-per-key(ms) 合计", sync)
        stat("  其中 shouldChangeText", shouldT)
        stat("  其中 replaceCharacters", replaceT)
        stat("  其中 didChangeText", didT)
        stat("pump 实际耗时（模拟 80ms）", pumpT)
    }
}
