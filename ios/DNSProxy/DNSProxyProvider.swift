import Foundation
import Network
import NetworkExtension

final class DNSProxyProvider: NEDNSProxyProvider {
    private let engine = RuleEngine()
    private let resolver = UpstreamResolver()

    override func startProxy(options: [String: Any]? = nil, completionHandler: @escaping (Error?) -> Void) {
        completionHandler(nil)
    }

    override func stopProxy(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    override func handleNewFlow(_ flow: NEAppProxyFlow) -> Bool {
        guard let udpFlow = flow as? NEAppProxyUDPFlow else { return false }
        udpFlow.open(withLocalEndpoint: nil) { [weak self] error in
            guard error == nil else { return }
            self?.readNext(udpFlow)
        }
        return true
    }

    private func readNext(_ flow: NEAppProxyUDPFlow) {
        flow.readDatagrams { [weak self] datagrams, endpoints, error in
            guard let self, error == nil, let datagrams, let endpoints, !datagrams.isEmpty else {
                return
            }

            let group = DispatchGroup()
            for (index, packet) in datagrams.enumerated() where index < endpoints.count {
                let endpoint = endpoints[index]
                group.enter()

                if let query = DNSQuery.parse(packet), self.engine.isBlocked(query.name) {
                    Stats.addBlocked()
                    let response = query.makeNXDomainResponse()
                    flow.writeDatagrams([response], sentBy: [endpoint]) { _ in
                        group.leave()
                    }
                } else {
                    self.resolver.query(packet) { answer in
                        guard let answer else {
                            group.leave()
                            return
                        }
                        flow.writeDatagrams([answer], sentBy: [endpoint]) { _ in
                            group.leave()
                        }
                    }
                }
            }

            group.notify(queue: .global()) { [weak self] in
                self?.readNext(flow)
            }
        }
    }
}

final class UpstreamResolver {
    private let server: String
    private let queue = DispatchQueue(label: "deadad.dns.upstream")

    init(server: String = "223.5.5.5") {
        self.server = server
    }

    func query(_ packet: Data, completion: @escaping (Data?) -> Void) {
        let host = NWEndpoint.Host(server)
        let port = NWEndpoint.Port(integerLiteral: 53)
        let connection = NWConnection(host: host, port: port, using: .udp)

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: packet, completion: .contentProcessed { error in
                    guard error == nil else {
                        connection.cancel()
                        completion(nil)
                        return
                    }
                    connection.receive(minimumIncompleteLength: 12, maximumLength: 4096) {
                        data, _, _, _ in
                        connection.cancel()
                        completion(data)
                    }
                })
            case .failed, .cancelled:
                completion(nil)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }
}
