import SwiftUI

// MARK: - Liquid Glass look, used by every screen
// iOS 26+ uses Apple's real Liquid Glass (.glassEffect); older iOS falls back to frosted materials.

/// Deep teal-to-night gradient behind every screen (matches the dark map).
struct AppBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x123C3F), Color(hex: 0x0C1F2B), Color(hex: 0x0A1420)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Theme.teal.opacity(0.35), .clear], center: .topLeading, startRadius: 10, endRadius: 420)
            RadialGradient(colors: [Color(hex: 0x3D5BE0).opacity(0.22), .clear], center: .bottomTrailing, startRadius: 10, endRadius: 460)
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Full-screen background + dark appearance + hidden list/form backgrounds.
    /// `transparent`: no background of its own, for sheets that float over the blurred map.
    func glassScreen(transparent: Bool = false) -> some View {
        modifier(GlassScreen(transparent: transparent))
    }

    @ViewBuilder fileprivate func glassScreenBody(transparent: Bool) -> some View {
        if transparent {
            self.scrollContentBackground(.hidden)
                .containerBackground(.clear, for: .navigation)   // NavigationStack otherwise paints solid black
                .background(Color.clear)
                .foregroundStyle(.white)
                .toolbarBackground(.hidden, for: .navigationBar)
        } else {
            self.scrollContentBackground(.hidden)
                .background(AppBackground())
                .foregroundStyle(.white)
                .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    /// Marks content shown in a panel over the blurred map, so every screen pushed inside it stays see-through.
    func overMap() -> some View { environment(\.overMap, true) }

    /// Sheets over the map: see-through, so the blurred map shows behind like the trainer card.
    func blurredMapSheet() -> some View {
        self.presentationBackground { Color.black.opacity(0.3) }
            .presentationCornerRadius(32)
    }

    @ViewBuilder func glassCard(_ radius: CGFloat = 20, tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(tint.map { .regular.tint($0.opacity(0.35)) } ?? .regular,
                             in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            self.background((tint ?? .white).opacity(tint == nil ? 0.08 : 0.25), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(.white.opacity(0.14), lineWidth: 1))
        }
    }

    @ViewBuilder func glassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            let base: Glass = tint.map { .regular.tint($0.opacity(0.55)) } ?? .regular
            self.glassEffect(interactive ? base.interactive() : base, in: Capsule())
        } else {
            self.background((tint ?? .white).opacity(tint == nil ? 0.1 : 0.45), in: Capsule())
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 1))
        }
    }

    @ViewBuilder func glassCircle(tint: Color? = nil, interactive: Bool = true) -> some View {
        if #available(iOS 26.0, *) {
            let base: Glass = tint.map { .regular.tint($0.opacity(0.6)) } ?? .regular
            self.glassEffect(interactive ? base.interactive() : base, in: Circle())
        } else {
            self.background((tint ?? .white).opacity(tint == nil ? 0.1 : 0.5), in: Circle())
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
        }
    }

    /// Standard list row look inside glass lists/forms.
    func glassRow() -> some View {
        self.listRowBackground(Color.white.opacity(0.07))
    }

    /// Old name kept for call sites: a padded glass card.
    func cardStyle() -> some View {
        self.padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(20)
    }
}

/// Prominent glass button (teal tinted), e.g. "OK", "Start walking".
struct GlassButton: View {
    let title: String
    var symbol: String? = nil
    var tint: Color = Theme.teal
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let symbol { Label(title, systemImage: symbol) } else { Text(title) }
            }
            .font(.rounded(17, .black))
            .frame(maxWidth: .infinity).frame(height: 52)
            .foregroundStyle(.white)
            .contentShape(Capsule())
            .glassCapsule(tint: tint, interactive: true)
        }
        .buttonStyle(.plain)
    }
}

/// A Poké Ball outline, used for the main menu button.
struct BallOutline: View {
    var lineWidth: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                Circle().stroke(lineWidth: lineWidth)
                Path { p in
                    p.move(to: CGPoint(x: 0, y: s / 2)); p.addLine(to: CGPoint(x: s * 0.36, y: s / 2))
                    p.move(to: CGPoint(x: s * 0.64, y: s / 2)); p.addLine(to: CGPoint(x: s, y: s / 2))
                }
                .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                Circle().stroke(lineWidth: lineWidth).frame(width: s * 0.28, height: s * 0.28)
            }
            .frame(width: s, height: s)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}


private struct OverMapKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var overMap: Bool {
        get { self[OverMapKey.self] }
        set { self[OverMapKey.self] = newValue }
    }
}

private struct GlassScreen: ViewModifier {
    let transparent: Bool
    @Environment(\.overMap) private var overMap
    func body(content: Content) -> some View {
        content.glassScreenBody(transparent: transparent || overMap)
    }
}
