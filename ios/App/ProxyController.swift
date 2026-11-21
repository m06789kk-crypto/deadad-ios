import Foundation
import NetworkExtension

@MainActor
final class ProxyController: ObservableObject {
    @Published var isEnabled = false
    @Published var statusText = "检查中…"
    @Published var errorText: String?

    /// 扩展 Bundle ID 跟着主 App 走，换签名证书改 Bundle ID 后依然对得上。
    static var providerBundleID: String {
        (Bundle.main.bundleIdentifier ?? "com.deadblock.app") + ".dnsproxy"
    }

    init() {
        refresh()
    }

    func refresh() {
        let manager = NEDNSProxyManager.shared()
        manager.loadFromPreferences { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    self?.errorText = Self.friendly(error)
                }
                self?.isEnabled = manager.isEnabled
                self?.statusText = manager.isEnabled ? "全机拦截已开启" : "全机拦截已关闭"
            }
        }
    }

    func setEnabled(_ enabled: Bool) {
        let manager = NEDNSProxyManager.shared()
        manager.loadFromPreferences { [weak self] loadError in
            if let loadError {
                DispatchQueue.main.async {
                    self?.errorText = Self.friendly(loadError)
                }
                return
            }

            manager.localizedDescription = "DeadAd 全机去广告"
            let proto = NEDNSProxyProviderProtocol()
            proto.providerBundleIdentifier = ProxyController.providerBundleID
            manager.providerProtocol = proto
            manager.isEnabled = enabled

            manager.saveToPreferences { [weak self] saveError in
                DispatchQueue.main.async {
                    if let saveError {
                        self?.errorText = Self.friendly(saveError)
                    } else {
                        self?.errorText = nil
                    }
                    self?.refresh()
                }
            }
        }
    }

    private static func friendly(_ error: Error) -> String {
        let message = error.localizedDescription
        let lower = message.lowercased()

        if lower.contains("permission denied") || lower.contains("not entitled") {
            return "签名缺少 Network Extension（dns-proxy）权限。请让签名方在描述文件里启用该权限，并用自带的 entitlements 重新签名。原始错误：\(message)"
        }
        if lower.contains("no provider") || lower.contains("provider not found") {
            return "系统找不到 DNS 扩展（PlugIns/DNSProxy.appex 没被正确嵌入或签名）。请用最新的 IPA 重新安装。原始错误：\(message)"
        }
        if lower.contains("configuration invalid") || lower.contains("invalid") {
            return "代理配置无效，可能是扩展 Bundle ID 与 App 内写的不一致。原始错误：\(message)"
        }
        return message
    }
}
