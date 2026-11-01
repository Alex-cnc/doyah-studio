import XCTest
@testable import DoyahCore

/// SSH 隧道的**接线判据**（源树）：判定在 Core，接线必须真的问过它（FR-CONN-18 判据 ①②④）。
///
/// 为什么要有这一层：`SSHTunnelDiagnosisTests` 全绿也只能证明「规则对」，证明不了
/// 「执行失败时那句人话真的经过了它」。这一档在别处已经踩过（机制有、接线没有），
/// 所以把四段接线钉在源树上：
///   · 建连前先起隧道、并把连接目标改写到本机转发端口（判据 ①/③ 的入口）；
///   · 执行失败的 catch 走 `tunnelAwareMessage`（判据 ② 的入口）；
///   · 归因之后**真的作废**这条连接（否则下一次复用一个断掉的连接，又报一句看不懂的话）；
///   · 断连时隧道跟着收（判据 ④ 的入口）。
///
/// 只读源码、不连库：运行时的那一半在 `SSHTunnelRuntimeTests`（真起进程）。
final class SSHTunnelWiringTests: XCTestCase {

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    /// 找不到标记 = **判红**（不是跳过）：源码一改名，判据静默空转是老病。
    private struct MissingMarker: Error, CustomStringConvertible {
        let marker: String
        var description: String { "源码里找不到标记「\(marker)」—— 这条判据要跟着源码改，不许空转" }
    }

    private func slice(_ text: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = text.range(of: start) else { throw MissingMarker(marker: start) }
        guard let endRange = text.range(of: end, range: startRange.upperBound..<text.endIndex) else {
            throw MissingMarker(marker: end)
        }
        return text[startRange.upperBound..<endRange.lowerBound]
    }

    /// 执行失败的 catch 必须经过 `tunnelAwareMessage`（而不是直接 `ErrorPresenter.message`）。
    func testQueryFailureGoesThroughTheTunnelAttribution() throws {
        let state = try source("App/AppState.swift")
        let catchBody = try slice(
            state,
            from: "let cancelled = Task.isCancelled || error is CancellationError",
            to: "updateTab(tabID) {\n                if cancelled {"
        )
        XCTAssertTrue(
            catchBody.contains("tunnelAwareMessage("),
            "执行失败没经过隧道归因 —— 判据 ② 又变成「规则在、接线没有」"
        )
        XCTAssertFalse(
            catchBody.contains("ErrorPresenter.message(for: error)\n"),
            "catch 里直接取了原始错误文案（绕过归因）"
        )
    }

    /// 归因那一段必须：先改判死隧道、再归因、再作废连接。
    func testAttributionMarksDeadTunnelsAndRebuildsTheConnection() throws {
        let state = try source("App/AppState.swift")
        let body = try slice(state, from: "private func tunnelAwareMessage(", to: "/// 按需建/复用 SSH 隧道")
        XCTAssertTrue(body.contains("markDeadIfExited("), "没先如实改判「进程没了」⇒ 状态永远停在 ready")
        XCTAssertTrue(body.contains("SSHTunnelDiagnosis.annotate("), "没经过 Core 的归因判定")
        XCTAssertTrue(body.contains("SSHTunnelDiagnosis.shouldRebuild("), "没按同一份边界决定要不要重建")
        XCTAssertTrue(body.contains("invalidateService(for: configuration.id)"), "死隧道没被收掉 ⇒ 下一次复用断连接")
    }

    /// 建连路径：先起隧道、再把目标改写成本机转发端口，然后才造服务。
    func testConnectPathBringsUpTheTunnelAndRewritesTheEndpoint() throws {
        let state = try source("App/AppState.swift")
        let tunnelCall = try slice(state, from: "let tunnelEndpoint = try await ensureTunnel(for: configuration)", to: "let newTask = Task<(any DatabaseService, ServerInfo), Error>")
        XCTAssertTrue(tunnelCall.contains("SSHTunnelEndpoint.rewrite(configuration, localPort: tunnelEndpoint?.port)"),
                      "建连时没把目标改写成本机转发端口（隧道等于白起）")
        let serviceCreation = try slice(state, from: "let service = DatabaseServiceFactory.make(", to: "do {\n                    let serverInfo = try await service.connect()")
        XCTAssertTrue(serviceCreation.contains("for: derived"), "服务是拿原配置连的（会直连到不可达的地址）")
    }

    /// 断连时隧道跟着收（判据 ④：不留残留进程 / 端口）。
    func testDisconnectStopsTheTunnel() throws {
        let state = try source("App/AppState.swift")
        let body = try slice(state, from: "private func invalidateService(for connectionID: UUID) {", to: "for key in Array(connectTasks.keys)")
        XCTAssertTrue(body.contains("sshTunnels.removeValue(forKey: connectionID)"), "断连没收隧道")
        XCTAssertTrue(body.contains("tunnel.stop()"), "隧道进程没被停（判据 ④）")
    }
}
