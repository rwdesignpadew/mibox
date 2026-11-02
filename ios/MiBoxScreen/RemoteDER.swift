// Adapted from Open Source TV Remote, Copyright (c) 2026 Nathan Butler, MIT License.
import Foundation

enum RemoteDER {
    static func tlv(_ tag: UInt8, _ content: [UInt8]) -> [UInt8] { [tag] + length(content.count) + content }
    static func length(_ n: Int) -> [UInt8] {
        if n < 0x80 { return [UInt8(n)] }
        var bytes: [UInt8] = []
        var value = n
        while value > 0 { bytes.insert(UInt8(value & 0xff), at: 0); value >>= 8 }
        return [0x80 | UInt8(bytes.count)] + bytes
    }
    static func sequence(_ items: [[UInt8]]) -> [UInt8] { tlv(0x30, items.flatMap { $0 }) }
    static func set(_ items: [[UInt8]]) -> [UInt8] { tlv(0x31, items.flatMap { $0 }) }
    static func explicit(_ n: UInt8, _ content: [UInt8]) -> [UInt8] { tlv(0xa0 | n, content) }
    static let null: [UInt8] = [0x05, 0x00]
    static func boolean(_ value: Bool) -> [UInt8] { [0x01, 0x01, value ? 0xff : 0x00] }
    static func utf8(_ value: String) -> [UInt8] { tlv(0x0c, Array(value.utf8)) }
    static func octetString(_ bytes: [UInt8]) -> [UInt8] { tlv(0x04, bytes) }
    static func bitString(_ bytes: [UInt8]) -> [UInt8] { tlv(0x03, [0] + bytes) }
    static func integer(_ magnitude: [UInt8]) -> [UInt8] {
        var bytes = Array(magnitude.drop { $0 == 0 })
        if bytes.isEmpty { bytes = [0] }
        if bytes[0] & 0x80 != 0 { bytes.insert(0, at: 0) }
        return tlv(0x02, bytes)
    }
    static func integer(_ number: Int) -> [UInt8] {
        var bytes: [UInt8] = [], value = number
        repeat { bytes.insert(UInt8(value & 0xff), at: 0); value >>= 8 } while value > 0
        return integer(bytes)
    }
    static func oid(_ dotted: String) -> [UInt8] {
        let parts = dotted.split(separator: ".").compactMap { UInt64($0) }
        var result = [UInt8(parts[0] * 40 + parts[1])]
        for part in parts.dropFirst(2) {
            var chunk = [UInt8(part & 0x7f)], value = part >> 7
            while value > 0 { chunk.insert(UInt8(value & 0x7f) | 0x80, at: 0); value >>= 7 }
            result += chunk
        }
        return tlv(0x06, result)
    }
    static func time(_ date: Date) -> [UInt8] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        let year = Calendar(identifier: .gregorian).dateComponents(in: formatter.timeZone, from: date).year ?? 2000
        formatter.dateFormat = year < 2050 ? "yyMMddHHmmss'Z'" : "yyyyMMddHHmmss'Z'"
        return tlv(year < 2050 ? 0x17 : 0x18, Array(formatter.string(from: date).utf8))
    }
}
