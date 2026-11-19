import SwiftUI
import UniformTypeIdentifiers

/// Turn sounds/music on or off and use your own audio files (mp3, m4a, wav…) for any of them.
struct SoundSettingsView: View {
    @ObservedObject private var sound = SoundKit.shared
    @State private var importing = false
    @State private var slot = ""

    var body: some View {
        List {
            Section {
                Toggle("Sound effects", isOn: $sound.effectsOn).glassRow()
                Toggle("Battle music", isOn: $sound.battleMusicOn).glassRow()
                Toggle("Route music on the map", isOn: $sound.routeMusicOn).glassRow()
            } footer: {
                Text("Sounds follow your silent switch. Route music pauses itself if you're already playing your own music or a podcast.")
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
