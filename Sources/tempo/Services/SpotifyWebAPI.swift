import Foundation
import CryptoKit
import Network
import AppKit

/// Add-to-playlist via the Spotify Web API, OAuth 2.0 PKCE (decision 003).
///
/// Fails silent throughout (Agent Guideline #3): a missing/invalid config,
/// a failed network call, or a malformed response simply leaves the
/// published state unchanged (or empty/false) — never a dialog, never a
/// crash. Nothing here ever logs a token, code, client id, or secret
/// (Agent Guideline #5).
@MainActor
final class SpotifyWebAPI: ObservableObject {
    @Published var isConfigured = false   // config.json with client id exists
    @Published var isAuthed = false       // have a refresh token
    @Published var playlists: [SpotifyPlaylist] = []
    /// Why the last add-to-playlist failed, for the UI to show. `nil` after a
    /// success. Never contains a token — only Spotify's own error message.
    @Published private(set) var lastAddError: String?

    /// The signed-in user's Spotify id, needed to tell an owned playlist from
    /// a merely *followed* one — `/me/playlists` returns both.
    private var currentUserID: String?

    // MARK: Constants

    static let redirectURI = "http://127.0.0.1:8888/callback"
    private static let callbackPort: UInt16 = 8888
    private static let scopes = "playlist-read-private playlist-modify-private playlist-modify-public"
    private static let authorizeURL = "https://accounts.spotify.com/authorize"
    private static let tokenURL = "https://accounts.spotify.com/api/token"
    private static let apiBase = "https://api.spotify.com/v1"

