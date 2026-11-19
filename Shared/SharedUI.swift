import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum Theme {
    static let teal = Color(hex: 0x2BA59F)
    static let tealDark = Color(hex: 0x5FD3C9)   // readable teal on dark glass
    // Text colours for the dark Liquid Glass theme.
    static let ink = Color.white
    static let inkSoft = Color.white.opacity(0.68)
    static let ground = Color(hex: 0x0C1F2B)
    static let orange = Color(hex: 0xF2A33A)
    static let route = Color(hex: 0x2F6FEB)
    static let card = Color.white
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
    init(_ type: PokeType) { self.init(hex: type.hex) }
}

extension Font {
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// Small party/box icon from the shared App Group (synchronous, so it's safe in widgets).
struct LocalIcon: View {
    let speciesID: Int

    var body: some View {
        if let image = Self.image(for: speciesID) {
            image.resizable().interpolation(.none).scaledToFit()
        } else {
            Image(systemName: "circle.dashed").resizable().scaledToFit().padding(4).foregroundStyle(.secondary)
        }
    }

    static func image(for speciesID: Int) -> Image? {
        #if canImport(UIKit)
        guard let ui = UIImage(contentsOfFile: SharedStore.iconFile(speciesID).path) else { return nil }
        return Image(uiImage: ui)
        #else
        return nil
        #endif
    }
}

/// Built-in two-tone ball drawing, used when the player hasn't supplied item sprites.
struct BallGlyph: View {
    var kind: BallKind = .poke

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let line = max(1.5, s * 0.06)
            ZStack {
                Circle().fill(Color(hex: 0xF4F7F6))
                Circle().trim(from: 0.5, to: 1).fill(Color(hex: kind.topHex))
                if kind == .great {
                    Capsule().fill(Color(hex: 0xE04A3F)).frame(width: s * 0.22, height: s * 0.3).offset(x: -s * 0.24, y: -s * 0.22)
                    Capsule().fill(Color(hex: 0xE04A3F)).frame(width: s * 0.22, height: s * 0.3).offset(x: s * 0.24, y: -s * 0.22)
                }
                if kind == .master {
                    Circle().fill(Color(hex: 0xE05FA0)).frame(width: s * 0.2).offset(x: -s * 0.24, y: -s * 0.22)
                    Circle().fill(Color(hex: 0xE05FA0)).frame(width: s * 0.2).offset(x: s * 0.24, y: -s * 0.22)
                }
                if kind == .ultra {
                    Rectangle().fill(Color(hex: 0xF2C230)).frame(width: s * 0.16, height: s * 0.38).offset(x: -s * 0.2, y: -s * 0.2)
                    Rectangle().fill(Color(hex: 0xF2C230)).frame(width: s * 0.16, height: s * 0.38).offset(x: s * 0.2, y: -s * 0.2)
                }
                Rectangle().fill(Color(hex: 0x1B2226)).frame(height: line)
                Circle().stroke(Color(hex: 0x1B2226), lineWidth: line)
                Circle().fill(.white).frame(width: s * 0.3, height: s * 0.3)
                Circle().stroke(Color(hex: 0x1B2226), lineWidth: line).frame(width: s * 0.3, height: s * 0.3)
            }
            .clipShape(Circle())
            .frame(width: s, height: s)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct ExpBar: View {
    let progress: Double
    var tint: Color = Theme.teal
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.16))
                Capsule().fill(tint)
                    .frame(width: max(height, geo.size.width * min(max(progress, 0), 1)))
            }
        }
        .frame(height: height)
    }
}

struct TypeChip: View {
    let type: PokeType
    var body: some View {
        Text(type.displayName.uppercased())
            .font(.rounded(11, .heavy))
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(Color(type), in: Capsule())
            .foregroundStyle(.white)
    }
}


/// Distances are shown in miles.
enum Distance {
    static let metersPerMile = 1609.344
    static func miles(_ meters: Double) -> Double { meters / metersPerMile }
    static func text(_ meters: Double, digits: Int = 1) -> String {
        String(format: "%.\(digits)f mi", miles(meters))
    }
}
