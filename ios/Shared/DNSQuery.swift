import Foundation

struct DNSQuery {
    let identifier: UInt16
    let name: String
    let question: Data

    static func parse(_ packet: Data) -> DNSQuery? {
        guard packet.count >= 12 else { return nil }
        guard readUInt16(packet, 4) >= 1 else { return nil }
        let identifier = readUInt16(packet, 0)

        var offset = 12
        var labels: [String] = []
        while offset < packet.count {
            let length = Int(packet[offset])
            if length == 0 {
                offset += 1
                break
            }
            if length & 0xC0 != 0 { return nil }
            let start = offset + 1
            guard start + length <= packet.count else { return nil }
            let labelData = packet.subdata(in: start..<(start + length))
            labels.append(String(decoding: labelData, as: UTF8.self))
            offset = start + length
            if labels.count > 32 { return nil }
        }
        guard offset + 4 <= packet.count else { return nil }
        let name = labels.joined(separator: ".")
        guard !name.isEmpty else { return nil }

        let question = packet.subdata(in: 12..<(offset + 4))
        return DNSQuery(identifier: identifier, name: name, question: question)
    }

    func makeNXDomainResponse() -> Data {
        var data = Data()
        data.append(UInt8(identifier >> 8))
        data.append(UInt8(identifier & 0xFF))
        data.append(0x81)
        data.append(0x83)
        data.append(contentsOf: [0x00, 0x01])
        data.append(contentsOf: [0x00, 0x00])
        data.append(contentsOf: [0x00, 0x00])
        data.append(contentsOf: [0x00, 0x00])
        data.append(question)
        return data
    }
}

func readUInt16(_ data: Data, _ offset: Int) -> UInt16 {
    guard offset >= 0, offset + 2 <= data.count else { return 0 }
    return (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
}
