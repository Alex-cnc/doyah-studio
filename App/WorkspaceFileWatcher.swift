import Foundation

/// **工作区文件监听**（实时感知磁盘改动 ⇒ 编辑器跟着重载）。
///
/// ## 为什么必须有它
///
/// 助手（或外部编辑器 / `git` / 构建脚本）改的是**磁盘**，而编辑器手里是**内存里的正文** ——
/// 没有监听，屏幕上永远是旧内容，人会误判成"没生效"。
/// 人类主人 2026-10-16 点名：「**工作区是实时加载或感知文件的修改重载的**」。
///
/// ## 做法
///
/// `FSEventStream`（`kFSEventStreamCreateFlagFileEvents`）挂在**工作区根**上：递归、按**路径**报事件。
/// 事件先**防抖**（默认 0.18s —— 一次保存 / 一次构建往往连着落十几条），合成一批再回调一次。
/// 回调只报「哪些路径变了」；**重载策略交回 `AppState`** —— 只有它知道哪个页签开着这个文件、
/// 有没有未保存的改动（**有改动就不许悄悄覆盖**，那是丢人数据）。
///
/// ## 边界（如实登记）
///
/// ① 只报**工作区根之内**的路径（根之外的正文件由 `watch(file:)` 单点监听，给"系统面板打开的任意文件"用）；
/// ② FSEvents 是**合并**事件：短时间内多次改动只报一次（这正是我们要的"一批一次"）；
/// ③ 自己的保存也会触发回调 —— 由 `AppState` 侧按"内容是否真的变了"过滤（不然会自己覆盖自己的脏标记）。
/// 给 FSEvents 回调用的**常驻盒子**：盒子由 FSEvents 持有，里面只放弱引用。
///
/// 参见 `streamContextPointer` 的注释 —— 直接把监听器塞进上下文会在 `stop()` 之后挨一次
/// "迟到的回调" 而崩；盒子把"谁还活着"这件事从裸指针里摘出来。
private final class WorkspaceWatcherBox {
    weak var watcher: WorkspaceFileWatcher?
}

/// 盒子仓库：**只增不减**。
///
/// 为什么允许这点"泄漏"：FSEvents 的回调是 C 函数指针，拿不到 Swift 的捕获列表，
/// 唯一能用的就是 `FSEventStreamContext.info` 这个裸指针。前后两版都栽在"谁来保证它指向的
/// 对象还活着"：
/// ① `passUnretained(self)` —— 监听器先走，回调打空（21:22 崩溃）；
/// ② `passRetained(self)` + `stop()` 释放 —— 已派发的回调落在释放之后（21:50 崩溃）；
/// ③ 盒子 + retain/release 回调 —— 仍在 22:31 连崩 5 次（说明"成对配平"这个假设在
///    `FSEventStreamInvalidate` 之后并不成立）。
///
/// 结论：裸指针的生命期**不能靠算引用计数来保证**，只能靠"永不释放"。
/// 盒子本身只有 16 字节，每次换工作区根多一个，进程内最多几十个 ——
/// 用这点内存换"绝不野指针"，是这笔交易里唯一划算的一边。
private enum WorkspaceWatcherBoxes {
    private static let lock = NSLock()
    private static var boxes: [WorkspaceWatcherBox] = []

    static func keep(_ box: WorkspaceWatcherBox) {
        lock.lock(); boxes.append(box); lock.unlock()
    }
}

final class WorkspaceFileWatcher {

    /// 一批改动（防抖后）。
    private var onChanges: (([String]) -> Void)?

    private var stream: FSEventStreamRef?
    /// FSEvents 上下文里那个「盒子」的指针 —— `stop()` 里成对 release。
    ///
    /// **为什么不是直接把 `self` 塞进去**：第一版用 `passRetained(self)` 看着对了，实机仍在
    /// `stop()` 之后崩过一次 —— `FSEventStreamStop`/`Invalidate` **不会取消已经派发到队列上的回调**，
    /// 那一次回调落在 `release` 之后 ⇒ 对已释放对象 `objc_msgSend`（EXC_BAD_ACCESS，
    /// 线程 `studio.doyah.workspace-watcher`，2026-10-18 21:50）。
    /// 改成盒子后：回调读的是**盒子**（FSEvents 自己持着，`retain`/`release` 回调成对），
    /// 盒子里对监听器是 **weak** ⇒ 监听器先走也只会拿到 `nil`，不会碰野指针。
    private var streamContextPointer: UnsafeMutableRawPointer?
    /// 单文件监听（工作区根之外）。
    private var fileSources: [String: DispatchSourceFileSystemObject] = [:]

