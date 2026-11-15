// AccountScopedStorage.swift
// Payments Training Hub iOS - Account-scoped UserDefaults keys.
//
// Every account or personal value the app keeps in UserDefaults lives
// under a key namespaced to the identity that owns it:
//   pf.account.<namespace>.<baseKey>
// The namespace is the signed-in user's Supabase id, or "guest" when
// nobody is signed in. Guest data lives under "guest"; account data
// lives under the account's user id. A user who signs out and another
// who signs in can never inherit each other's data, because every
// store re-resolves its keys to the current namespace and reloads.
//
// How the current namespace is known: AuthService is the only writer
// of the signed-in identity, and it calls setCurrentNamespace on
// every identity transition (sign-in, session restore, sign-out,
// account deletion, failed refresh). Stores read currentNamespace,
// which is that cached value, or "guest" before any transition.
// Reading AuthService directly from here would pull MainActor
// isolation into every store, including ones that are not
// MainActor-isolated, so the cache is the contract: AuthService
// keeps it in step, and no other file may set it.
//
// Legacy adoption: builds before this change stored the same base
// keys with no namespace. On first load after the change, each store
// adopts its legacy keys into the current namespace (adoptLegacyKey
// and adoptLegacyKeys), copying the value only when the namespaced
// key has none, then removing the legacy key. Removing it matters:
// a legacy key left in place could be adopted again into a different
// account later. Adoption therefore happens exactly once, into
// whichever identity is current at first launch. When that identity
// is the guest, the adopted data is guest data, and the
// guest-to-account migration offer (see AuthService) can move it
// into an account later, never automatically.
//
// Migration: migrateGuestKeys copies guest values into an account
// namespace only for keys the account does not already have. It
// never overwrites. Migration is offered only from "guest" to a
// signed-in account, never account to account, and only once per
// account (AuthService records that the offer was resolved).
// No em dashes in any user-facing text.

import Foundation

enum AccountScopedStorage {
    /// The namespace for signed-out (guest) data.
    static let guestNamespace = "guest"

    /// The namespace AuthService last reported, or nil before any
    /// identity transition, which means the guest namespace.
    private static var cachedNamespace: String?

    /// The namespace for the current identity: the signed-in user's
    /// id, or "guest" when signed out. See the file header for how
    /// AuthService keeps this in step.
    static var currentNamespace: String {
        cachedNamespace ?? guestNamespace
    }

    /// Record the current identity namespace. AuthService only: call
    /// with the signed-in user's id on sign-in and session restore,
    /// and with nil on sign-out, deletion and failed refresh.
    static func setCurrentNamespace(_ namespace: String?) {
        let trimmed = namespace?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        cachedNamespace = trimmed.isEmpty ? nil : trimmed
    }

    /// The UserDefaults key for a base key under a given namespace.
    /// The namespace is sanitised so the key can only contain safe
    /// characters; Supabase user ids (UUIDs) pass through unchanged.
    static func key(_ baseKey: String, namespace: String) -> String {
        "\(prefix(for: namespace))\(baseKey)"
    }

    /// The UserDefaults key for a base key under the current identity.
    static func currentKey(_ baseKey: String) -> String {
        key(baseKey, namespace: currentNamespace)
    }

    /// The key prefix for one namespace, including the trailing dot,
    /// so a scan for it can never match a longer namespace that
    /// merely starts with the same characters.
    static func prefix(for namespace: String) -> String {
        "pf.account.\(sanitisedNamespace(namespace))."
    }

    /// Remove every UserDefaults key belonging to a namespace, by
    /// scanning for its prefix. Used by account deletion.
    static func removeAllKeys(in namespace: String) {
        let defaults = UserDefaults.standard
        let namespacePrefix = prefix(for: namespace)
        let keys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(namespacePrefix) }
        for key in keys {
            defaults.removeObject(forKey: key)
        }
    }

    /// Copy guest-namespace values to an account namespace, only for
    /// keys the account does not already have. Existing account
    /// values are never overwritten. Returns the base keys actually
    /// migrated. A no-op when the target is the guest namespace.
    @discardableResult
    static func migrateGuestKeys(_ baseKeys: [String], to namespace: String) -> [String] {
        guard sanitisedNamespace(namespace) != guestNamespace else { return [] }
        let defaults = UserDefaults.standard
        var migrated: [String] = []
        for baseKey in baseKeys {
            let guestKey = key(baseKey, namespace: guestNamespace)
            let accountKey = key(baseKey, namespace: namespace)
            guard defaults.object(forKey: accountKey) == nil,
                  let value = defaults.object(forKey: guestKey) else { continue }
            defaults.set(value, forKey: accountKey)
            migrated.append(baseKey)
        }
        return migrated
    }

    /// The prefix-family form of migrateGuestKeys: copy every
    /// guest-namespace key whose base key starts with the given
    /// prefix (for example per-lesson audio positions), only where
    /// the account has no value. Returns the base keys migrated.
    @discardableResult
    static func migrateGuestKeys(withPrefix prefix: String, to namespace: String) -> [String] {
        guard sanitisedNamespace(namespace) != guestNamespace else { return [] }
        let defaults = UserDefaults.standard
        let guestPrefix = "\(self.prefix(for: guestNamespace))\(prefix)"
        let baseKeys = defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(guestPrefix) }
            .map { String($0.dropFirst(self.prefix(for: guestNamespace).count)) }
        return migrateGuestKeys(baseKeys, to: namespace)
    }

    /// True when a namespace holds any key whose base key starts
    /// with the given prefix.
    static func hasKeys(in namespace: String, withBasePrefix prefix: String) -> Bool {
        let fullPrefix = "\(self.prefix(for: namespace))\(prefix)"
        return UserDefaults.standard.dictionaryRepresentation().keys.contains { $0.hasPrefix(fullPrefix) }
    }

    /// Adopt one legacy un-namespaced key into the current namespace:
    /// copy its value only when the namespaced key has none, then
    /// remove the legacy key so it can never be adopted twice.
    static func adoptLegacyKey(_ baseKey: String) {
        let defaults = UserDefaults.standard
        let namespacedKey = currentKey(baseKey)
        if defaults.object(forKey: namespacedKey) == nil,
           let value = defaults.object(forKey: baseKey) {
            defaults.set(value, forKey: namespacedKey)
        }
        defaults.removeObject(forKey: baseKey)
    }

    /// Adopt every legacy un-namespaced key whose name starts with
    /// the given prefix into the current namespace, with the same
    /// copy-only-when-absent then remove rule as adoptLegacyKey.
    /// Namespaced keys never match, because they start with
    /// "pf.account." and no legacy prefix does.
    static func adoptLegacyKeys(withPrefix prefix: String) {
        let defaults = UserDefaults.standard
        let legacyKeys = defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(prefix) && !$0.hasPrefix("pf.account.") }
        for legacyKey in legacyKeys {
            adoptLegacyKey(legacyKey)
        }
    }

    private static func sanitisedNamespace(_ namespace: String) -> String {
        let chars = namespace.map { char in
            (char.isLetter || char.isNumber || char == "-" || char == "_") ? char : "-"
        }
        let result = String(chars)
        return result.isEmpty ? guestNamespace : result
    }
}
