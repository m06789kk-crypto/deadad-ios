import SwiftUI

struct ContentView: View {
    @StateObject private var controller = ProxyController()
    @State private var todayCount = 0
    @State private var totalCount = 0
    @State private var ruleCount = RuleEngine.loadRules().count

    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            Form {
                Section("拦截开关") {
                    Toggle("全机去广告", isOn: Binding(
                        get: { controller.isEnabled },
                        set: { controller.setEnabled($0) }
                    ))
                    Text(controller.statusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let error = controller.errorText {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section("拦截统计") {
                    LabeledContent("今日拦截", value: "\(todayCount) 次")
                    LabeledContent("累计拦截", value: "\(totalCount) 次")
                    Button("清零统计") {
                        Stats.reset()
                        refreshStats()
                    }
                    .foregroundStyle(.red)
                }

                Section("规则") {
                    LabeledContent("内置规则", value: "\(ruleCount) 条")
                    Text("DNS 级拦截：命中规则的域名直接返回「不存在」，其余请求转发给上游 DNS（223.5.5.5）。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("说明") {
                    Text("开启时系统会请求添加 VPN 配置，这是 Network Extension 的正常流程，不会改变你的网络线路。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("部分 App 用同一域名同时下发内容和广告，这类广告无法靠 DNS 拦掉。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("DeadAd")
            .onAppear {
                refreshStats()
                ruleCount = RuleEngine.loadRules().count
            }
            .onReceive(timer) { _ in
                refreshStats()
            }
        }
    }

    private func refreshStats() {
        let snapshot = Stats.snapshot()
        todayCount = snapshot.today
        totalCount = snapshot.total
    }
}
