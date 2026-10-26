import XCTest
@testable import DoyahCore

/// 详设 §3.22 的三条用例：`T-3.22-01`（重复声明停装载）· `T-3.22-02`（不可见 ≠ 不存在，两种提示不同）·
/// `T-3.22-03`（同一工具两壳指向同一 handler）。
final class AgentToolCatalogSnapshotTests: XCTestCase {

    private func definition(_ name: String, enabled: Bool = true) -> AgentToolDefinition {
        AgentToolDefinition(name: name,
                            summary: "test",
                            capability: .readFile,
                            parameters: ["path": "string"],
                            required: ["path"],
                            level: .readOnly,
                            approval: .none,
                            enabled: enabled)
    }

    // MARK: T-3.22-01 重复声明停装载

    func testDuplicateDeclarationStopsLoading() {
        let registry = AgentToolRegistry(definitions: [definition("read_file"), definition("read_file")])
        XCTAssertThrowsError(try AgentToolCatalog(registry: registry)) { error in
            XCTAssertEqual(error as? AgentToolCatalogError, .duplicateDeclaration("read_file"))
        }
    }

    func testStandardRegistryLoads() throws {
        let catalog = try AgentToolCatalog(registry: .standard)
        var snapshot = catalog.snapshot(for: .terminalShell)
        XCTAssertFalse(snapshot.entries.isEmpty)
        // 标准表里 `read_notes` / `fetch_url` 是第二批、`enabled: false` ⇒ 不进快照
        XCTAssertEqual(snapshot.omittedCount, 2)
        // 同一 profile 同一指纹 ⇒ 同一内容（幂等）
        XCTAssertEqual(snapshot, catalog.snapshot(for: .terminalShell))
        // 第二批未启用的工具不该出现在快照里
        XCTAssertNil(snapshot.entry(named: "fetch_url"))
        snapshot = catalog.snapshot(for: .subagent)
        XCTAssertNil(snapshot.entry(named: "read_notes"))
    }

    // MARK: T-3.22-02 不可见 ≠ 不存在

    func testNotVisibleIsDifferentFromNotRegistered() throws {
        let catalog = try AgentToolCatalog(registry: .standard,
                                           visibility: [.subagent: ["read_file", "search"]])
        // 已登记、但本 profile 不可见
        let hidden = catalog.resolve("write_file", for: .subagent)
        XCTAssertEqual(try? hidden.get(), nil)
        if case .failure(let refusal) = hidden {
            XCTAssertEqual(refusal, .toolNotVisibleInProfile("write_file", .subagent))
        } else {
            XCTFail("应当返回 toolNotVisibleInProfile")
        }
        // 压根没登记
        let missing = catalog.resolve("hack_the_planet", for: .subagent)
        if case .failure(let refusal) = missing {
            XCTAssertEqual(refusal, .toolNotRegistered("hack_the_planet"))
        } else {
            XCTFail("应当返回 toolNotRegistered")
        }
        // 两种拒绝不相等 —— 界面提示因此不同
        XCTAssertNotEqual(hidden, missing)
    }

    func testEmptyVisibilityInheritsEverything() throws {
        let catalog = try AgentToolCatalog(registry: .standard, visibility: [.graphicalShell: []])
        XCTAssertNotNil(try? catalog.resolve("write_file", for: .graphicalShell).get())
    }

    func testSchemaNotFetchedRefusal() throws {
        let catalog = try AgentToolCatalog(registry: .standard, schemaFetched: ["read_file"])
        let result = catalog.resolve("search", for: .terminalShell)
        if case .failure(let refusal) = result {
            XCTAssertEqual(refusal, .schemaNotFetched("search"))
        } else {
            XCTFail("schema 未取回必须拒")
        }
        XCTAssertNotNil(try? catalog.resolve("read_file", for: .terminalShell).get())
    }

    // MARK: T-3.22-03 两壳同一实现

    func testBothShellsPointToSameImplementation() throws {
        let catalog = try AgentToolCatalog(registry: .standard)
        XCTAssertTrue(catalog.sharesImplementation("write_file", .terminalShell, .graphicalShell))
        XCTAssertTrue(catalog.sharesImplementation("search", .terminalShell, .graphicalShell))
        // 可见性不同时，实现身份仍相同（可见 ≠ 能力）
        let restricted = try AgentToolCatalog(registry: .standard,
                                              visibility: [.subagent: ["read_file"]])
        XCTAssertFalse(restricted.sharesImplementation("write_file", .terminalShell, .subagent))
    }

    func testDisabledToolIsNotVisible() throws {
        let registry = AgentToolRegistry(definitions: [definition("read_file"), definition("fetch_url", enabled: false)])
        let catalog = try AgentToolCatalog(registry: registry)
        let snapshot = catalog.snapshot(for: .terminalShell)
        XCTAssertEqual(snapshot.visibleNames, ["read_file"])
        XCTAssertEqual(snapshot.omittedCount, 1)
        if case .failure(let refusal) = catalog.resolve("fetch_url", for: .terminalShell) {
            XCTAssertEqual(refusal, .toolNotVisibleInProfile("fetch_url", .terminalShell))
        } else {
            XCTFail("未启用工具必须按不可见处理")
        }
    }

    func testRegistryFingerprintChangesWhenDefinitionsChange() throws {
        let a = try AgentToolCatalog(registry: AgentToolRegistry(definitions: [definition("a")]))
        let b = try AgentToolCatalog(registry: AgentToolRegistry(definitions: [definition("b")]))
        XCTAssertNotEqual(a.registryFingerprint, b.registryFingerprint)
    }
}
