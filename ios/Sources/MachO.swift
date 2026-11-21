import Foundation

enum MachOError: Error, CustomStringConvertible {
    case invalid(String)

    var description: String {
        switch self {
        case .invalid(let message): return message
        }
    }
}

private let lcLoadDylib: UInt32 = 0xC
private let lcLoadWeakDylib: UInt32 = 0x8000_0018
private let lcReexportDylib: UInt32 = 0x8000_001F
private let lcLoadUpwardDylib: UInt32 = 0x8000_0023
private let lcLazyLoadDylib: UInt32 = 0x20
private let lcSegment: UInt32 = 0x1
private let lcSegment64: UInt32 = 0x19
private let lcEncryptionInfo: UInt32 = 0x21
private let lcEncryptionInfo64: UInt32 = 0x2C

private let machMagic: UInt32 = 0xFEED_FACE
private let machMagic64: UInt32 = 0xFEED_FACF
private let fatMagic: UInt32 = 0xCAFE_BABE
private let fatMagic64: UInt32 = 0xCAFE_BABF

private let dylibLoadCommands: Set<UInt32> = [
    lcLoadDylib, lcLoadWeakDylib, lcReexportDylib, lcLoadUpwardDylib, lcLazyLoadDylib,
]

func readU32(_ data: Data, _ offset: Int, bigEndian: Bool = false) -> UInt32 {
    guard offset >= 0, offset + 4 <= data.count else { return 0 }
    let raw = UInt32(data[offset])
        | (UInt32(data[offset + 1]) << 8)
        | (UInt32(data[offset + 2]) << 16)
        | (UInt32(data[offset + 3]) << 24)
    return bigEndian ? raw.byteSwapped : raw
}

func readU64(_ data: Data, _ offset: Int, bigEndian: Bool = false) -> UInt64 {
    guard offset >= 0, offset + 8 <= data.count else { return 0 }
    var value: UInt64 = 0
    for index in 0..<8 {
        let byte = UInt64(data[offset + index])
        value |= byte << UInt64(8 * index)
    }
    return bigEndian ? value.byteSwapped : value
}

func encodeU32(_ value: UInt32, bigEndian: Bool = false) -> [UInt8] {
    let v = bigEndian ? value.byteSwapped : value
    return [
        UInt8(truncatingIfNeeded: v),
        UInt8(truncatingIfNeeded: v >> 8),
        UInt8(truncatingIfNeeded: v >> 16),
        UInt8(truncatingIfNeeded: v >> 24),
    ]
}

func writeU32(_ data: inout Data, _ value: UInt32, at offset: Int, bigEndian: Bool = false) {
    guard offset >= 0, offset + 4 <= data.count else { return }
    let bytes = encodeU32(value, bigEndian: bigEndian)
    for index in 0..<4 {
        data[offset + index] = bytes[index]
    }
}

func looksLikeMachO(_ data: Data) -> Bool {
    guard data.count >= 4 else { return false }
    let big = readU32(data, 0, bigEndian: true)
    if big == fatMagic || big == fatMagic64 { return true }
    let little = readU32(data, 0)
    return little == machMagic || little == machMagic64
}

struct MachOSlice {
    var index: Int
    var offset: Int
    var size: Int
    var bigEndian: Bool
    var is64: Bool
    var cputype: UInt32
    var cpusubtype: UInt32
    var filetype: UInt32
    var ncmds: UInt32
    var sizeofcmds: UInt32
    var commands: [(cmd: UInt32, range: Range<Int>)]
    var cryptid: UInt32
    var minSectionOffset: Int?

    var headerSize: Int { is64 ? 32 : 28 }
    var lcOffset: Int { offset + headerSize }

    var arch: String {
        switch cputype {
        case 0x0100_000C:
            return (cpusubtype & 0x00FF_FFFF) == 2 ? "arm64e" : "arm64"
        case 0x0100_0007:
            return "x86_64"
        case 12:
            return "arm"
        case 7:
            return "i386"
        default:
            return String(format: "cpu%x", cputype)
        }
    }
}

struct MachOFile {
    private(set) var data: Data
    private(set) var slices: [MachOSlice]

