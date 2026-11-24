import SwiftUI
import AVFoundation

// MARK: - Shared pieces

enum SleepFormat {
    static func hm(_ s: TimeInterval) -> String {
        let m = max(0, Int((s / 60).rounded()))
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }
    static func time(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }
}

extension SleepNight.Stage {
    var color: Color {
        switch self {
        case .awake: return Color(hex: 0xF4A259)
        case .rem: return Color(hex: 0x7FD1F7)
        case .core: return Color(hex: 0x3F8EF0)
        case .deep: return Color(hex: 0x5B4BD8)
        case .asleep: return Color(hex: 0x3FB8AF)
        case .inBed: return .white.opacity(0.2)
        }
    }
    /// Height in the chart: awake at the top, deep at the bottom (like the Health app).
    var row: Int {
        switch self { case .awake: return 0; case .rem: return 1; case .core, .asleep: return 2; case .deep: return 3; case .inBed: return 0 }
    }
}

/// Stage-by-stage timeline of the night.
struct SleepChart: View {
    let night: SleepNight

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let total = max(1, night.wake.timeIntervalSince(night.bedtime))
                let rows: CGFloat = night.hasStages ? 4 : 1
                let rowH = geo.size.height / rows
                ZStack(alignment: .topLeading) {
                    ForEach(Array(night.blocks.enumerated()), id: \.offset) { _, b in
                        let x = CGFloat(b.start.timeIntervalSince(night.bedtime) / total) * geo.size.width
                        let w = max(1.5, CGFloat(b.end.timeIntervalSince(b.start) / total) * geo.size.width)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(b.stage.color)
                            .frame(width: w, height: rowH - 4)
                            .offset(x: x, y: night.hasStages ? CGFloat(b.stage.row) * rowH + 2 : 2)
                    }
                }
            }
            .frame(height: night.hasStages ? 96 : 26)
            HStack {
                Text(SleepFormat.time(night.bedtime)); Spacer(); Text(SleepFormat.time(night.wake))
            }
            .font(.rounded(11, .heavy)).foregroundStyle(Theme.inkSoft)
        }
    }
}

/// Plays one of the night's sleep-talk clips.
@MainActor
final class ClipPlayer: ObservableObject {
    static let shared = ClipPlayer()
    @Published var playing: URL?
    private var player: AVAudioPlayer?

    func toggle(_ url: URL) {
        if playing == url { player?.stop(); playing = nil; return }
        if !SleepRecorder.active { try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers]) }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.volume = 1
        player?.play()
        playing = url
        let d = player?.duration ?? 0
        Task { try? await Task.sleep(for: .seconds(d + 0.2)); if self.playing == url { self.playing = nil } }
    }
}

struct SleepClipsList: View {
    let day: Date
    @ObservedObject private var player = ClipPlayer.shared

    var body: some View {
        let clips = Array(SleepRecorder.clips(for: day).prefix(SleepRecorder.keep))
        if !clips.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Sleep talking", systemImage: "waveform").font(.rounded(14, .heavy))
                ForEach(Array(clips.enumerated()), id: \.element) { i, url in
                    Button { player.toggle(url) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: player.playing == url ? "stop.fill" : "play.fill")
                                .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 34, height: 34).glassCircle(tint: Theme.teal, interactive: false)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Clip \(i + 1)").font(.rounded(14, .heavy))
                                Text(SleepRecorder.time(url).map(SleepFormat.time) ?? "")
                                    .font(.rounded(11)).foregroundStyle(Theme.inkSoft)
                            }
                            Spacer()
                            if player.playing == url {
                                Image(systemName: "waveform").symbolEffect(.variableColor.iterative, options: .repeating)
                                    .foregroundStyle(Theme.teal)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Everything about one night: headline, chart, stages, body stats, comparisons and sleep talking.
struct SleepDetails: View {
    let night: SleepNight
    var usual: (asleep: TimeInterval, bedtimeMinutes: Double)?
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(SleepFormat.hm(night.asleep)).font(.rounded(34, .black))
                    Text("asleep · \(SleepFormat.time(night.bedtime)) – \(SleepFormat.time(night.wake))")
                        .font(.rounded(13, .heavy)).foregroundStyle(Theme.inkSoft)
                }
                Spacer()
                Image(systemName: "moon.zzz.fill").font(.system(size: 30)).foregroundStyle(Color(hex: 0x9AA7FF))
            }

            SleepChart(night: night)

            if night.hasStages {
                HStack(spacing: 8) {
                    stage(.awake, night.awake); stage(.rem, night.rem); stage(.core, night.core); stage(.deep, night.deep)
                }
            }

