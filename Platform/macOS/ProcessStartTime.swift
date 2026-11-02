import Foundation

/// 进程创建时刻（内核记录的那一个）。
///
/// 为什么不用「App 里第一行执行到的 `Date()`」当冷启动起点：那会把 dyld 解析、
/// 动态链接、静态初始化这段**最不可控**的耗时整段算作免费 —— 实测这类开销在
/// 冷启动里占得不小，而用户感知的「点了图标到界面能点」是**含**它的。
///
/// 取法：`sysctl([CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()])` 读 `kinfo_proc`，
/// 其 `kp_proc.p_starttime` 就是内核对本进程的创建时刻（与 `ps -o lstart` 同源）。
///
/// 边界：读不到（`sysctl` 失败 / 大小不符）⇒ 返回 `nil`，由调用方决定退化成
/// 「自己第一行」并**把退化这件事写进收据**，不许静默当成同一件事。
public enum ProcessStartTime {

    public static func current() -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        let status = mib.withUnsafeMutableBufferPointer { buffer in
            sysctl(buffer.baseAddress, u_int(buffer.count), &info, &size, nil, 0)
        }
        guard status == 0, size > 0 else { return nil }
        let start = info.kp_proc.p_starttime
        let seconds = Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000
        guard seconds.isFinite, seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}
