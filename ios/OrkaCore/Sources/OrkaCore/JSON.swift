import Foundation

extension String {
    /// Trimmed text, or nil if it's empty or the literal "null".
    var trimmedOrNil: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return (t.isEmpty || t == "null") ? nil : t
    }
}

/// Providers send the same field as text or as a number. This accepts either and never fails.
struct FlexString: Decodable {
    let value: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { value = nil; return }
        if let s = try? c.decode(String.self) { value = s.trimmedOrNil; return }
        if let i = try? c.decode(Int.self) { value = String(i); return }
        if let d = try? c.decode(Double.self) {
            value = d == d.rounded() ? String(Int(d)) : String(d)
            return
        }
        if let b = try? c.decode(Bool.self) { value = b ? "1" : "0"; return }
        value = nil
    }
}

/// Decodes one array element, turning a bad element into nil instead of failing the whole array.
struct Lossy<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

extension Dictionary where Key == String, Value == Any {
    /// Reads a field as trimmed text, whether it was sent as text or a number.
    func str(_ key: String) -> String? {
        guard let v = self[key] else { return nil }
        if v is NSNull { return nil }
        if let s = v as? String { return s.trimmedOrNil }
        if let n = v as? NSNumber { return n.stringValue }
        return nil
    }
}