    private static var supportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tempo", isDirectory: true)
    }
    private static var configFile: URL { supportDir.appendingPathComponent("config.json") }
    private static var tokensFile: URL { supportDir.appendingPathComponent("tokens.json") }

    // MARK: State

    private var clientID: String?
    private var tokens: StoredTokens?
    private var pendingVerifier: String?
    private var pendingState: String?
    private var callbackListener: NWListener?

    private struct Config: Codable {
        var spotify_client_id: String
    }

    private struct StoredTokens: Codable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
    }

    private struct TokenResponse: Decodable {
        var access_token: String
        var token_type: String
        var expires_in: Int
        var refresh_token: String?
        var scope: String?
    }

    // MARK: start()

    /// Loads config + any previously stored tokens. Missing/invalid config
    /// leaves `isConfigured == false` and every other entry point below is
    /// inert (Agent Guideline #3 — no dialogs, no crashes).
    func start() {
        guard let data = try? Data(contentsOf: Self.configFile),
              let config = try? JSONDecoder().decode(Config.self, from: data),
              !config.spotify_client_id.isEmpty else {
            isConfigured = false
            return
        }
        clientID = config.spotify_client_id
        isConfigured = true

        if let tokenData = try? Data(contentsOf: Self.tokensFile),
           let stored = try? JSONDecoder().decode(StoredTokens.self, from: tokenData),
           !stored.refreshToken.isEmpty {
            tokens = stored
            isAuthed = true
        }
    }

    // MARK: Client ID configuration (Settings window)

    /// The configured Client ID, for the Settings field to show. Not a secret
    /// (it is public per Spotify's PKCE flow) — unlike the tokens, which are
    /// never exposed.
    var configuredClientID: String { clientID ?? "" }

    /// Writes `config.json` with the given Client ID and reloads config state,
    /// replacing the manual file-editing step the README used to require
    /// (Agent Guideline #8). An empty/whitespace id clears the configuration
    /// instead. Changing the id to a *different* app invalidates any tokens we
    /// hold — they were issued to the old client — so those are dropped too.
    func saveClientID(_ raw: String) {
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return clearConfiguration() }
        guard id != clientID else { return }

        let fm = FileManager.default
        ensureSupportDir()
        guard let data = try? JSONEncoder().encode(Config(spotify_client_id: id)) else { return }
        fm.createFile(atPath: Self.configFile.path, contents: data, attributes: [.posixPermissions: 0o600])

        if clientID != nil { disconnect() }
        clientID = id
        isConfigured = true
    }

    /// Removes `config.json` and any tokens issued under it: back to the
    /// unconfigured state, where every entry point here is inert.
    func clearConfiguration() {
        try? FileManager.default.removeItem(at: Self.configFile)
        disconnect()
        clientID = nil
        isConfigured = false
    }

    /// Forgets the stored refresh/access tokens. The Spotify-side grant is not
    /// revoked (that needs the user's account page); this only drops our copy.
    func disconnect() {
        try? FileManager.default.removeItem(at: Self.tokensFile)
        tokens = nil
        isAuthed = false
        playlists = []
        currentUserID = nil
        lastAddError = nil
    }

    // MARK: connect() — begin PKCE flow

    /// Starts a fresh PKCE authorization flow: generates verifier/challenge
    /// and a random `state`, opens the system browser to Spotify's
    /// authorize endpoint, and stands up a one-shot loopback listener on
    /// 127.0.0.1:8888 to catch the redirect.
    func connect() {
        guard isConfigured, let clientID else { return }

        let verifier = Self.randomCodeVerifier()
        let challenge = Self.codeChallenge(for: verifier)
        let state = Self.randomState()
        pendingVerifier = verifier
        pendingState = state

        var components = URLComponents(string: Self.authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: Self.scopes),
        ]
        guard let url = components.url else { return }

        startCallbackListener { [weak self] code, returnedState in
            Task { @MainActor in
                await self?.finishConnect(code: code, returnedState: returnedState)
            }
        }

        NSWorkspace.shared.open(url)
    }

    private func finishConnect(code: String?, returnedState: String?) async {
        defer {
            pendingVerifier = nil
            pendingState = nil
        }
        guard let code,
              let returnedState, returnedState == pendingState,
              let verifier = pendingVerifier else { return }
        await exchangeCode(code, verifier: verifier)
    }

    // MARK: Loopback listener

    /// Accepts exactly one connection on 127.0.0.1:8888, parses `code` and
    /// `state` off the GET request line, responds with a small static page,
    /// and tears the listener down. Never touches any other port or
    /// interface, and never keeps listening past the single callback.
    private func startCallbackListener(completion: @escaping (String?, String?) -> Void) {
        callbackListener?.cancel()

        let params = NWParameters.tcp
        guard let listener = try? NWListener(using: params, on: NWEndpoint.Port(rawValue: Self.callbackPort)!) else {
            return
        }
        callbackListener = listener

        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .main)
            Self.receiveRequest(on: connection) { code, state in
                completion(code, state)
                connection.cancel()
                Task { @MainActor [weak self] in
                    self?.callbackListener?.cancel()
                    self?.callbackListener = nil
                }
            }
        }
        listener.stateUpdateHandler = { [weak self] newState in
            if case .failed = newState {
                Task { @MainActor [weak self] in
                    self?.callbackListener = nil
                }
            }
        }
        listener.start(queue: .main)
    }

    nonisolated private static func receiveRequest(on connection: NWConnection, completion: @escaping (String?, String?) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, error in
            guard let data, let text = String(data: data, encoding: .utf8) else {
                completion(nil, nil)
                return
            }
            // Request line looks like: "GET /callback?code=...&state=... HTTP/1.1"
            let firstLine = text.split(separator: "\r\n", maxSplits: 1).first.map(String.init) ?? text
            let parts = firstLine.split(separator: " ")
            var code: String?
            var state: String?
            if parts.count >= 2 {
                let path = String(parts[1])
                if let urlComponents = URLComponents(string: "http://127.0.0.1" + path) {
                    code = urlComponents.queryItems?.first(where: { $0.name == "code" })?.value
                    state = urlComponents.queryItems?.first(where: { $0.name == "state" })?.value
                }
            }

            let body = "<html><body><p>You can close this tab and return to Tempo.</p></body></html>"
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
            connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                completion(code, state)
            })
        }
    }

    // MARK: Token exchange / refresh

    private func exchangeCode(_ code: String, verifier: String) async {
        guard let clientID else { return }
        var request = URLRequest(url: URL(string: Self.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = [
            "client_id": clientID,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "code_verifier": verifier,
        ]
        request.httpBody = Self.formEncode(bodyParams)

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let tokenResponse = try? JSONDecoder().decode(TokenResponse.self, from: data),
              let refreshToken = tokenResponse.refresh_token else {
            return
        }

        let stored = StoredTokens(
            accessToken: tokenResponse.access_token,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(tokenResponse.expires_in))
        )
        tokens = stored
        persistTokens(stored)
        isAuthed = true
    }

    /// Refreshes the access token using the stored refresh token. Spotify's
    /// PKCE refresh response includes a new refresh token, which must be
    /// stored (the old one becomes invalid).
    private func refreshIfNeeded() async -> Bool {
        guard let clientID, let current = tokens else { return false }
        if current.expiresAt.timeIntervalSinceNow > 60 {
            return true // still valid with a minute of headroom
        }

        var request = URLRequest(url: URL(string: Self.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = [
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": current.refreshToken,
        ]
        request.httpBody = Self.formEncode(bodyParams)

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let tokenResponse = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            isAuthed = false
            return false
        }

        let newRefreshToken = tokenResponse.refresh_token ?? current.refreshToken
        let stored = StoredTokens(
            accessToken: tokenResponse.access_token,
            refreshToken: newRefreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(tokenResponse.expires_in))
        )
        tokens = stored
        persistTokens(stored)
        return true
    }

    // MARK: Token persistence (0600 file, 0700 dir)

    private func ensureSupportDir() {
        let fm = FileManager.default
        let dir = Self.supportDir
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
    }

    private func persistTokens(_ stored: StoredTokens) {
        let fm = FileManager.default
        ensureSupportDir()
        guard let data = try? JSONEncoder().encode(stored) else { return }
        fm.createFile(atPath: Self.tokensFile.path, contents: data, attributes: [.posixPermissions: 0o600])
    }

    // MARK: loadPlaylists()

    /// GETs the user's playlists, following `next` pagination up to a ~200
    /// item cap. Any failure along the way leaves `playlists` untouched
    /// silently rather than throwing.
    ///
    /// Only playlists the user can actually add to are kept: `/me/playlists`
    /// returns **followed** playlists alongside owned ones, and Spotify answers
    /// 403 for a POST to someone else's non-collaborative playlist. Listing
    /// those was a lying signal (UI Principle #4) — and since the picker
    /// defaults to the first row, the default was very often a playlist that
    /// could never work. Observed on this account: 48 playlists, of which the
    /// first was someone else's.
    func loadPlaylists() async {
        guard isAuthed, await refreshIfNeeded(), let accessToken = tokens?.accessToken else { return }
        if currentUserID == nil { currentUserID = await fetchCurrentUserID(accessToken: accessToken) }
        guard let currentUserID else { return }

        var results: [SpotifyPlaylist] = []
        var next: String? = "\(Self.apiBase)/me/playlists?limit=50"

        while let urlString = next, results.count < 200 {
            guard let url = URL(string: urlString) else { break }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let page = try? JSONDecoder().decode(PlaylistsPage.self, from: data) else {
                break
            }

            results.append(contentsOf: page.items.compactMap { item in
                guard let id = item.id, let name = item.name else { return nil }
                let isOwned = item.owner?.id == currentUserID
                guard isOwned || item.collaborative == true else { return nil }
                return SpotifyPlaylist(id: id, name: name)
            })
            next = page.next
        }

        playlists = Array(results.prefix(200))
    }

    private struct PlaylistsPage: Decodable {
        var items: [PlaylistItem]
        var next: String?
    }
    private struct PlaylistItem: Decodable {
        var id: String?
        var name: String?
        var collaborative: Bool?
        var owner: Owner?

        struct Owner: Decodable { var id: String? }
    }

    private struct CurrentUser: Decodable { var id: String }

    /// One GET /me, cached for the process: the id never changes while the
    /// same account is connected, and it is cleared on disconnect.
    private func fetchCurrentUserID(accessToken: String) async -> String? {
        guard let url = URL(string: "\(Self.apiBase)/me") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let user = try? JSONDecoder().decode(CurrentUser.self, from: data) else { return nil }
        return user.id
    }

    // MARK: add(trackURI:toPlaylist:)

    /// Adds one track. On failure, records *why* in `lastAddError` instead of
    /// only returning false: a bare warning triangle with no reason was
    /// unactionable (Agent Guideline #11), and the reason is usually something
    /// the user can act on — a playlist they don't own, an expired session, a
    /// local file that has no Spotify URI.
    @discardableResult
    func add(trackURI: String, toPlaylist playlistID: String) async -> Bool {
        lastAddError = nil

        guard trackURI.hasPrefix("spotify:track:") || trackURI.hasPrefix("spotify:episode:") else {
            // Local files come back from AppleScript as `spotify:local:…` and
            // cannot be added through the Web API at all.
            lastAddError = "This track isn't in Spotify's catalogue (local file), so it can't be added."
            return false
        }
        guard isAuthed, await refreshIfNeeded(), let accessToken = tokens?.accessToken else {
            lastAddError = "Spotify session expired — reconnect in Settings ▸ Music."
            return false
        }
        guard let url = URL(string: "\(Self.apiBase)/playlists/\(playlistID)/tracks") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let body = try? JSONEncoder().encode(["uris": [trackURI]]) else { return false }
        request.httpBody = body

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else {
            lastAddError = "Couldn't reach Spotify. Check your connection."
            return false
        }
        if http.statusCode == 200 || http.statusCode == 201 { return true }

        lastAddError = Self.addFailureMessage(status: http.statusCode, body: data)
        return false
    }

    /// Turns a failed response into something the user can act on. Spotify's
    /// own `error.message` is included when present; it never carries
    /// credentials.
    private static func addFailureMessage(status: Int, body: Data) -> String {
        struct APIError: Decodable {
            struct Inner: Decodable { var message: String? }
            var error: Inner?
        }
        let detail = (try? JSONDecoder().decode(APIError.self, from: body))?.error?.message

        switch status {
        case 401:
            return "Spotify rejected the session — reconnect in Settings ▸ Music."
        case 403:
            return detail ?? "You can't add to that playlist — it isn't yours and isn't collaborative."
        case 404:
            return "That playlist no longer exists."
        case 429:
            return "Spotify is rate-limiting Tempo. Try again shortly."
        default:
            if let detail { return "Spotify said: \(detail) (HTTP \(status))" }
            return "Spotify refused the request (HTTP \(status))."
        }
    }

    // MARK: PKCE helpers

    private static func randomCodeVerifier() -> String {
        // 43-128 char unreserved-charset string per RFC 7636. 96 random
        // bytes base64url-encoded (no padding) comfortably lands in range.
        var bytes = [UInt8](repeating: 0, count: 96)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URLEncode(Data(bytes))
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URLEncode(Data(digest))
    }

    private static func randomState() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URLEncode(Data(bytes))
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func formEncode(_ params: [String: String]) -> Data {
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&="))
        let pairs = params.map { key, value -> String in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }
        return pairs.joined(separator: "&").data(using: .utf8) ?? Data()
    }
}

struct SpotifyPlaylist: Identifiable, Equatable {
    var id: String
    var name: String
}
