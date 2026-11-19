import SwiftUI

/// Guided setup for the Shortcut that passes Apple Health steps (incl. Apple Watch) to PokéWalk.
/// One Shortcut does the work; a few automations run it.
struct StepSyncSetupView: View {
    @State private var done: Set<Int> = Self.loadDone()
    @State private var lastSync = ShortcutSteps.lastSync
    @State private var copied: String?
    private let tick = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private struct Step: Identifiable {
        let id: Int
        let title: String
        let lines: [String]
        var copy: String? = nil
        var open: String? = nil
    }

    private let steps: [Step] = [
        Step(id: 1, title: "Make a new Shortcut",
             lines: ["Tap Open Shortcuts below — a blank Shortcut opens.",
                     "Tap the name at the top › Rename › paste the name."],
             copy: "PokéWalk Step Sync", open: "shortcuts://create-shortcut"),
        Step(id: 2, title: "Add “Find Health Samples”",
             lines: ["Search for Find Health Samples and add it.",
                     "Tap Type › Steps.",
                     "Tap Add Filter › Start Date › is today."]),
        Step(id: 3, title: "Add “Calculate Statistics”",
             lines: ["Search for Calculate Statistics and add it.",
                     "Set it to Sum. It should read “Sum of Health Samples”."]),
        Step(id: 4, title: "Add “Sync Steps to PokéWalk”",
             lines: ["Search for PokéWalk and add Sync Steps to PokéWalk.",
                     "Tap Steps today › choose Statistics Result (the Sum).",
                     "Tap Done. Run it once with ▶︎ — it should say “PokéWalk synced … steps”.",
                     "If asked, tap Allow for Health access."]),
        Step(id: 5, title: "Run it whenever you open PokéWalk",
             lines: ["Automation tab › + › App.",
                     "Choose PokéWalk, tick Is Opened, choose Run Immediately.",
                     "Next › pick your PokéWalk Step Sync Shortcut."],
             open: "shortcuts://"),
        Step(id: 6, title: "Optional: keep it synced while you're out",
             lines: ["Automation › + › Time of Day — make a few (e.g. 9:00, 13:00, 17:00, 21:00).",
                     "Each one: Daily, Run Immediately, then pick PokéWalk Step Sync.",
                     "Other good triggers: When Charger Connects, or when you close an app you use a lot (Music, Maps)."]),
    ]

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: lastSync == nil ? "hourglass" : "checkmark.circle.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(lastSync == nil ? Theme.inkSoft : Theme.teal)
                        .contentTransition(.symbolEffect(.replace))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lastSync == nil ? "Waiting for the first sync…" : "Sync is working")
                            .font(.rounded(16, .heavy))
                        Text(lastSync.map {
                            "\(ShortcutSteps.steps(for: ShortcutSteps.dayKey(Calendar.current.startOfDay(for: .now))).formatted()) steps today · \($0.formatted(.relative(presentation: .named)))"
                        } ?? "Finish step 4 and run the Shortcut — this turns green.")
                        .font(.rounded(12)).foregroundStyle(Theme.inkSoft)
                    }
                }
                .glassRow()
            } footer: {
                Text("Your sideloading tool can't give PokéWalk Apple Health access, but Shortcuts can read Health and hand the total over. Steps arrive in a jump each time it runs.")
            }

            ForEach(steps) { step in
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            withAnimation(.snappy) { if done.contains(step.id) { done.remove(step.id) } else { done.insert(step.id) } }
                            Self.saveDone(done)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: done.contains(step.id) ? "checkmark.circle.fill" : "\(step.id).circle")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(done.contains(step.id) ? Theme.teal : .white)
                                Text(step.title).font(.rounded(16, .heavy))
                                    .strikethrough(done.contains(step.id), color: .white.opacity(0.4))
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        ForEach(step.lines, id: \.self) { line in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•").foregroundStyle(Theme.teal)
                                Text(line).font(.rounded(14)).foregroundStyle(.white.opacity(0.85))
                            }
                        }

                        HStack(spacing: 10) {
                            if let copy = step.copy {
                                Button {
                                    UIPasteboard.general.string = copy
                                    copied = copy
                                } label: {
                                    Label(copied == copy ? "Copied" : "Copy name", systemImage: copied == copy ? "checkmark" : "doc.on.doc")
                                        .font(.rounded(14, .heavy)).padding(.horizontal, 14).frame(height: 36)
                                        .background(.white.opacity(0.12), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                            if let open = step.open {
                                Button {
                                    if let u = URL(string: open) { UIApplication.shared.open(u) }
                                } label: {
                                    Label("Open Shortcuts", systemImage: "arrow.up.forward.app")
                                        .font(.rounded(14, .heavy)).foregroundStyle(.white)
                                        .padding(.horizontal, 14).frame(height: 36)
                                        .background(Theme.teal.opacity(0.75), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 2)
                    }
                    .glassRow()
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Want distance too?").font(.rounded(15, .heavy))
                    Text("In the same Shortcut, add another Find Health Samples (Type: Walking + Running Distance, Start Date is today, Unit: m), then Calculate Statistics › Sum, and put that into Sync Steps' Distance.")
                        .font(.rounded(13)).foregroundStyle(Theme.inkSoft)
                }
                .glassRow()
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Step sync setup")
        .glassScreen()
        .onReceive(tick) { _ in
            let now = ShortcutSteps.lastSync
            if now != lastSync { withAnimation(.snappy) { lastSync = now } }
        }
    }

    private static func loadDone() -> Set<Int> {
        Set((UserDefaults.standard.array(forKey: "stepSyncSetupDone") as? [Int]) ?? [])
    }
    private static func saveDone(_ s: Set<Int>) {
        UserDefaults.standard.set(Array(s), forKey: "stepSyncSetupDone")
    }
}