    init(data: Data) throws {
        self.data = data
        self.slices = []
        guard data.count >= 8 else { throw MachOError.invalid("文件太短，不是 Mach-O") }

        let big = readU32(data, 0, bigEndian: true)
        if big == fatMagic || big == fatMagic64 {
            try parseFat(is64: big == fatMagic64)
        } else {
            let magic = readU32(data, 0)
            guard magic == machMagic64 || magic == machMagic else {
                throw MachOError.invalid("不是 Mach-O / fat binary")
            }
            slices = [try parseSlice(offset: 0, size: data.count, index: 0)]
        }
    }

    var archs: [String] { Array(Set(slices.map { $0.arch })).sorted() }
    var encrypted: Bool { slices.contains { $0.cryptid != 0 } }
    var totalCommands: Int { slices.reduce(0) { $0 + Int($1.ncmds) } }

    func dylibs() -> [String] {
        var result: [String] = []
        for slice in slices {
            for command in slice.commands where dylibLoadCommands.contains(command.cmd) {
                result.append(dylibPath(of: command, slice: slice))
            }
        }
        return result
    }

    func externalDylibs() -> [String] {
        dylibs().filter { !$0.hasPrefix("/usr/lib/") && !$0.hasPrefix("/System/") }
    }

    mutating func removeDylibs(_ paths: Set<String>) throws -> [String] {
        guard !paths.isEmpty else { return [] }
        var removed: [String] = []

        for index in slices.indices {
            let slice = slices[index]
            var kept: [(cmd: UInt32, range: Range<Int>)] = []
            var sliceRemoved = false

            for command in slice.commands {
                if dylibLoadCommands.contains(command.cmd), paths.contains(dylibPath(of: command, slice: slice)) {
                    sliceRemoved = true
                    removed.append(dylibPath(of: command, slice: slice))
                    continue
                }
                kept.append(command)
            }
            guard sliceRemoved else { continue }

            var body = Data()
            for command in kept {
                body.append(data[command.range])
            }
            while body.count % 8 != 0 { body.append(0) }

            guard body.count <= Int(slice.sizeofcmds) else {
                throw MachOError.invalid("改写后的加载命令区反而变大，已中止")
            }
            if let limit = slice.minSectionOffset, slice.headerSize + body.count > limit {
                throw MachOError.invalid("改写后的加载命令会盖住 section 数据，已中止")
            }
            let start = slice.lcOffset
            let oldEnd = start + Int(slice.sizeofcmds)
            guard start >= 0, oldEnd <= data.count else {
                throw MachOError.invalid("加载命令区越界")
            }

            var replacement = body
            if replacement.count < oldEnd - start {
                replacement.append(Data(repeating: 0, count: oldEnd - start - replacement.count))
            }
            data.replaceSubrange(start..<oldEnd, with: replacement)

            writeU32(&data, UInt32(kept.count), at: slice.offset + 16, bigEndian: slice.bigEndian)
            writeU32(&data, UInt32(body.count), at: slice.offset + 20, bigEndian: slice.bigEndian)

            slices[index].commands = kept
            slices[index].ncmds = UInt32(kept.count)
            slices[index].sizeofcmds = UInt32(body.count)
        }
        return removed
    }

    func containsSymbol(_ needle: String) -> Bool {
        let bytes = Array(needle.utf8)
        guard !bytes.isEmpty, bytes.count <= data.count else { return false }
        return data.range(of: Data(bytes)) != nil
    }

    // MARK: - 解析

    private mutating func parseFat(is64: Bool) throws {
        let count = Int(readU32(data, 4, bigEndian: true))
        guard count > 0, count <= 32 else { throw MachOError.invalid("fat 架构数量异常") }
        var position = 8
        for index in 0..<count {
            let archSize = is64 ? 32 : 20
            guard position + archSize <= data.count else { throw MachOError.invalid("fat 头不完整") }
            let offset: UInt64
            let size: UInt64
            if is64 {
                offset = readU64(data, position + 8, bigEndian: true)
                size = readU64(data, position + 16, bigEndian: true)
            } else {
                offset = UInt64(readU32(data, position + 8, bigEndian: true))
                size = UInt64(readU32(data, position + 12, bigEndian: true))
            }
            position += archSize
            guard offset + size <= UInt64(data.count) else { throw MachOError.invalid("fat 切片越界") }
            slices.append(try parseSlice(offset: Int(offset), size: Int(size), index: index))
        }
    }

