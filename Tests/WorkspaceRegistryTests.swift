import XCTest
@testable import DoyahCore

/// `FR-STD-WS-FS-010`（多工作区切换，同一时刻只有一个活动）的判据。
///
/// 这条需求的实现面只有一张表，但表上的错法都**静默**：多出一条同名行、活动状态丢了、
/// 活动那条被容量淘汰、把一个已经不可用的目录切成活动 —— 界面上都还在正常显示，
/// 用户要到「树是空的 / 一重启工作区就没了」才发现。所以这里逐条判。
final class WorkspaceRegistryTests: XCTestCase {

    private func bookmark(
        _ path: String,
        id: UUID = UUID(),
        name: String? = nil,
        createdAt: Date = Date()
    ) -> DirectoryBookmark {
        DirectoryBookmark(
            id: id,
            displayName: name ?? (path as NSString).lastPathComponent,
            bookmarkData: Data([0x01]),
            createdAt: createdAt,
            lastKnownPath: path
        )
    }

    private func entry(
        _ path: String,
        id: UUID = UUID(),
        availability: WorkspaceAvailability = .available
    ) -> WorkspaceRegistry.Entry {
        WorkspaceRegistry.Entry(
            id: id,
            displayName: (path as NSString).lastPathComponent,
            path: path,
            availability: availability
        )
    }

    private let allAvailable: (DirectoryBookmark) -> WorkspaceAvailability = { _ in .available }

    // MARK: ① 可用性映射

    func testAvailabilityFoldsEveryStatusAndOnlyGrantedIsUsable() {
        XCTAssertEqual(WorkspaceAvailability(.granted(path: "/a", isStale: false)), .available)
        XCTAssertEqual(WorkspaceAvailability(.granted(path: "/a", isStale: true)), .available)
        XCTAssertEqual(WorkspaceAvailability(.notAuthorized), .notAuthorized)
        XCTAssertEqual(WorkspaceAvailability(.missing(path: "/a")), .missing)
        XCTAssertEqual(WorkspaceAvailability(.denied(path: "/a")), .denied)
        XCTAssertEqual(WorkspaceAvailability(.resolutionFailed(reason: "坏了")), .unresolved)

        // 只有「能用」那档算能用；书签过期（isStale）**仍是可用** —— 过期不是失效。
        for value in WorkspaceAvailability.allCases {
            XCTAssertEqual(value.isUsable, value == .available, "\(value) 的 isUsable 判错了")
        }
    }

    // MARK: ② 只有一个活动

    func testReconciledKeepsExactlyOneActiveAndPutsItFirst() {
        let first = bookmark("/tmp/a")
        let second = bookmark("/tmp/b")
        let third = bookmark("/tmp/c")
        let registry = WorkspaceRegistry.reconciled(
            bookmarks: [first, second, third],
            activeID: third.id,
            availability: allAvailable
        )

        XCTAssertEqual(registry.entries.count, 3)
        XCTAssertEqual(registry.activeID, third.id)
        XCTAssertEqual(registry.entries.first?.id, third.id, "活动那条应在最前")
        XCTAssertEqual(registry.candidates.filter(\.isActive).count, 1, "活动工作区只能有一条")
        XCTAssertEqual(registry.active?.path, "/tmp/c")
    }

    func testActivateMovesTheChosenOneToFrontAndClearsTheOldFlag() {
        var registry = WorkspaceRegistry(
            entries: [entry("/tmp/a"), entry("/tmp/b"), entry("/tmp/c")],
            activeID: nil
        )
        let target = registry.entries[2].id
        XCTAssertEqual(registry.activate(target), .switchTo(target))
        XCTAssertEqual(registry.activeID, target)
        XCTAssertEqual(registry.entries.first?.id, target)
        XCTAssertEqual(registry.candidates.filter(\.isActive).map(\.id), [target])
    }

    // MARK: ③ 拒绝面

