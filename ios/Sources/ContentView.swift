import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var showPicker = false
    @State private var status = "还没有选择 IPA"
    @State private var inspection: Inspection?
    @State private var selected: Set<String> = []
    @State private var busy = false
    @State private var log: [String] = []

    private let processor = IPAProcessor.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("① 选择文件") {
                    Button {
                        showPicker = true
                    } label: {
                        Label("选择 IPA", systemImage: "doc.badge.plus")
                    }
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let inspection {
                    Section("② 包信息") {
                        LabeledContent("App", value: inspection.appName)
                        LabeledContent("Bundle ID", value: inspection.bundleID)
                        LabeledContent("版本", value: inspection.version)
                        LabeledContent("Mach-O", value: "\(inspection.binaryCount) 个")
                        LabeledContent("加密", value: inspection.encrypted ? "是（产物无法运行）" : "否")
                    }

                    Section("③ 广告 SDK（\(inspection.hits.count)）") {
                        if inspection.hits.isEmpty {
                            Text("没有命中内置指纹")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(inspection.hits) { hit in
                            Toggle(isOn: binding(for: hit.id)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(hit.name)
                                    Text(hit.riskHigh ? "高风险：App 仍在引用，剔除后可能闪退" : "可安全剥离")
                                        .font(.caption)
                                        .foregroundStyle(hit.riskHigh ? .orange : .secondary)
                                }
                            }
                        }
                    }

                    Section("④ 导出") {
                        Button(busy ? "处理中…" : "剥离选中项并导出 IPA") {
                            run(inspection)
                        }
                        .disabled(busy || selected.isEmpty)
                    }
                }

                if !log.isEmpty {
                    Section("日志") {
                        ForEach(log, id: \.self) { line in
                            Text(line).font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("DeadAd")
            .fileImporter(
                isPresented: $showPicker,
                allowedContentTypes: [.data],
                allowsMultipleSelection: false
            ) { result in
                handlePick(result)
            }
        }
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { selected.contains(id) },
            set: { isOn in
                if isOn {
                    selected.insert(id)
                } else {
                    selected.remove(id)
                }
            }
        )
    }

    private func handlePick(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            status = "选择失败：\(error.localizedDescription)"
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            busy = true
            status = "正在解析…"
            DispatchQueue.global(qos: .userInitiated).async {
                defer {
                    if scoped { url.stopAccessingSecurityScopedResource() }
                }
                do {
                    let copy = FileManager.default.temporaryDirectory
                        .appendingPathComponent("input-\(UUID().uuidString).ipa")
                    try FileManager.default.copyItem(at: url, to: copy)
                    let result = try IPAProcessor.shared.open(ipa: copy)
                    DispatchQueue.main.async {
                        inspection = result
                        selected = Set(result.hits.filter { !$0.riskHigh }.map { $0.id })
                        status = "已解析，可勾选要剥离的 SDK"
                        busy = false
                    }
                } catch {
                    DispatchQueue.main.async {
                        status = "解析失败：\(error)"
                        busy = false
                    }
                }
            }
        }
    }

    private func run(_ inspection: Inspection) {
        busy = true
        log = []
        let chosen = inspection.hits.filter { selected.contains($0.id) }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                var lines = try IPAProcessor.shared.strip(hits: chosen, forceRisk: false)
                if lines.isEmpty {
                    lines.append("没有删除任何东西")
                }
                let name = "\(inspection.appName)-clean.ipa"
                let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let output = documents.appendingPathComponent(name)
                try IPAProcessor.shared.pack(to: output)
                lines.append("已导出 \(name)")
                lines.append("在「文件」App → 我的 iPhone → DeadAd 里取走，再用自签工具安装")
                DispatchQueue.main.async {
                    log = lines
                    status = "完成"
                    busy = false
                }
            } catch {
                DispatchQueue.main.async {
                    log = ["失败：\(error)"]
                    busy = false
                }
            }
        }
    }
}
