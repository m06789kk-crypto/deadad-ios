import Foundation
import ZIPFoundation

enum ProcessorError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let text): return text
        }
    }
}

struct SDKHit: Identifiable {
    var id: String { key + "|" + framework }

    let key: String
    let name: String
    let framework: String
    var linkedPaths: [String]
    var classRefs: [String]

    var riskHigh: Bool { !classRefs.isEmpty }
    var removable: Bool { !riskHigh }
}

struct Inspection {
    let appName: String
    let bundleID: String
    let version: String
    let encrypted: Bool
    let binaryCount: Int
    let frameworks: [String]
    let hits: [SDKHit]
}

final class IPAProcessor {
    static let shared = IPAProcessor()

    private let fm = FileManager.default
    private(set) var rootDirectory: URL?
    private(set) var appDirectory: URL?

    // MARK: - 打开 / 解析

    func open(ipa: URL) throws -> Inspection {
        close()
        let root = fm.temporaryDirectory.appendingPathComponent("deadad-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        rootDirectory = root

        let unpacked = root.appendingPathComponent("unpacked", isDirectory: true)
        try fm.createDirectory(at: unpacked, withIntermediateDirectories: true)
        try fm.unzipItem(at: ipa, to: unpacked)

        let payloadURL = unpacked.appendingPathComponent("Payload", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: payloadURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ProcessorError.message("不是标准 IPA：缺少 Payload/ 目录")
        }
        let entries = try fm.contentsOfDirectory(at: payloadURL, includingPropertiesForKeys: nil)
        guard let app = entries.first(where: { $0.pathExtension == "app" }) else {
            throw ProcessorError.message("Payload/ 里没有 .app")
        }
        appDirectory = app
        return inspect(app: app)
    }

    private func inspect(app: URL) -> Inspection {
        var info: [String: Any] = [:]
        let infoURL = app.appendingPathComponent("Info.plist")
        if let data = try? Data(contentsOf: infoURL),
           let parsed = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
           let dict = parsed as? [String: Any] {
            info = dict
        }

        let binaries = machoFiles(in: app)
        var parsedBinaries: [MachOFile] = []
        var encrypted = false
        for url in binaries {
            guard let data = try? Data(contentsOf: url), let macho = try? MachOFile(data: data) else { continue }
            parsedBinaries.append(macho)
            if macho.encrypted { encrypted = true }
        }

        let frameworksURL = app.appendingPathComponent("Frameworks", isDirectory: true)
        let frameworks = ((try? fm.contentsOfDirectory(at: frameworksURL, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "framework" }
            .map { $0.lastPathComponent }

        var hits: [SDKHit] = []
        for sdk in AdSDKDatabase.all {
            let present = sdk.frameworks.filter { frameworks.contains($0) }

            var linked: [String] = []
            for macho in parsedBinaries {
                for path in macho.dylibs() where present.contains(where: { path.contains("/\($0)/") }) {
                    if !linked.contains(path) { linked.append(path) }
                }
            }

            var refs: [String] = []
            for prefix in sdk.classPrefixes {
                let needle = "_OBJC_CLASS_$_" + prefix
                if parsedBinaries.contains(where: { $0.containsSymbol(needle) }) {
                    refs.append(prefix)
                }
            }

            guard !present.isEmpty || !linked.isEmpty else { continue }
            hits.append(
                SDKHit(
                    key: sdk.key,
                    name: sdk.name,
                    framework: present.first ?? sdk.frameworks.first ?? sdk.key,
                    linkedPaths: linked,
                    classRefs: refs
                )
            )
        }

        return Inspection(
            appName: info["CFBundleDisplayName"] as? String
                ?? info["CFBundleName"] as? String
                ?? app.deletingPathExtension().lastPathComponent,
            bundleID: info["CFBundleIdentifier"] as? String ?? "?",
            version: info["CFBundleShortVersionString"] as? String ?? "?",
            encrypted: encrypted,
            binaryCount: parsedBinaries.count,
            frameworks: frameworks,
            hits: hits
        )
    }

    // MARK: - 剥离

    func strip(hits: [SDKHit], forceRisk: Bool) throws -> [String] {
        guard let app = appDirectory else { throw ProcessorError.message("还没有打开 IPA") }
        var log: [String] = []
        let frameworksURL = app.appendingPathComponent("Frameworks", isDirectory: true)

        var removedFrameworks: Set<String> = []
        for hit in hits {
            if hit.riskHigh && !forceRisk {
                log.append("跳过 \(hit.name)：App 仍引用 \(hit.classRefs.joined(separator: "、"))，剔除后可能闪退")
                continue
            }
            let frameworkURL = frameworksURL.appendingPathComponent(hit.framework, isDirectory: true)
            if fm.fileExists(atPath: frameworkURL.path) {
                try fm.removeItem(at: frameworkURL)
                log.append("已删除 \(hit.framework)")
            }
            removedFrameworks.insert(hit.framework)
            let bundles = AdSDKDatabase.all.first(where: { $0.key == hit.key })?.bundles ?? []
            for bundle in bundles {
                let bundleURL = app.appendingPathComponent(bundle, isDirectory: true)
                if fm.fileExists(atPath: bundleURL.path) {
                    try fm.removeItem(at: bundleURL)
                    log.append("已删除 \(bundle)")
                }
            }
        }

        guard !removedFrameworks.isEmpty else { return log }

        for url in machoFiles(in: app) {
            guard let data = try? Data(contentsOf: url), var macho = try? MachOFile(data: data) else { continue }
            let targets = Set(
                macho.dylibs().filter { path in removedFrameworks.contains { path.contains("/\($0)/") } }
            )
            guard !targets.isEmpty else { continue }
            let removed = try macho.removeDylibs(targets)
            if !removed.isEmpty {
                try macho.data.write(to: url, options: .atomic)
                makeExecutable(url)
                log.append("已断开 \(url.lastPathComponent) 的 \(removed.count) 条广告库链接")
            }
        }
        return log
    }

    // MARK: - 导出

    func pack(to destination: URL) throws {
        guard let root = rootDirectory else { throw ProcessorError.message("还没有打开 IPA") }
        let unpacked = root.appendingPathComponent("unpacked", isDirectory: true)
        for url in machoFiles(in: unpacked) {
            makeExecutable(url)
        }
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.zipItem(at: unpacked, to: destination, shouldKeepParent: false, compressionMethod: .deflate)
    }

    func close() {
        if let root = rootDirectory {
            try? fm.removeItem(at: root)
        }
        rootDirectory = nil
        appDirectory = nil
    }

    // MARK: - 工具

    private func machoFiles(in directory: URL) -> [URL] {
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var result: [URL] = []
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            guard let handle = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? handle.close() }
            guard let head = try? handle.read(upToCount: 16), head.count >= 8 else { continue }
            if looksLikeMachO(head) {
                result.append(url)
            }
        }
        return result
    }

    private func makeExecutable(_ url: URL) {
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
