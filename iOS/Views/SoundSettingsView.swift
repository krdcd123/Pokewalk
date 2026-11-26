import SwiftUI
import UniformTypeIdentifiers

/// Turn sounds/music on or off and use your own audio files (mp3, m4a, wav…) for any of them.
struct SoundSettingsView: View {
    @ObservedObject private var sound = SoundKit.shared
    @ObservedObject private var other = ExternalMusic.shared
    @State private var importing = false
    @State private var slot = ""

    var body: some View {
        List {
            Section {
                Toggle("Sound effects", isOn: $sound.effectsOn).glassRow()
                Toggle("Battle, catch & evolution music", isOn: $sound.battleMusicOn).glassRow()
                Toggle("Route music on the map", isOn: $sound.routeMusicOn).glassRow()
            } footer: {
                Text("Sounds follow your silent switch. Route music pauses itself if you're already playing your own music or a podcast.")
            }

            Section {
                HStack {
                    Image(systemName: "music.note").foregroundStyle(.pink).frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple Music").font(.rounded(15, .heavy))
                        Text(other.appleMusicAllowed ? "Shown on the map" : "Allow PokéWalk to see the Music app's song")
                            .font(.rounded(12)).foregroundStyle(Theme.inkSoft)
                    }
                    Spacer()
                    if !other.appleMusicAllowed {
                        Button("Allow") { Task { await other.requestAppleMusic() } }.buttonStyle(.borderless)
                    }
                }
                .glassRow()
                HStack {
                    Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(Color(hex: 0x1DB954)).frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Spotify").font(.rounded(15, .heavy))
                        Text(other.spotifyConnected ? "Connected — shown on the map" : "Not connected")
                            .font(.rounded(12)).foregroundStyle(Theme.inkSoft)
                    }
                    Spacer()
                    if other.spotifyConnected {
                        Button("Disconnect") { other.disconnectSpotify() }.buttonStyle(.borderless).tint(.red)
                    } else {
                        Button("Connect") { other.connectSpotify() }.buttonStyle(.borderless)
                    }
                }
                .glassRow()
                if !other.spotifyConnected {
                    TextField("Spotify Client ID", text: $other.spotifyClientID)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(.rounded(14, .semibold).monospaced())
                        .glassRow()
                }
                if let e = other.spotifyError {
                    Text(e).font(.rounded(12, .semibold)).foregroundStyle(.orange).glassRow()
                }
            } header: { Text("Your music on the map") } footer: {
                Text("iOS doesn't let apps see each other's songs, so Spotify needs a one-time setup: at developer.spotify.com › Dashboard, create an app (any name), add the redirect URI \(ExternalMusic.redirectURI), tick Web API, then paste its Client ID here and tap Connect.")
            }

            Section {
                volume("Route music", value: $sound.routeVolume, icon: "map.fill")
                volume("Battle music", value: $sound.battleVolume, icon: "bolt.fill")
                volume("Sound effects", value: $sound.effectsVolume, icon: "speaker.wave.2.fill") { sound.play(.select) }
            } header: { Text("Volume") } footer: {
                Text("Relative to your phone's volume. Music volume changes straight away if it's playing.")
            }

            Section {
                ForEach(SoundKit.Effect.allCases) { e in
                    row(e.title, custom: sound.hasCustom(e), slot: e.rawValue, preview: { sound.play(e) })
                }
            } header: { Text("Sound effects") } footer: {
                Text("Each one has a small built-in sound. Tap Choose to use your own file instead.")
            }

            Section {
                row("Wild battle", custom: sound.battleFile != nil, slot: "battle", preview: nil)
                row("Caught a Pokémon", custom: sound.caughtMusicFile != nil, slot: "caughtMusic", preview: nil)
                row("Evolution", custom: sound.evolutionMusicFile != nil, slot: "evolutionMusic", preview: nil)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Route music").font(.rounded(15, .heavy))
                        Text(sound.routeFiles.isEmpty ? "None added" : "\(sound.routeFiles.count) track\(sound.routeFiles.count == 1 ? "" : "s"), shuffled")
                            .font(.rounded(12)).foregroundStyle(Theme.inkSoft)
                    }
                    Spacer()
                    if !sound.routeFiles.isEmpty {
                        Button("Clear") { sound.removeCustom(slot: "route") }.buttonStyle(.borderless).tint(.red)
                    }
                    Button("Add…") { slot = "route"; importing = true }.buttonStyle(.borderless)
                }
                .glassRow()
            } header: { Text("Music") } footer: {
                Text("No music is built in — add your own audio files. Battle music loops during wild encounters; route tracks shuffle on the map. You can add several route tracks at once.")
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Sounds & music")
        .glassScreen()
        .id(sound.revision)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio], allowsMultipleSelection: slot == "route") { result in
            guard case .success(let urls) = result else { return }
            for u in urls { sound.importFile(u, slot: slot) }
        }
    }

    private func volume(_ title: String, value: Binding<Double>, icon: String, onEnd: (() -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: icon).font(.rounded(15, .heavy))
                Spacer()
                Text("\(Int(value.wrappedValue * 100))%").font(.rounded(13, .heavy)).foregroundStyle(Theme.inkSoft)
                    .monospacedDigit()
            }
            Slider(value: value, in: 0...1) { editing in if !editing { onEnd?() } }
                .tint(Theme.teal)
        }
        .glassRow()
    }

    private func row(_ title: String, custom: Bool, slot s: String, preview: (() -> Void)?) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.rounded(15, .heavy))
                Text(custom ? "Your file" : (preview == nil ? "None" : "Built-in")).font(.rounded(12)).foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            if let preview { Button { preview() } label: { Image(systemName: "play.fill") }.buttonStyle(.borderless) }
            if custom { Button("Reset") { sound.removeCustom(slot: s) }.buttonStyle(.borderless).tint(.red) }
            Button("Choose…") { slot = s; importing = true }.buttonStyle(.borderless)
        }
        .glassRow()
    }
}