    func testAlreadyActiveIsANoOp() {
        let only = entry("/tmp/a")
        var registry = WorkspaceRegistry(entries: [only], activeID: only.id)
        let before = registry

        XCTAssertEqual(registry.decision(for: only.id), .alreadyActive)
        XCTAssertEqual(registry.activate(only.id), .alreadyActive)
        // 「点了当前这一条」一个字都不许改：重取一次授权会把树整棵塌掉（展开状态清零）。
        XCTAssertEqual(registry, before)
    }

    func testUnavailableWorkspaceCannotBecomeActive() {
        let usable = entry("/tmp/a")
        let gone = entry("/tmp/gone", availability: .missing)
        var registry = WorkspaceRegistry(entries: [usable, gone], activeID: usable.id)

        XCTAssertEqual(registry.decision(for: gone.id), .refuse(.unavailable(.missing)))
        XCTAssertEqual(registry.activate(gone.id), .refuse(.unavailable(.missing)))
        XCTAssertEqual(registry.activeID, usable.id, "切不过去时原活动不许被改掉")
    }

    func testUnknownIDIsRefused() {
        let registry = WorkspaceRegistry(entries: [entry("/tmp/a")], activeID: nil)
        XCTAssertEqual(registry.decision(for: UUID()), .refuse(.unknownWorkspace))
    }

    // MARK: ④ 同一目录只登记一条

    func testDuplicatePathCollapsesToOneAndKeepsTheActiveOne() {
        // 用户在同一个文件夹上「重新选一次」：磁盘上会多一条新 id、路径相同的书签。
        let old = bookmark("/tmp/proj", createdAt: Date(timeIntervalSince1970: 100))
        let new = bookmark("/tmp/proj", createdAt: Date(timeIntervalSince1970: 200))
        let registry = WorkspaceRegistry.reconciled(
            bookmarks: [old, new],
            activeID: old.id,
            availability: allAvailable
        )

        XCTAssertEqual(registry.entries.count, 1, "同一目录不该长出两条")
        XCTAssertEqual(registry.activeID, old.id, "活动那条优先留下（否则一重启工作区就没了）")
    }

    func testDuplicatePathKeepsTheNewerOneWhenNeitherIsActive() {
        let old = bookmark("/tmp/proj", name: "旧名", createdAt: Date(timeIntervalSince1970: 100))
        let new = bookmark("/tmp/proj", name: "新名", createdAt: Date(timeIntervalSince1970: 200))
        let registry = WorkspaceRegistry.reconciled(
            bookmarks: [old, new],
            activeID: nil,
            availability: allAvailable
        )

        XCTAssertEqual(registry.entries.count, 1)
        XCTAssertEqual(registry.entries.first?.id, new.id)
        XCTAssertEqual(registry.entries.first?.displayName, "新名")
        XCTAssertNil(registry.activeID, "没有活动就是没有活动，不许自己挑一条")
    }

    func testReconciledIsDeterministic() {
        let bookmarks = [bookmark("/tmp/a"), bookmark("/tmp/b")]
        let one = WorkspaceRegistry.reconciled(bookmarks: bookmarks, activeID: bookmarks[1].id, availability: allAvailable)
        let two = WorkspaceRegistry.reconciled(bookmarks: bookmarks, activeID: bookmarks[1].id, availability: allAvailable)
        XCTAssertEqual(one, two)
        XCTAssertEqual(one.candidates.map(\.id), two.candidates.map(\.id), "顺序也必须一样")
    }

    func testReconciledDropsActiveWhenThatBookmarkIsGone() {
        let kept = bookmark("/tmp/a")
        let registry = WorkspaceRegistry.reconciled(
            bookmarks: [kept],
            activeID: UUID(),
            availability: allAvailable
        )
        XCTAssertNil(registry.activeID)
        XCTAssertEqual(registry.candidates.filter(\.isActive).count, 0)
        XCTAssertEqual(registry.entries.count, 1)
    }

    // MARK: ⑤ 容量