    private let queue = DispatchQueue(label: "studio.doyah.workspace-watcher")
    private var pending: Set<String> = []
    private var flushScheduled = false

    /// 防抖窗口（秒）。0.18 是"保存一次就够用、又不会让人等"的取值。
    private let debounce: TimeInterval

    init(debounce: TimeInterval = 0.18) {
        self.debounce = debounce
    }

    deinit {
        stop()
    }

    // MARK: - 生命周期

    /// 开始监听一个工作区根（已开着就换根）。
    func start(root: String, onChanges: @escaping ([String]) -> Void) {
        stop()
        self.onChanges = onChanges

        // 盒子：`passRetained` 交给 FSEvents（下面 retain/release 回调成对配平），
        // 盒子里对监听器是 weak ⇒ 迟到的回调也不会碰野指针。
        let box = WorkspaceWatcherBox()
        box.watcher = self
        // 盒子交给进程级仓库保管（**永不释放**，见 `WorkspaceWatcherBoxes`），
        // 这里故意用 `passUnretained`：生命周期由仓库负责，不归引用计数管。
        WorkspaceWatcherBoxes.keep(box)
        let info = Unmanaged.passUnretained(box).toOpaque()
        streamContextPointer = info
        var context = FSEventStreamContext(
            version: 0, info: info, retain: nil, release: nil, copyDescription: nil
        )
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, count, paths, _, _ in
                guard let info else { return }
                // 迟到回调只会拿到 nil（盒子还活着，监听器可能已经走了）
                guard let watcher = Unmanaged<WorkspaceWatcherBox>.fromOpaque(info)
                    .takeUnretainedValue().watcher else { return }
                // **不把整个数组桥接过去**：`FSEvents` 给的是 `CFArray`，逐元素取字符串更稳
                // （实测：整数组桥接在脚本模式下会崩在 `_conditionallyBridgeFromObjectiveC`）。
                let array = unsafeBitCast(paths, to: CFArray.self)
                var list: [String] = []
                list.reserveCapacity(count)
                for index in 0..<CFArrayGetCount(array) {
                    guard let raw = CFArrayGetValueAtIndex(array, index) else { continue }
                    list.append(Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String)
                }
                watcher.note(paths: list)
            },
            &context,
            [root] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            debounce,
            FSEventStreamCreateFlags(flags)
        ) else {
            // 建流失败 ⇒ 把上面的 retain 退回去，否则监听器永远不释放
            // 盒子不释放：它归 `WorkspaceWatcherBoxes` 所有
            streamContextPointer = nil
            return
        }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        // 与 `start()` 的 passRetained 配对：先 invalidate（不再有回调），再 release
        // 盒子留在仓库里（见 `WorkspaceWatcherBoxes` 的注释），这里只清本地指针
        streamContextPointer = nil
        for (_, source) in fileSources { source.cancel() }
        fileSources = [:]
        onChanges = nil
        pending = []
    }

    /// 工作区根**之外**的单文件监听（`openFileFromPanel` 那种随便打开的文件）。
    func watch(file path: String) {
        guard fileSources[path] == nil else { return }
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .rename, .delete, .extend], queue: queue)
        source.setEventHandler { [weak self] in self?.note(paths: [path]) }
        source.setCancelHandler { close(descriptor) }
        fileSources[path] = source
        source.resume()
    }

    func unwatch(file path: String) {
        fileSources[path]?.cancel()
        fileSources[path] = nil
    }

    // MARK: - 防抖

    private func note(paths: [String]) {
        pending.formUnion(paths)
        guard !flushScheduled else { return }
        flushScheduled = true
        queue.asyncAfter(deadline: .now() + debounce) { [weak self] in
            guard let self else { return }
            self.flushScheduled = false
            let batch = self.pending
            self.pending = []
            guard !batch.isEmpty else { return }
            self.onChanges?(batch.sorted())
        }
    }
}
