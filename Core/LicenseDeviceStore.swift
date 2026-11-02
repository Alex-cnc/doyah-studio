import Foundation

/// **设备配额与设备管理**（`FR-STD-ALL-LIC-005`）：默认 5 台、**可释放**、换机不锁。
///
/// ## 为什么设备台账在**本地**、不写进许可证文件
///
/// 许可证文件是**发行方签名**的（`LicenseFile.payload` + detached 签名）。设备是使用过程中
/// 长出来的状态，本地一改签名就对不上 —— 于是只有两条路：把设备写进签名载荷（那每次换机
/// 都要找发行方重签，离线许可当场作废），或者**把设备登记留在本机**（`license-devices.json`，
/// 与许可证同目录）。
///
/// 选后者，并把代价写清楚：这份台账**不带签名、可被手改**（ADR-34：不做 DRM、不联网激活、
/// 不采集硬件指纹）—— 配额是「防顺手共享」的引信，不是防破解的锁。改它不会让人多拿到功能，
/// 只会让本机多算几台。
///
/// ## 口径
///
/// · 配额上限**只从许可证读**（`license.maxDevices`，默认 5），这里不写第二个默认值；
/// · 满了**必须指名先释放哪一台**（最早激活的那台），不给人一句「已达上限」；
/// · 释放之后配额立刻回来（`remaining` 跟着变）；
/// · **到期不影响设备管理**：到期只降呈现（`LicenseGate`），换机照旧（判据 003 的口径）。
public struct LicenseDeviceStore: Sendable {

    /// 台账文件格式。`slots` 以「许可证开给谁」为键：同一个人换许可证（续期 / 升档）
    /// 设备不清零 —— 续期把用户已登记的设备抹掉，是最没道理的一种「降级」。
    public struct Ledger: Codable, Equatable, Sendable {
        public var version: Int
        public var slots: [String: [LicenseDevice]]

        public init(version: Int = LicenseDeviceStore.formatVersion, slots: [String: [LicenseDevice]] = [:]) {
            self.version = version
            self.slots = slots
        }
    }

    public static let formatVersion = 1

    /// 台账文件名（与许可证同目录）。
    public static let fileName = "license-devices.json"

    /// `nil` = **纯内存**（单测用；不落盘，不碰用户目录）。
    private let fileURL: URL?

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL
    }

    /// 默认位置：许可证所在目录 `/license-devices.json`。
    ///
    /// 与许可证同目录而不是另开一个数据家：换机时用户搬的正是这一整个目录
    /// （`Application Support/DoyahStudio/`），拆开就等于「搬了许可证、设备台账丢了」。
    public static func defaultFileURL(licenseURL: URL = LicenseLoader.defaultLicenseURL()) -> URL {
        licenseURL.deletingLastPathComponent().appendingPathComponent(fileName, isDirectory: false)
    }

    // MARK: - 读

    /// 这台机器上，该许可证已登记的设备。
    ///
    /// 台账里还没有这一位用户时，**以许可证载荷里声明的设备为初值**（发行方签的那份是
    /// 权威清单；本地台账只承接「后来在本机登记 / 释放」的那部分变化）。
    public func devices(for license: License) -> [LicenseDevice] {
        let key = Self.key(for: license)
        if let stored = loadLedger().slots[key] { return stored }
        return license.devices
    }

    /// 还剩几台可登记（不小于 0 —— 配额被改小时不出现「负几台」）。
    public func remaining(for license: License, now: Date = Date()) -> Int {
        _ = now
        return max(0, license.maxDevices - devices(for: license).count)
    }

    /// 一台都没登记时也要给出配额（界面据此说「配额 5 台」，不写「0 台」）。
    public func quota(for license: License) -> Int { license.maxDevices }

    // MARK: - 写

    /// 登记一台设备。配额满 ⇒ `License.DeviceError.quotaExceeded`（带「建议释放哪一台」）。
    @discardableResult
    public func activate(
        named name: String,
        for license: License,
        id: UUID = UUID(),
        now: Date = Date()
    ) throws -> LicenseDevice {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var current = devices(for: license)
        guard !current.contains(where: { $0.id == id }) else {
            throw License.DeviceError.alreadyRegistered(id)
        }
        guard current.count < license.maxDevices else {
            let suggestion = current.min { $0.addedAt < $1.addedAt }?.name
            throw License.DeviceError.quotaExceeded(max: license.maxDevices, suggestion: suggestion)
        }
        let device = LicenseDevice(id: id, name: trimmed.isEmpty ? "Mac" : trimmed, addedAt: now)
        current.append(device)
        try store(current, for: license)
        return device
    }

    /// 释放一台设备（配额立刻回来）。**到期也允许** —— 换机不锁是硬口径。
    public func release(_ id: UUID, for license: License) throws {
        var current = devices(for: license)
        guard let index = current.firstIndex(where: { $0.id == id }) else {
            throw License.DeviceError.unknownDevice(id)
        }
        current.remove(at: index)
        try store(current, for: license)
    }

    // MARK: - 落盘

    private static func key(for license: License) -> String {
        // 键 = 开给谁（去掉首尾空白）。**不掺能力位 / 到期时间**：续期与升档是同一个人，
        // 掺进去就等于「换一份许可证 → 设备清零 → 老机器被当成新机器」。
        license.issuedTo.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loadLedger() -> Ledger {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let ledger = try? Self.decoder().decode(Ledger.self, from: data) else {
            // 读不出来（首次运行 / 文件被手改坏）⇒ 当成空台账，初值退到许可证载荷里的设备。
            // **不静默删文件**：坏文件留在盘上，用户自己的数据不归这里清。
            return Ledger()
        }
        return ledger
    }

    private func store(_ devices: [LicenseDevice], for license: License) throws {
        var ledger = loadLedger()
        ledger.slots[Self.key(for: license)] = devices
        guard let fileURL else { return }  // 内存模式：写进本次调用即止（单测用）
        let folder = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Self.encoder().encode(ledger).write(to: fileURL, options: [.atomic])
    }

    /// 编解码只用一处：`addedAt` 是日期，**写的时候按 ISO8601、读的时候也必须按 ISO8601** ——
    /// 两边各写一个默认解码器，日期就成了「写进去读不回来」，而症状是「激活了但台账还是空的」
    /// （2026-11-02 本族用例第一版实测：9 例里 8 例红，全部是这条）。
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
