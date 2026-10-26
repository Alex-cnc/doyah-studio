import XCTest
@testable import DoyahCore

/// `FR-AGT-GUARD-PERM-002`（配置面）与 `-003`（运行时边界）判据：
/// 改配置立即生效、非法配置拒绝并说明、越界路径被拒。
final class AgentPermissionBoundaryTests: XCTestCase {

    private func config(level: AgentPermissionLevel = .scoped,
                        roots: [AgentSandboxRoot] = [AgentSandboxRoot(path: "/work/proj", allowsWrite: true)],
                        commands: [String] = ["git", "swift"]) throws -> AgentPermissionConfig {
        try AgentPermissionConfig.validated(level: level, roots: roots, commands: commands)
    }

    // MARK: 配置面

    func testValidConfigRoundTrips() throws {
        let c = try config()
        XCTAssertEqual(c.level, .scoped)
        XCTAssertEqual(c.roots.count, 1)
        XCTAssertTrue(c.allowsWrite(to: "/work/proj/Core/A.swift"))
    }

    func testIllegalConfigIsRejectedWithReason() {
        XCTAssertThrowsError(try config(roots: [])) { error in
            XCTAssertEqual(error as? AgentPermissionConfigError, .noRoots)
        }
        XCTAssertThrowsError(try config(roots: [AgentSandboxRoot(path: "relative/dir", allowsWrite: true)])) { error in
            XCTAssertEqual(error as? AgentPermissionConfigError, .mustBeAbsolute("relative/dir"))
        }
        XCTAssertThrowsError(try config(roots: [AgentSandboxRoot(path: "/a", allowsWrite: true),
                                                AgentSandboxRoot(path: "/a/", allowsWrite: false)])) { error in
            XCTAssertEqual(error as? AgentPermissionConfigError, .duplicateRoot("/a/"))
        }
        XCTAssertThrowsError(try config(commands: ["git", "  "])) { error in
            XCTAssertEqual(error as? AgentPermissionConfigError, .emptyCommand)
        }
    }

    func testStoreAppliesImmediately() throws {
        var store = AgentPermissionConfigStore()
        XCTAssertEqual(store.current.level, .readOnly)
        let applied = store.apply(level: .scoped,
                                  roots: [AgentSandboxRoot(path: "/work", allowsWrite: true)],
                                  commands: ["git"])
        XCTAssertEqual(try? applied.get().level, .scoped)
        XCTAssertEqual(store.current.level, .scoped, "改配置必须立即生效")
        XCTAssertTrue(store.current.allowsWrite(to: "/work/x"))
    }

    func testStoreKeepsOldConfigOnIllegalInput() throws {
        var store = AgentPermissionConfigStore()
        _ = store.apply(level: .scoped, roots: [AgentSandboxRoot(path: "/work", allowsWrite: true)], commands: [])
        let before = store.current
        let failed = store.apply(level: .fullAccess, roots: [], commands: [])
        XCTAssertEqual(failed, .failure(.noRoots))
        XCTAssertEqual(store.current, before, "非法配置不许把当前值改坏")
        XCTAssertEqual(store.lastError, .noRoots)
    }

    // MARK: 运行时边界

    func testInsideRootAllowed() throws {
        let boundary = AgentSandboxBoundary(config: try config(), rootExists: { _ in true })
        XCTAssertEqual(boundary.check(path: "/work/proj/Core/A.swift", access: .read), .success("/work/proj/Core/A.swift"))
        XCTAssertEqual(boundary.check(path: "/work/proj/Core/A.swift", access: .write), .success("/work/proj/Core/A.swift"))
    }

    func testEscapeByDotDotIsRejected() throws {
        let boundary = AgentSandboxBoundary(config: try config(), rootExists: { _ in true })
        let result = boundary.check(path: "/work/proj/../../etc/passwd", access: .read)
        XCTAssertEqual(result, .failure(.outsideRoots("/etc/passwd")))
    }

    func testSiblingPrefixIsNotInside() throws {
        let boundary = AgentSandboxBoundary(config: try config(), rootExists: { _ in true })
        XCTAssertEqual(boundary.check(path: "/work/proj-evil/x", access: .read),
                       .failure(.outsideRoots("/work/proj-evil/x")))
    }

    func testReadOnlyRootDeniesWriteButAllowsRead() throws {
        let c = try config(roots: [AgentSandboxRoot(path: "/data", allowsWrite: false)])
        let boundary = AgentSandboxBoundary(config: c, rootExists: { _ in true })
        XCTAssertEqual(boundary.check(path: "/data/x", access: .read), .success("/data/x"))
        XCTAssertEqual(boundary.check(path: "/data/x", access: .write), .failure(.writeDeniedReadOnly(path: "/data/x")))
    }

    func testReadOnlyLevelDeniesAllWrites() throws {
        let c = try config(level: .readOnly)
        let boundary = AgentSandboxBoundary(config: c, rootExists: { _ in true })
        XCTAssertEqual(boundary.check(path: "/work/proj/x", access: .write), .failure(.writeDeniedReadOnlyLevel(path: "/work/proj/x")))
        XCTAssertTrue(boundary.isAllowed(path: "/work/proj/x", access: .read))
    }

    func testRelativePathRejected() throws {
        let boundary = AgentSandboxBoundary(config: try config(), rootExists: { _ in true })
        XCTAssertEqual(boundary.check(path: "Core/A.swift", access: .read), .failure(.invalidPath("Core/A.swift")))
        XCTAssertEqual(boundary.check(path: "  ", access: .read), .failure(.invalidPath("  ")))
    }
}