            if !compact {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    tile("bed.double.fill", SleepFormat.hm(night.inBed), "in bed")
                    tile("percent", "\(Int(night.efficiency * 100))%", "of it asleep")
                    tile("eye.fill", "\(night.awakenings)", night.awakenings == 1 ? "time awake" : "times awake")
                    if let hr = night.avgHeartRate {
                        tile("heart.fill", "\(Int(hr)) bpm", night.minHeartRate.map { "average · lowest \(Int($0))" } ?? "average")
                    }
                    if let r = night.respiratoryRate { tile("lungs.fill", String(format: "%.1f", r), "breaths/min") }
                    if let o = night.bloodOxygen { tile("drop.fill", "\(Int((o * 100).rounded()))%", "blood oxygen") }
                }
            }

            let notes = insights
            if !notes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(notes, id: \.self) { n in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "sparkle").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.teal).padding(.top, 3)
                            Text(n).font(.rounded(13)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            SleepClipsList(day: night.day)

            Text("From \(night.source) sleep tracking in Apple Health")
                .font(.rounded(11)).foregroundStyle(Theme.inkSoft)
        }
    }

    private var insights: [String] {
        var out: [String] = []
        if let u = usual {
            let diff = night.asleep - u.asleep
            if abs(diff) >= 15 * 60 {
                out.append("\(SleepFormat.hm(abs(diff))) \(diff > 0 ? "more" : "less") sleep than your usual \(SleepFormat.hm(u.asleep)).")
            } else {
                out.append("About as much sleep as usual (\(SleepFormat.hm(u.asleep))).")
            }
            let c = Calendar.current.dateComponents([.hour, .minute], from: night.bedtime)
            var m = Double((c.hour ?? 0) * 60 + (c.minute ?? 0)) - 18 * 60
            if m < 0 { m += 24 * 60 }
            let late = Int(m - u.bedtimeMinutes)
            if abs(late) >= 20 { out.append("Bedtime was \(abs(late)) min \(late > 0 ? "later" : "earlier") than usual.") }
        }
        if night.asleep < 6 * 3600 { out.append("Under 6 hours — most adults need 7 to 9.") }
        else if night.asleep >= 7 * 3600 && night.asleep <= 9 * 3600 { out.append("A full night: right in the 7–9 hour range.") }
        if night.hasStages && night.asleep > 0 {
            let deep = Int(night.deep / night.asleep * 100), rem = Int(night.rem / night.asleep * 100)
            out.append("Deep sleep \(deep)% (typical 13–23%) · REM \(rem)% (typical 20–25%).")
        }
        if night.awakenings >= 4 { out.append("A restless night: you woke \(night.awakenings) times.") }
        return out
    }

    private func stage(_ s: SleepNight.Stage, _ t: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Capsule().fill(s.color).frame(height: 5)
            Text(s.title).font(.rounded(11, .heavy)).foregroundStyle(Theme.inkSoft)
            Text(SleepFormat.hm(t)).font(.rounded(14, .black))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tile(_ icon: String, _ value: String, _ label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 15, weight: .bold)).foregroundStyle(Color(hex: 0x9AA7FF)).frame(width: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.rounded(16, .black)).lineLimit(1).minimumScaleFactor(0.7)
                Text(label).font(.rounded(11)).foregroundStyle(Theme.inkSoft).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .glassCard(14)
    }
}

// MARK: - Morning popup

struct SleepPopupCard: View {
    let night: SleepNight
    var close: () -> Void
    var more: () -> Void
    @State private var usual: (asleep: TimeInterval, bedtimeMinutes: Double)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Good morning!").font(.rounded(22, .black))
                Spacer()
                Image(systemName: "sun.horizon.fill").font(.system(size: 24)).foregroundStyle(Theme.orange)
            }
            ScrollView { SleepDetails(night: night, usual: usual, compact: true) }
                .frame(maxHeight: 440)
            HStack(spacing: 10) {
                Button { SoundKit.shared.play(.select); more() } label: {
                    Text("Full night").font(.rounded(16, .heavy)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 46).glassCapsule(interactive: true)
                }
                Button { SoundKit.shared.play(.select); close() } label: {
                    Text("Nice!").font(.rounded(16, .black)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 46).glassCapsule(tint: Theme.teal, interactive: true)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: 380)
        .glassCard(28)
        .task { usual = await SleepService.shared.usual(before: night.day) }
    }
}

// MARK: - Journal page for a day's night

struct SleepSection: View {
    let day: Date
    var showRecorder = false
    @ObservedObject private var recorder = SleepRecorder.shared
    @State private var night: SleepNight?
    @State private var usual: (asleep: TimeInterval, bedtimeMinutes: Double)?
    @State private var loaded = false
    @State private var message: String?
    @State private var autoListen = SleepRecorder.autoListen

