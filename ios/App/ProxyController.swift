import Foundation
import NetworkExtension

@MainActor
final class ProxyController: ObservableObject {
    @Published var isEnabled = false
    @Published var statusText = "检查中…"
    @Published var errorText: String?

    static let providerBundleID = "com.deadblock.app.dnsproxy"

    init() {
        refresh()
    }

    func refresh() {
        let manager = NEDNSProxyManager.shared()
        manager.loadFromPreferences { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    self?.errorText = error.localizedDescription
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
                    self?.errorText = loadError.localizedDescription
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
                        self?.errorText = saveError.localizedDescription
                    }
                    self?.refresh()
                }
            }
        }
    }
}
