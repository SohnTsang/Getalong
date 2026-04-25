import Foundation
import Supabase

/// Centralised configuration for the Supabase client.
///
/// Real values are read from `Secrets.plist` at runtime. The plist is
/// gitignored. See `ios/README.md` for setup.
///
/// IMPORTANT: only the **anon** key may live in the app. The service role
/// key must never ship in any client.
enum SupabaseConfig {
    static let url: URL = {
        guard let raw = Self.value(for: "SUPABASE_URL"),
              let url = URL(string: raw) else {
            preconditionFailure("Missing SUPABASE_URL in Secrets.plist")
        }
        return url
    }()

    static let anonKey: String = {
        guard let key = Self.value(for: "SUPABASE_ANON_KEY"), !key.isEmpty else {
            preconditionFailure("Missing SUPABASE_ANON_KEY in Secrets.plist")
        }
        return key
    }()

    private static func value(for key: String) -> String? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, format: nil
              ) as? [String: Any]
        else { return nil }
        return plist[key] as? String
    }
}

/// Single shared `SupabaseClient`. Services and `SessionManager` go
/// through this. Built on first access.
enum Supa {
    static let client: SupabaseClient = {
        SupabaseClient(
            supabaseURL: SupabaseConfig.url,
            supabaseKey: SupabaseConfig.anonKey
        )
    }()
}