    /// Today's page (and, before 3pm, last night's too while it's still being slept/listened to).
    private var isTonight: Bool {
        Calendar.current.isDateInToday(day) || Calendar.current.isDate(day, inSameDayAs: SleepService.nightDay(for: .now))
    }
    private var isFuture: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SLEEP · NIGHT OF \(day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)).uppercased())")
                .font(.rounded(13, .heavy)).foregroundStyle(Theme.inkSoft)
            if let night {
                SleepDetails(night: night, usual: usual).padding(16).glassCard(22)
            } else if loaded {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "moon.stars.fill").font(.system(size: 28)).foregroundStyle(Color(hex: 0x9AA7FF))
                    Text(isFuture ? "Tonight's sleep will show here in the morning." : "No sleep recorded for this night.")
                        .font(.rounded(15, .heavy))
                    Text("PokéWalk works out your sleep from when your iPhone sits still overnight — just leave it down when you go to sleep. Wearing your Apple Watch to bed adds sleep stages and heart rate. (The iPhone only keeps 7 days of motion, so older nights need watch data.)")
                        .font(.rounded(12)).foregroundStyle(Theme.inkSoft)
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading).glassCard(22)
                SleepClipsList(day: day).padding(16).glassCard(22)
            }
            if isTonight || showRecorder { recorderCard }
        }
        .task(id: day) {
            loaded = false
            night = await SleepService.shared.night(for: day)
            usual = await SleepService.shared.usual(before: day)
            loaded = true
        }
    }

    private var recorderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Sleep talking", systemImage: "waveform.badge.mic").font(.rounded(15, .heavy))
            Text(recorder.isRecording
                 ? "Listening since \(recorder.startedAt.map(SleepFormat.time) ?? "now"). It only starts saving once your phone has been still for 15 minutes (you've dropped off), and in the morning it matches the clips to when your watch or iPhone says you were asleep. It stops when you open PokéWalk."
                 : "Start this when you go to bed. PokéWalk listens through the night and keeps the \(SleepRecorder.keep) loudest moments from while you were actually asleep (sleep talking, snoring…). Keep your phone charging. Clips stay on your phone.")
                .font(.rounded(12)).foregroundStyle(Theme.inkSoft)
            if AVAudioApplication.shared.recordPermission != .granted {
                Label("Tap Start once to allow the microphone — after that it starts by itself at night.",
                      systemImage: "exclamationmark.circle.fill")
                    .font(.rounded(12, .heavy)).foregroundStyle(Theme.orange)
            }
            Button {
                if recorder.isRecording { recorder.stop() }
                else { Task { message = await recorder.start() } }
            } label: {
                Label(recorder.isRecording ? "Stop listening" : "Start listening tonight",
                      systemImage: recorder.isRecording ? "stop.circle.fill" : "mic.fill")
                    .font(.rounded(15, .heavy)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .glassCapsule(tint: recorder.isRecording ? Color(hex: 0xE04A3F) : Color(hex: 0x5B4BD8), interactive: true)
            }
            .buttonStyle(.plain)
            if let message { Text(message).font(.rounded(12)).foregroundStyle(Theme.orange) }
            Toggle(isOn: Binding(get: { autoListen }, set: { autoListen = $0; SleepRecorder.autoListen = $0 })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Start by itself at night").font(.rounded(14, .heavy))
                    Text("When you open PokéWalk after \(SleepRecorder.hourText(SleepRecorder.listenFromHour)) with your phone charging (change the time in Settings).")
                        .font(.rounded(11)).foregroundStyle(Theme.inkSoft)
                }
            }
            .tint(Color(hex: 0x5B4BD8))
        }
        .padding(16)
        .glassCard(22)
    }
}

/// Sun / moon switch: day stats or that night's sleep.
struct DayNightToggle: View {
    @Binding var sleep: Bool
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach([false, true], id: \.self) { s in
                Button {
                    SoundKit.shared.play(.select)
                    withAnimation(.smooth(duration: 0.5)) { sleep = s }
                } label: {
                    Image(systemName: s ? "moon.fill" : "sun.max.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(sleep == s ? .white : Theme.inkSoft)
                        .symbolEffect(.bounce, value: sleep == s)
                        .frame(width: 34, height: 30)
                        .background {
                            if sleep == s {
                                Capsule().fill((s ? Color(hex: 0x5B4BD8) : Theme.orange).opacity(0.8))
                                    .matchedGeometryEffect(id: "pill", in: ns)     // the highlight slides across
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .glassCapsule()
    }
}
