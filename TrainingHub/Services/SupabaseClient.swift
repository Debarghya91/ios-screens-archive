// SupabaseClient.swift
// Payments Training Hub iOS - URLSession-based Supabase client, no third-party
// package. Talks to the Supabase Auth, REST (PostgREST) and Storage
// HTTP endpoints with the headers Supabase expects: apikey plus an
// Authorization Bearer token (anon key for public calls, the user's
// access token once signed in).
// Preferred path: the official Supabase Swift SDK does the same thing
// with less hand-written code. See supabase/README.md. This layer must
// still work standalone, and it does: every feature in the app uses
// only this file, so the SDK is optional, never required.
// When Supabase is not configured, every call throws
// SupabaseError.notConfigured and the caller falls back to guest mode.
// No em dashes in any user-facing text.

import Foundation

// MARK: - Errors

enum SupabaseError: LocalizedError {
    case notConfigured
    case invalidURL
    case http(status: Int, body: String)
    case decoding(underlying: Error)
    case network(underlying: Error)
    case missingAccessToken

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Sign-in is not set up yet. The app keeps working as a guest."
        case .invalidURL:
            return "The server address is not valid."
        case .http(let status, _):
            return "The server returned an error (\(status)). Please try again."
        case .decoding:
            return "The server reply could not be read. Please try again."
        case .network:
            return "Check your connection and try again."
        case .missingAccessToken:
            return "You are not signed in. Sign in and try again."
        }
    }

    /// The message Supabase itself returned, when it sent one
    /// ({"msg": ...}, {"message": ...} or {"error_description": ...}).
    /// Callers use this to build a friendly message; the raw body is
    /// never shown to the user.
    var serverMessage: String? {
        guard case .http(_, let body) = self,
              let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        for key in ["msg", "message", "error_description", "error"] {
            if let value = object[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }
}

// MARK: - Client

/// A thin URLSession wrapper over the Supabase HTTP API.
final class SupabaseClient {
    static let shared = SupabaseClient()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// True when real Supabase values are present in Config.
    var isConfigured: Bool { SupabaseConfig.isConfigured }

    // MARK: - Generic request

    /// Perform one request against a full Supabase URL.
    /// - Parameters:
    ///   - url: the full endpoint URL.
    ///   - method: GET, POST, PATCH or DELETE.
    ///   - body: an encodable body, sent as JSON when present.
    ///   - accessToken: the signed-in user's access token when one
    ///     exists; the anon key is used otherwise.
    ///   - extraHeaders: extra headers, for example Prefer for upserts.
    func request<T: Encodable>(
        url: URL,
        method: String,
        body: T? = nil,
        accessToken: String? = nil,
        extraHeaders: [String: String] = [:]
    ) async throws -> Data {
        guard isConfigured else { throw SupabaseError.notConfigured }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        urlRequest.setValue("Bearer \(accessToken ?? SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in extraHeaders {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        if let body {
            urlRequest.httpBody = try JSONEncoder().encode(body)
        }
        let data: Data
        let response: URLResponse
        (data, response) = try await dataWithRetry(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw SupabaseError.http(status: 0, body: "")
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw SupabaseError.http(status: http.statusCode, body: bodyText)
        }
        return data
    }

    /// Perform a URLSession data task with bounded retry: up to 3
    /// attempts, exponential backoff (0.5s, then 1s). Only transient
    /// failures are retried: transport errors and HTTP 429 / 5xx.
    /// A 4xx response is returned immediately for the caller to
    /// report, never retried.
    private func dataWithRetry(for urlRequest: URLRequest) async throws -> (Data, URLResponse) {
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                let (data, response) = try await session.data(for: urlRequest)
                if let http = response as? HTTPURLResponse,
                   (http.statusCode == 429 || (500..<600).contains(http.statusCode)),
                   attempt < 2 {
                    try? await Task.sleep(nanoseconds: UInt64(500_000_000 * (1 << attempt)))
                    continue
                }
                return (data, response)
            } catch {
                lastError = error
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: UInt64(500_000_000 * (1 << attempt)))
                    continue
                }
                throw SupabaseError.network(underlying: error)
            }
        }
        throw SupabaseError.network(underlying: lastError ?? URLError(.unknown))
    }

    /// A request with no body.
    func request(
        url: URL,
        method: String,
        accessToken: String? = nil,
        extraHeaders: [String: String] = [:]
    ) async throws -> Data {
        let empty: EmptyBody? = nil
        return try await request(url: url, method: method, body: empty, accessToken: accessToken, extraHeaders: extraHeaders)
    }

    private struct EmptyBody: Encodable {}

    // MARK: - REST (PostgREST) helpers

    /// GET rows from a table. Pass the query string, for example
    /// "select=*&user_id=eq.<uuid>".
    func restGet(table: String, query: String, accessToken: String?) async throws -> Data {
        guard let base = SupabaseConfig.restBaseURL,
              let url = URL(string: "\(base)/\(table)?\(query)") else {
            throw SupabaseError.invalidURL
        }
        return try await request(url: url, method: "GET", accessToken: accessToken)
    }

    /// POST rows into a table. Returns the inserted rows when
    /// `returning` is true.
    func restInsert<T: Encodable>(table: String, rows: [T], accessToken: String?, returning: Bool = false) async throws -> Data {
        guard let base = SupabaseConfig.restBaseURL,
              let url = URL(string: "\(base)/\(table)") else {
            throw SupabaseError.invalidURL
        }
        var headers: [String: String] = [:]
        headers["Prefer"] = returning ? "return=representation" : "return=minimal"
        return try await request(url: url, method: "POST", body: rows, accessToken: accessToken, extraHeaders: headers)
    }

    /// Upsert rows into a table, merging on the named conflict columns.
    /// This is what keeps guest-to-account migration from duplicating
    /// records: the same (user_id, lesson_id) row is updated, not added.
    func restUpsert<T: Encodable>(table: String, rows: [T], onConflict: String, accessToken: String?) async throws -> Data {
        guard let base = SupabaseConfig.restBaseURL,
              let url = URL(string: "\(base)/\(table)?on_conflict=\(onConflict)") else {
            throw SupabaseError.invalidURL
        }
        let headers = ["Prefer": "resolution=merge-duplicates,return=minimal"]
        return try await request(url: url, method: "POST", body: rows, accessToken: accessToken, extraHeaders: headers)
    }

    /// PATCH rows in a table matching the query, for example
    /// "id=eq.<uuid>".
    func restUpdate<T: Encodable>(table: String, query: String, body: T, accessToken: String?) async throws -> Data {
        guard let base = SupabaseConfig.restBaseURL,
              let url = URL(string: "\(base)/\(table)?\(query)") else {
            throw SupabaseError.invalidURL
        }
        return try await request(url: url, method: "PATCH", body: body, accessToken: accessToken, extraHeaders: ["Prefer": "return=minimal"])
    }

    /// DELETE rows in a table matching the query.
    func restDelete(table: String, query: String, accessToken: String?) async throws -> Data {
        guard let base = SupabaseConfig.restBaseURL,
              let url = URL(string: "\(base)/\(table)?\(query)") else {
            throw SupabaseError.invalidURL
        }
        return try await request(url: url, method: "DELETE", accessToken: accessToken)
    }

    /// Decode a REST response into an array of rows.
    func decodeRows<T: Decodable>(_ data: Data, as type: T.Type) throws -> [T] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode([T].self, from: data)
        } catch {
            throw SupabaseError.decoding(underlying: error)
        }
    }

    // MARK: - Storage helpers

    /// Upload data to a Storage bucket path, for example
    /// bucket "avatars", path "<user-id>/avatar.jpg". Returns the public
    /// path. The bucket must be private; the app never makes it public.
    func storageUpload(bucket: String, path: String, data: Data, contentType: String, accessToken: String?) async throws -> String {
        guard let base = SupabaseConfig.storageBaseURL,
              let url = URL(string: "\(base)/object/\(bucket)/\(path)") else {
            throw SupabaseError.invalidURL
        }
        guard isConfigured else { throw SupabaseError.notConfigured }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        urlRequest.setValue("Bearer \(accessToken ?? SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("true", forHTTPHeaderField: "x-upsert")
        urlRequest.httpBody = data
        let responseData: Data
        let response: URLResponse
        (responseData, response) = try await dataWithRetry(for: urlRequest)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw SupabaseError.http(status: status, body: String(data: responseData, encoding: .utf8) ?? "")
        }
        return "\(bucket)/\(path)"
    }

    /// Download a file from a Storage bucket path.
    func storageDownload(bucket: String, path: String, accessToken: String?) async throws -> Data {
        guard let base = SupabaseConfig.storageBaseURL,
              let url = URL(string: "\(base)/object/\(bucket)/\(path)") else {
            throw SupabaseError.invalidURL
        }
        return try await request(url: url, method: "GET", accessToken: accessToken)
    }

    /// A signed URL for a file in a private Storage bucket, for
    /// example the user's avatar. The bucket stays private: the URL
    /// is what the app displays, and it stops working when it
    /// expires. The caller stores the storage path (not this URL) in
    /// the profiles row and asks for a fresh signed URL on display.
    func storageSignedURL(bucket: String, path: String, expiresIn seconds: Int = 3600, accessToken: String?) async throws -> URL {
        guard let base = SupabaseConfig.storageBaseURL,
              let url = URL(string: "\(base)/object/sign/\(bucket)/\(path)") else {
            throw SupabaseError.invalidURL
        }
        struct SignBody: Encodable { let expiresIn: Int }
        struct SignReply: Decodable { let signedURL: String }
        let data = try await request(url: url, method: "POST", body: SignBody(expiresIn: seconds), accessToken: accessToken)
        let reply: SignReply
        do {
            reply = try JSONDecoder().decode(SignReply.self, from: data)
        } catch {
            throw SupabaseError.decoding(underlying: error)
        }
        if let absolute = URL(string: reply.signedURL), absolute.scheme != nil {
            return absolute
        }
        guard let origin = URL(string: SupabaseConfig.url),
              let full = URL(string: "/storage/v1\(reply.signedURL)", relativeTo: origin) else {
            throw SupabaseError.invalidURL
        }
        return full.absoluteURL
    }

    // MARK: - Edge functions

    /// Call one Supabase Edge Function by name, for example
    /// "record-purchase" or "delete-account". The function runs with
    /// the service-role key in its own environment; the app only ever
    /// sends the signed-in user's own access token and its own data.
    func invokeFunction<T: Encodable>(name: String, body: T, accessToken: String?) async throws -> Data {
        guard let base = SupabaseConfig.functionsBaseURL,
              let url = URL(string: "\(base)/\(name)") else {
            throw SupabaseError.invalidURL
        }
        return try await request(url: url, method: "POST", body: body, accessToken: accessToken)
    }

    /// Ask the record-purchase edge function to record a verified
    /// StoreKit purchase on the server, so the entitlement syncs
    /// across devices. This is the ONLY way the app writes a
    /// user_purchases row: the table is SELECT-only for the app under
    /// RLS. Returns true when the server confirmed the record.
    /// Callers keep the on-device StoreKit entitlement regardless:
    /// a failed server record never locks the user out here.
    func recordPurchaseViaFunction(
        transactionID: String,
        productID: String,
        userID: String,
        purchasedAt: Date,
        accessToken: String?
    ) async -> Bool {
        struct RecordBody: Encodable {
            let action: String
            let transactionID: String
            let productID: String
            let userID: String
            let store: String
            let purchasedAt: String

            enum CodingKeys: String, CodingKey {
                case action
                case transactionID = "transaction_id"
                case productID = "product_id"
                case userID = "user_id"
                case store
                case purchasedAt = "purchased_at"
            }
        }
        let body = RecordBody(
            action: "record",
            transactionID: transactionID,
            productID: productID,
            userID: userID,
            store: "apple",
            purchasedAt: ISO8601DateFormatter().string(from: purchasedAt)
        )
        do {
            let data = try await invokeFunction(name: "record-purchase", body: body, accessToken: accessToken)
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            return object?["ok"] as? Bool == true
        } catch {
            return false
        }
    }

    /// Ask the record-purchase edge function to mark a purchase
    /// revoked or refunded, for example after a StoreKit refund.
    /// Returns true when the server confirmed it.
    func revokePurchaseViaFunction(
        transactionID: String,
        userID: String,
        status: String,
        accessToken: String?
    ) async -> Bool {
        struct RevokeBody: Encodable {
            let action: String
            let transactionID: String
            let userID: String
            let status: String

            enum CodingKeys: String, CodingKey {
                case action
                case transactionID = "transaction_id"
                case userID = "user_id"
                case status
            }
        }
        let body = RevokeBody(action: "revoke", transactionID: transactionID, userID: userID, status: status)
        do {
            let data = try await invokeFunction(name: "record-purchase", body: body, accessToken: accessToken)
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            return object?["ok"] as? Bool == true
        } catch {
            return false
        }
    }
}