    private func parseSlice(offset: Int, size: Int, index: Int) throws -> MachOSlice {
        guard offset >= 0, size >= 8, offset + size <= data.count else {
            throw MachOError.invalid("切片范围越界")
        }
        let magic = readU32(data, offset)
        let is64: Bool
        switch magic {
        case machMagic64: is64 = true
        case machMagic: is64 = false
        default: throw MachOError.invalid("未知的 Mach-O 魔数")
        }
        let headerSize = is64 ? 32 : 28
        guard size >= headerSize else { throw MachOError.invalid("Mach-O 头被截断") }

        let cputype = readU32(data, offset + 4)
        let cpusubtype = readU32(data, offset + 8)
        let filetype = readU32(data, offset + 12)
        let ncmds = readU32(data, offset + 16)
        let sizeofcmds = readU32(data, offset + 20)
        guard ncmds < 100_000 else { throw MachOError.invalid("加载命令数量异常") }

        let lcStart = offset + headerSize
        let lcEnd = lcStart + Int(sizeofcmds)
        guard lcEnd <= offset + size, lcEnd <= data.count else {
            throw MachOError.invalid("加载命令区超出切片范围")
        }

        var commands: [(cmd: UInt32, range: Range<Int>)] = []
        var cryptid: UInt32 = 0
        var minSection: Int?
        var position = lcStart

        for _ in 0..<Int(ncmds) {
            guard position + 8 <= lcEnd else { throw MachOError.invalid("加载命令数量与长度不一致") }
            let cmd = readU32(data, position)
            let cmdsize = Int(readU32(data, position + 4))
            guard cmdsize >= 8, position + cmdsize <= lcEnd else {
                throw MachOError.invalid("加载命令 cmdsize 异常")
            }
            let range = position..<(position + cmdsize)
            commands.append((cmd, range))

            if cmd == lcSegment64 || cmd == lcSegment {
                let segment64 = cmd == lcSegment64
                let nsects = Int(readU32(data, position + (segment64 ? 64 : 48)))
                var cursor = position + (segment64 ? 72 : 56)
                let sectionSize = segment64 ? 80 : 68
                for _ in 0..<nsects {
                    guard cursor + sectionSize <= range.upperBound else { break }
                    let fileOffset = segment64 ? readU32(data, cursor + 48) : readU32(data, cursor + 40)
                    let byteSize = segment64 ? readU32(data, cursor + 40) : readU32(data, cursor + 36)
                    if byteSize > 0, fileOffset > 0 {
                        if minSection == nil || Int(fileOffset) < minSection! {
                            minSection = Int(fileOffset)
                        }
                    }
                    cursor += sectionSize
                }
            } else if cmd == lcEncryptionInfo || cmd == lcEncryptionInfo64 {
                cryptid = readU32(data, position + 16)
            }
            position += cmdsize
        }

        return MachOSlice(
            index: index,
            offset: offset,
            size: size,
            bigEndian: false,
            is64: is64,
            cputype: cputype,
            cpusubtype: cpusubtype,
            filetype: filetype,
            ncmds: ncmds,
            sizeofcmds: sizeofcmds,
            commands: commands,
            cryptid: cryptid,
            minSectionOffset: minSection
        )
    }

    private func dylibPath(of command: (cmd: UInt32, range: Range<Int>), slice: MachOSlice) -> String {
        let nameOffset = Int(readU32(data, command.range.lowerBound + 8, bigEndian: slice.bigEndian))
        let start = command.range.lowerBound + nameOffset
        guard start >= command.range.lowerBound, start < command.range.upperBound else { return "" }
        var bytes: [UInt8] = []
        var cursor = start
        while cursor < command.range.upperBound {
            let byte = data[cursor]
            if byte == 0 { break }
            bytes.append(byte)
            cursor += 1
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
