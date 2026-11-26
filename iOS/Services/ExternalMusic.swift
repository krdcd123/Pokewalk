import Foundation
import MediaPlayer
import AuthenticationServices
import CryptoKit
import UIKit

/// What's playing in another app, for the map's music card. iOS doesn't let apps read each other's "Now Playing",
/// so: the Music app is read directly (Apple Music / your library), and Spotify through its Web API once you've
/// connected your account in Settings › Sounds & music.
@MainActor
final class ExternalMusic: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = ExternalMusic()

    struct Track: Equatable { var title: String; var artist: String; var app: String }
    @Published private(set) var track: Track?
    @Published private(set) var spotifyConnected = false
    @Published var spotifyError: String?

    /// Your Spotify app's Client ID (developer.spotify.com › Dashboard › Create app, redirect URI below).
    @Published var spotifyClientID: String {
        didSet { UserDefaults.standard.set(spotifyClientID.trimmingCharacters(in: .whitespaces), forKey: "spotifyClientID") }
    }
    static let redirectURI = "pokewalk://spotify-callback"

    private var timer: Timer?
    private var accessToken: String?
    private var tokenExpiry = Date.distantPast
    private var refreshToken: String? {
        get { UserDefaults.standard.string(forKey: "spotifyRefreshToken") }
        set { UserDefaults.standard.set(newValue, forKey: "spotifyRefreshToken") }
    }

    override init() {
        spotifyClientID = UserDefaults.standard.string(forKey: "spotifyClientID") ?? ""
        super.init()
        spotifyConnected = refreshToken != nil
        NotificationCenter.default.addObserver(forName: .MPMusicPlayerControllerNowPlayingItemDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        NotificationCenter.default.addObserver(forName: .MPMusicPlayerControllerPlaybackStateDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    // MARK: Watching (while the map is on screen)

    func start() {
        guard timer == nil else { return }
        if MPMediaLibrary.authorizationStatus() == .authorized {
            MPMusicPlayerController.systemMusicPlayer.beginGeneratingPlaybackNotifications()
        }
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate(); timer = nil
    }

    func refresh() async {
        // Nothing else playing → nothing to show (and no need to ask Spotify)
        guard AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint else {
            if track != nil { track = nil }
            return
        }
        if let t = appleMusic() { track = t; return }
        if spotifyConnected, let t = await spotify() { track = t; return }
        track = nil
    }

    private func appleMusic() -> Track? {
        guard MPMediaLibrary.authorizationStatus() == .authorized else { return nil }
        let p = MPMusicPlayerController.systemMusicPlayer
        guard p.playbackState == .playing, let item = p.nowPlayingItem, let title = item.title, !title.isEmpty else { return nil }
        return Track(title: title, artist: item.artist ?? "", app: "Music")
    }

    /// Asks for Music access (shows your Apple Music / library song on the map).
    func requestAppleMusic() async {
        let status = await withCheckedContinuation { c in MPMediaLibrary.requestAuthorization { c.resume(returning: $0) } }
        if status == .authorized {
            MPMusicPlayerController.systemMusicPlayer.beginGeneratingPlaybackNotifications()
            await refresh()
        }
        objectWillChange.send()
    }
    var appleMusicAllowed: Bool { MPMediaLibrary.authorizationStatus() == .authorized }

    // MARK: Spotify (Authorization Code with PKCE: no secret stored in the app)

    func connectSpotify() {
        let id = spotifyClientID.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty else { spotifyError = "Paste your Spotify Client ID first."; return }
        let verifier = Self.randomString(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        var c = URLComponents(string: "https://accounts.spotify.com/authorize")!
        c.queryItems = [
            .init(name: "client_id", value: id), .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "scope", value: "user-read-currently-playing user-read-playback-state"),
            .init(name: "code_challenge_method", value: "S256"), .init(name: "code_challenge", value: challenge),
        ]
        let session = ASWebAuthenticationSession(url: c.url!, callbackURLScheme: "pokewalk") { [weak self] url, error in
            Task { @MainActor in
                guard let self else { return }
                guard let url, let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "code" })?.value else {
                    if let error, (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin {
                        self.spotifyError = "Couldn't connect: \(error.localizedDescription)"
                    }
                    return
                }
                await self.exchange(["grant_type": "authorization_code", "code": code,
                                     "redirect_uri": Self.redirectURI, "client_id": id, "code_verifier": verifier])
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        session.start()
    }

    func disconnectSpotify() {
        refreshToken = nil; accessToken = nil; tokenExpiry = .distantPast
        spotifyConnected = false
        Task { await refresh() }
    }

    private func exchange(_ form: [String: String]) async {
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = form.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")" }
            .joined(separator: "&").data(using: .utf8)
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            spotifyError = "Couldn't reach Spotify."
            return
        }
        guard (resp as? HTTPURLResponse)?.statusCode == 200, let token = json["access_token"] as? String else {
            spotifyError = "Spotify said: " + ((json["error_description"] as? String) ?? (json["error"] as? String) ?? "no")
            if form["grant_type"] == "refresh_token" { disconnectSpotify() }
            return
        }
        accessToken = token
        tokenExpiry = Date().addingTimeInterval(Double(json["expires_in"] as? Int ?? 3600) - 60)
        if let r = json["refresh_token"] as? String { refreshToken = r }
        spotifyConnected = true
        spotifyError = nil
        if form["grant_type"] == "authorization_code" { await refresh() }
    }

    private func spotify() async -> Track? {
        if accessToken == nil || Date() >= tokenExpiry {
            guard let r = refreshToken else { return nil }
            await exchange(["grant_type": "refresh_token", "refresh_token": r, "client_id": spotifyClientID])
        }
        guard let token = accessToken else { return nil }
        var req = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/currently-playing")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let code = (resp as? HTTPURLResponse)?.statusCode else { return nil }
        if code == 401 { accessToken = nil; return nil }
        guard code == 200, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["is_playing"] as? Bool == true, let item = json["item"] as? [String: Any],
              let name = item["name"] as? String else { return nil }
        // songs have artists; podcast episodes have a show
        let artists = (item["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String }.joined(separator: ", ")
        let show = (item["show"] as? [String: Any])?["name"] as? String
        return Track(title: name, artist: artists ?? show ?? "", app: "Spotify")
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }

    private static func randomString(_ n: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<n).map { _ in chars.randomElement()! })
    }
}

private extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
