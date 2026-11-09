import CryptoKit
import XCTest

/// `check-ui-snapshot-languages.py` 的 Swift 版：**界面快照的语言覆盖**（队列 L-13）。
///
/// 为什么要有它：L-13 把「语言」做成了宿主参数，于是每张图都有中英两份。但「两份都生成了」
/// **不等于**「语言到了像素上」—— 最容易发生的退化是宿主参数被忽略、或某个面板的文案走了绕过
/// `L(...)` 的路，于是两张图**逐字节相同**，而图看起来照样正常（第 10 / 11 轮吃过两次
/// 「判据太松」的亏：一次是假绿的占位图，一次是注释里的假设被实测推翻）。
///
/// 判据（两个方向都是硬的，只留一个口子）：
/// · **未注册**的快照：中英两张 PNG 必须**逐字节不同** —— 相同 ⇒ 语言没到像素上
///   （若确实语言无关，请显式注册并写明理由）；
/// · **已注册为语言无关**的快照：两张必须**逐字节相同** —— 不同 ⇒ 条目过期，必须删掉；
/// · 注册表里不得有陈旧条目（manifest 里没有这张图 ⇒ 红；`--partial` 筛选跑除外）；
/// · 每个快照名必须带 `-zh` / `-en`，且每个 base 恰好各一份；
/// · 每条记录必须带 `language` 与 `localizedStrings`（证明快照工具自己把语言落进了清单）。
///
/// 跑法：由 `Scripts/make-ui-snapshots.sh` 在渲染完之后调用
/// （`DOYAH_SNAPSHOT_LANGUAGE_GATE=1 DOYAH_SNAPSHOT_PARTIAL=… swift test --filter UISnapshotLanguageCoverageTests`）
/// —— 快照是取证工具、不进每轮闭环，但**取证那一刻**要把这件事判住。
final class UISnapshotLanguageCoverageTests: XCTestCase {

