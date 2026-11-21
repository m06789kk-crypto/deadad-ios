import Foundation

struct RuleEngine {
    private let domains: [String]

    init(domains: [String]) {
        self.domains = domains
    }

    init() {
        self.init(domains: RuleEngine.loadRules())
    }

    var count: Int { domains.count }

    static func loadRules() -> [String] {
        guard let url = Bundle.main.url(forResource: "rules", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        return text
            .split(separator: "\n")
            .compactMap { rawLine in
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty, !line.hasPrefix("#"), line.contains(".") else { return nil }
                return line.lowercased()
            }
    }

    func isBlocked(_ host: String) -> Bool {
        let name = host.lowercased()
        for domain in domains where name == domain || name.hasSuffix("." + domain) {
            return true
        }
        return false
    }
}