    func testCapacityTrimsOnConstructionButKeepsTheActiveOne() {
        // 磁盘上攒了 10 条（老版本没上限）：重建时裁到上限，但**活动那条即使排在最尾也不淘汰**。
        let entries = (0..<10).map { entry("/tmp/p\($0)") }
        let registry = WorkspaceRegistry(entries: entries, activeID: entries[9].id)

        XCTAssertEqual(registry.entries.count, WorkspaceRegistry.capacity)
        XCTAssertEqual(registry.activeID, entries[9].id)
        XCTAssertNotNil(registry.entry(id: entries[9].id), "活动那条即使是最旧的也不许淘汰")
        XCTAssertNil(registry.entry(id: entries[8].id), "被挤掉的是表尾那一条非活动的")
        XCTAssertEqual(registry.candidates.filter(\.isActive).count, 1)
    }

    func testAddEvictsTheTailWhenFull() {
        var registry = WorkspaceRegistry(
            entries: (0..<WorkspaceRegistry.capacity).map { entry("/tmp/q\($0)") },
            activeID: nil
        )
        let tail = registry.entries.last!.id
        let newcomer = entry("/tmp/new")
        registry.add(newcomer)

        XCTAssertEqual(registry.entries.count, WorkspaceRegistry.capacity)
        XCTAssertEqual(registry.entries.first?.id, newcomer.id)
        XCTAssertEqual(registry.activeID, newcomer.id)
        XCTAssertNil(registry.entry(id: tail), "没活动时就是纯 FIFO：淘汰表尾")
        XCTAssertEqual(registry.candidates.filter(\.isActive).count, 1)
    }

    func testCapacityCannotGoBelowTheActiveOne() {
        // 极端：容量 1 且只有那一条 —— 淘汰循环必须停住（不许死循环，也不许把活动删掉）。
        var single = WorkspaceRegistry(entries: [entry("/tmp/only")], activeID: nil)
        let only = single.entries[0].id
        single.add(entry("/tmp/only", id: only))
        XCTAssertEqual(single.activeID, only)
        XCTAssertEqual(single.entries.count, 1)
        single.add(entry("/tmp/only", id: only))
        XCTAssertEqual(single.entries.count, 1)
    }

    // MARK: ⑥ 登记

    func testAddingExistingPathReusesTheIDAndRefreshesTheRow() {
        let existing = entry("/tmp/proj", availability: .missing)
        var registry = WorkspaceRegistry(entries: [existing], activeID: nil)

        let picked = entry("/tmp/proj", availability: .available)
        let resolved = registry.add(picked)

        XCTAssertEqual(resolved, existing.id, "同一目录复用旧 id（否则磁盘上留下两条同路径书签）")
        XCTAssertEqual(registry.entries.count, 1)
        XCTAssertEqual(registry.activeID, existing.id)
        XCTAssertEqual(registry.entries.first?.availability, .available, "重选一次应把不可用那档刷新掉")
    }

    func testAddingNewWorkspaceGoesFirstAndBecomesActive() {
        var registry = WorkspaceRegistry(entries: [entry("/tmp/a"), entry("/tmp/b")], activeID: nil)
        let fresh = entry("/tmp/c")
        registry.add(fresh)

        XCTAssertEqual(registry.entries.map(\.path), ["/tmp/c", "/tmp/a", "/tmp/b"])
        XCTAssertEqual(registry.activeID, fresh.id)
        XCTAssertEqual(registry.candidates.filter(\.isActive).count, 1)
    }

    func testAddingPathlessBookmarkDoesNotCollideWithOthers() {
        // 从没解析出路径的书签（`lastKnownPath == nil`）：不许因为「路径都是空」把它们去重成一条。
        var registry = WorkspaceRegistry()
        registry.add(WorkspaceRegistry.Entry(id: UUID(), displayName: "甲", path: nil, availability: .available))
        registry.add(WorkspaceRegistry.Entry(id: UUID(), displayName: "乙", path: nil, availability: .available))
        XCTAssertEqual(registry.entries.count, 2)
        XCTAssertEqual(registry.entries.map(\.displayName), ["乙", "甲"])
    }
}