    static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    enum Gate {
        static let languageSuffix: [(suffix: String, language: String)] = [("-zh", "zh-Hans"), ("-en", "en")]
        static let exemptionsRel = "Scripts/ui-snapshot-language-exemptions.json"

        struct Record {
            var name: String
            var file: String
            var language: String?
            var localizedStrings: [String]?
        }

        struct Reading {
            var problems: [String] = []
            var notes: [String] = []
            var pairs = 0
            var identicalRegistered = 0
            var snapshots = 0
        }

        static func split(_ name: String) -> (base: String, language: String)? {
            for entry in languageSuffix where name.hasSuffix(entry.suffix) {
                return (String(name.dropLast(entry.suffix.count)), entry.language)
            }
            return nil
        }

        static func sha256(_ url: URL) -> String? {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }

        /// 判定本体。`fileExists` / `hash` 由调用方给（测试可以喂临时文件或内存桩）。
        static func judge(records: [Record],
                          exemptions: [String: String],
                          partial: Bool,
                          fileExists: (String) -> Bool,
                          hash: (String) -> String?) -> Reading {
            var reading = Reading()
            reading.snapshots = records.count
            var groups: [String: [String: Record]] = [:]
            for record in records {
                guard let split = split(record.name) else {
                    reading.problems.append("\(record.name)：快照名没带语言后缀（-zh / -en）")
                    continue
                }
                if record.language != split.language {
                    reading.problems.append("\(record.name)：名字说的是 \(split.language)，记录里写的却是 "
                                            + "\(record.language ?? "nil")")
                }
                if record.localizedStrings == nil {
                    reading.problems.append("\(record.name)：记录里没有 `localizedStrings`（语言没被观测，判据无从下手）")
                }
                if groups[split.base]?[split.language] != nil {
                    reading.problems.append("\(record.name)：同一个语言出现了两份（\(split.base) · \(split.language)）")
                }
                groups[split.base, default: [:]][split.language] = record
            }
            if groups.isEmpty {
                reading.problems.append("一条都不成对，判据无从下手")
                return reading
            }
            var missingEntries: [String] = []
            for (base, reason) in exemptions.sorted(by: { $0.key < $1.key }) {
                if reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    reading.problems.append("\(base)：注册为语言无关却没写理由（理由就是这条判据的可读性）")
                }
                if groups[base] == nil {
                    if partial {
                        missingEntries.append(base)
                    } else {
                        reading.problems.append("\(base)：注册表里有这个条目，但清单里没有这张图 —— 陈旧条目，请删掉")
                    }
                }
            }
            if !missingEntries.isEmpty {
                reading.notes.append("局部清单（partial）：注册表里另有 \(missingEntries.count) 条不在这一份里 —— "
                                     + "陈旧与否由**全量跑**判")
            }
            var identicalRegistered: [String] = []
            for base in groups.keys.sorted() {
                let bucket = groups[base] ?? [:]
                let missing = languageSuffix.map(\.language).filter { bucket[$0] == nil }
                if !missing.isEmpty {
                    reading.problems.append("\(base)：缺 \(missing.joined(separator: ", ")) —— 语言覆盖缺了一半")
                    continue
                }
                let chinese = bucket["zh-Hans"]!
                let english = bucket["en"]!
                let missingFiles = [chinese, english].filter { !fileExists($0.file) }
                if !missingFiles.isEmpty {
                    for record in missingFiles {
                        reading.problems.append("\(record.name)：清单指向的 PNG 不在（\(record.file)）")
                    }
                    continue
                }
                reading.pairs += 1
                let samePixels = hash(chinese.file) == hash(english.file)
                let textsDiffer = (chinese.localizedStrings ?? []).sorted() != (english.localizedStrings ?? []).sorted()
                if exemptions[base] != nil {
                    if !samePixels {
                        reading.problems.append("\(base)：注册为语言无关，但中英两张**已经不一样**了 —— 条目过期，请删掉")
                    }
                    identicalRegistered.append(base)
                    if textsDiffer {
                        reading.notes.append("\(base)：语言无关，但两遍文案**不同** —— 文案没进像素（只到 .help / 无障碍标签）")
                    }
                } else {
                    if samePixels {
                        reading.problems.append("\(base)：中英两张 PNG **逐字节相同** ⇒ 语言没到像素上"
                                                + "（若确实语言无关，请到 \(exemptionsRel) 注册并写明理由）")
                    }
                    if !textsDiffer {
                        reading.notes.append("\(base)：两遍观测到的文案相同 —— 它的语言差异不是文案带来的")
                    }
                }
            }
            reading.identicalRegistered = identicalRegistered.count
            return reading
        }
    }

    // MARK: - 真清单（快照收尾那一刻跑）

    func testManifestLanguageCoverage() throws {
        guard ProcessInfo.processInfo.environment["DOYAH_SNAPSHOT_LANGUAGE_GATE"] == "1" else {
            throw XCTSkip("语言覆盖判据只在快照收尾那一刻跑"
                          + "（DOYAH_SNAPSHOT_LANGUAGE_GATE=1；见 Scripts/make-ui-snapshots.sh）")
        }
        let manifestURL: URL
        if let override = ProcessInfo.processInfo.environment["DOYAH_SNAPSHOT_DIR"], !override.isEmpty {
            manifestURL = URL(fileURLWithPath: override, isDirectory: true).appendingPathComponent("manifest.json")
        } else {
            manifestURL = Self.packageRoot.appendingPathComponent(".build/ui-snapshots/manifest.json")
        }
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            XCTFail("没有清单：\(manifestURL.path)（先跑 ./Scripts/make-ui-snapshots.sh）")
            return
        }
        let data = try Data(contentsOf: manifestURL)
        let payload = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let rawSnapshots = (payload["snapshots"] as? [[String: Any]]) ?? []
        XCTAssertFalse(rawSnapshots.isEmpty, "清单里一条快照都没有：\(manifestURL.path)")
        let records = rawSnapshots.map { item in
            Gate.Record(name: (item["name"] as? String) ?? "",
                        file: (item["file"] as? String) ?? "",
                        language: item["language"] as? String,
                        localizedStrings: item["localizedStrings"] as? [String])
        }
        let exemptionsURL = Self.packageRoot.appendingPathComponent(Gate.exemptionsRel)
        var exemptions: [String: String] = [:]
        if let data = try? Data(contentsOf: exemptionsURL),
           let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let entries = payload["exemptions"] as? [String: Any] {
            for (key, value) in entries { exemptions[key] = value as? String ?? "" }
        }
        let partial = ProcessInfo.processInfo.environment["DOYAH_SNAPSHOT_PARTIAL"] == "1"
        let reading = Gate.judge(records: records, exemptions: exemptions, partial: partial,
                                 fileExists: { FileManager.default.fileExists(atPath: $0) },
                                 hash: { Gate.sha256(URL(fileURLWithPath: $0)) })
        XCTAssertTrue(reading.problems.isEmpty,
                      "语言覆盖门禁未通过（\(reading.problems.count) 项）：\n" + reading.problems.joined(separator: "\n"))
        print("📏 语言覆盖：\(reading.snapshots) 张 / \(reading.pairs) 组（随语言变化 \(reading.pairs - reading.identicalRegistered) 组，"
              + "注册为语言无关 \(reading.identicalRegistered) 组）")
    }

    // MARK: - 反例（临时目录里的真 PNG）

    private func makePNG(_ directory: URL, _ name: String, bytes: [UInt8]) throws -> String {
        let url = directory.appendingPathComponent(name)
        try Data(bytes).write(to: url)
        return url.path
    }

    private func judgeFixture(_ directory: URL,
                              pairs: [(base: String, zh: [UInt8], en: [UInt8])],
                              exemptions: [String: String] = [:],
                              partial: Bool = false) -> Gate.Reading {
        var records: [Gate.Record] = []
        for pair in pairs {
            let zh = (try? makePNG(directory, "\(pair.base)-zh.png", bytes: pair.zh)) ?? ""
            let en = (try? makePNG(directory, "\(pair.base)-en.png", bytes: pair.en)) ?? ""
            records.append(Gate.Record(name: "\(pair.base)-zh", file: zh, language: "zh-Hans", localizedStrings: ["甲"]))
            records.append(Gate.Record(name: "\(pair.base)-en", file: en, language: "en", localizedStrings: ["A"]))
        }
        return Gate.judge(records: records, exemptions: exemptions, partial: partial,
                          fileExists: { FileManager.default.fileExists(atPath: $0) },
                          hash: { Gate.sha256(URL(fileURLWithPath: $0)) })
    }

    func testIdenticalPixelsAreRedUnlessRegistered() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lang-coverage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let unregistered = judgeFixture(directory, pairs: [("plain", [1, 2, 3], [1, 2, 3])])
        XCTAssertTrue(unregistered.problems.contains { $0.contains("逐字节相同") },
                      "未注册却逐字节相同必须判红：\(unregistered.problems)")

        let registered = judgeFixture(directory, pairs: [("plain", [1, 2, 3], [1, 2, 3])],
                                      exemptions: ["plain": "活动栏只走到 .help 与无障碍标签，不进像素"])
        XCTAssertTrue(registered.problems.isEmpty, "注册为语言无关后应绿：\(registered.problems)")

        let stale = judgeFixture(directory, pairs: [("plain", [1, 2, 3], [9, 9, 9])],
                                 exemptions: ["plain": "夹具：条目过期"])
        XCTAssertTrue(stale.problems.contains { $0.contains("已经不一样") },
                      "注册了却已经不一样必须判红（条目过期）：\(stale.problems)")
    }

    func testMissingPairAndStaleEntryAreRed() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lang-coverage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // 只有英文那一份 ⇒ 缺一半。
        let zhPath = try makePNG(directory, "lonely-zh.png", bytes: [1])
        let records = [Gate.Record(name: "lonely-zh", file: zhPath, language: "zh-Hans", localizedStrings: [])]
        let lonely = Gate.judge(records: records, exemptions: [:], partial: false,
                                fileExists: { FileManager.default.fileExists(atPath: $0) },
                                hash: { Gate.sha256(URL(fileURLWithPath: $0)) })
        XCTAssertTrue(lonely.problems.contains { $0.contains("缺 en") }, "缺一半必须判红：\(lonely.problems)")

        let stale = judgeFixture(directory, pairs: [("gone", [1], [2])], exemptions: ["gone": "夹具"], partial: false)
        XCTAssertFalse(stale.problems.isEmpty)

        let partial = judgeFixture(directory, pairs: [("shot", [1], [2])],
                                   exemptions: ["not-in-this-batch": "夹具：这一次没拍"], partial: true)
        XCTAssertTrue(partial.problems.isEmpty, "筛选跑的局部清单不许把没拍到的条目判成陈旧：\(partial.problems)")
        XCTAssertTrue(partial.notes.contains { $0.contains("局部清单") }, "应留下如实登记的读数：\(partial.notes)")
    }

    func testNameAndRecordShapeAreChecked() {
        let records = [
            Gate.Record(name: "no-suffix", file: "/tmp/x.png", language: "zh-Hans", localizedStrings: []),
            Gate.Record(name: "wrong-lang-zh", file: "/tmp/y.png", language: "en", localizedStrings: []),
            Gate.Record(name: "no-strings-zh", file: "/tmp/z.png", language: "zh-Hans", localizedStrings: nil),
            Gate.Record(name: "dup-zh", file: "/tmp/a.png", language: "zh-Hans", localizedStrings: []),
            Gate.Record(name: "dup-zh", file: "/tmp/b.png", language: "zh-Hans", localizedStrings: []),
        ]
        let reading = Gate.judge(records: records, exemptions: [:], partial: false,
                                 fileExists: { _ in false }, hash: { _ in nil })
        XCTAssertTrue(reading.problems.contains { $0.contains("没带语言后缀") }, "缺后缀必须判红：\(reading.problems)")
        XCTAssertTrue(reading.problems.contains { $0.contains("名字说的是") }, "记录的 language 必须与名字一致：\(reading.problems)")
        XCTAssertTrue(reading.problems.contains { $0.contains("localizedStrings") }, "缺 localizedStrings 必须判红：\(reading.problems)")
        XCTAssertTrue(reading.problems.contains { $0.contains("同一个语言出现了两份") }, "同语言两份必须判红：\(reading.problems)")
    }
}
