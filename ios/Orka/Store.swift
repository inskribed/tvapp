import Foundation
import Security
import OrkaCore

/// Playlist logins (which include a password) go in the Keychain; everything else in UserDefaults.
enum Keychain {
    private static func base(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.inskribed.orka",
            kSecAttrAccount as String: key,
        ]
    }

    static func set(_ data: Data, key: String) {
        SecItemDelete(base(key) as CFDictionary)
        var query = base(key)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    static func get(key: String) -> Data? {
        var query = base(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }
}

final class Store {
    private let defaults = UserDefaults.standard

    func playlists() -> [Playlist] {
        guard let data = Keychain.get(key: "playlists"),
              let list = try? JSONDecoder().decode([Playlist].self, from: data) else { return [] }
        return list
    }

    func savePlaylists(_ list: [Playlist]) {
        if let data = try? JSONEncoder().encode(list) { Keychain.set(data, key: "playlists") }
    }

    var activeID: String? {
        get { defaults.string(forKey: "active_playlist") }
        set { defaults.set(newValue, forKey: "active_playlist") }
    }

    func load<T: Decodable>(_ key: String, as type: T.Type = T.self) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    var showScores: Bool {
        get { defaults.object(forKey: "show_scores") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "show_scores") }
    }

    var accentName: String? {
        get { defaults.string(forKey: "accent_name") }
        set { defaults.set(newValue, forKey: "accent_name") }
    }
}
