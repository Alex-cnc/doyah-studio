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
final class WorkspaceFileWatcher {

    /// 一批改动（防抖后）。
    private var onChanges: (([String]) -> Void)?

    private var stream: FSEventStreamRef?
    /// FSEvents 上下文里 `passRetained(self)` 的那个指针 —— `stop()` 里成对 release。
    /// **必须 retain**：不 retain 时监听器一旦先释放，FSEvents 线程回调 `takeUnretainedValue()`
    /// 就是对一个已释放对象 `objc_msgSend` ⇒ 直接 SIGSEGV（2026-10-18 实测：启动即崩，
    /// 崩溃线程 `studio.doyah.workspace-watcher`，栈顶 `closure #1 in WorkspaceFileWatcher.start`）。
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

        // **passRetained**：让 FSEvents 自己持有监听器，直到 `stop()` 成对 release。
        // 用 passUnretained 是崩溃的根因（见 `streamContextPointer` 注释）。
        let info = Unmanaged.passRetained(self).toOpaque()
        streamContextPointer = info
        var context = FSEventStreamContext(
            version: 0,
            info: info,
            retain: nil, release: nil, copyDescription: nil
        )
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, count, paths, _, _ in
                guard let info else { return }
                let watcher = Unmanaged<WorkspaceFileWatcher>.fromOpaque(info).takeUnretainedValue()
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
            Unmanaged<WorkspaceFileWatcher>.fromOpaque(info).release()
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
        if let pointer = streamContextPointer {
            Unmanaged<WorkspaceFileWatcher>.fromOpaque(pointer).release()
            streamContextPointer = nil
        }
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
