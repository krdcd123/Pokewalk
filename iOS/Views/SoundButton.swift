import SwiftUI

/// Every `Button` in the app is this one (it shadows SwiftUI's): the same button, but tapping it plays the
/// Emerald "select" sound — so the sound only plays for things that can actually be pressed.
struct Button<Label: View>: View {
    private let role: ButtonRole?
    private let action: () -> Void
    private let label: Label

    init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.role = nil; self.action = action; self.label = label()
    }

    init(role: ButtonRole?, action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.role = role; self.action = action; self.label = label()
    }

    var body: some View {
        SwiftUI.Button(role: role) {
            SoundKit.shared.play(.select)
            action()
        } label: {
            label
        }
    }
}

extension Button where Label == Text {
    init(_ titleKey: LocalizedStringKey, action: @escaping () -> Void) {
        self.init(action: action) { Text(titleKey) }
    }
    @_disfavoredOverload
    init<S: StringProtocol>(_ title: S, action: @escaping () -> Void) {
        self.init(action: action) { Text(title) }
    }
    init(_ titleKey: LocalizedStringKey, role: ButtonRole?, action: @escaping () -> Void) {
        self.init(role: role, action: action) { Text(titleKey) }
    }
    @_disfavoredOverload
    init<S: StringProtocol>(_ title: S, role: ButtonRole?, action: @escaping () -> Void) {
        self.init(role: role, action: action) { Text(title) }
    }
}

extension Button where Label == SwiftUI.Label<Text, Image> {
    init(_ titleKey: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) {
        self.init(action: action) { SwiftUI.Label(titleKey, systemImage: systemImage) }
    }
    @_disfavoredOverload
    init<S: StringProtocol>(_ title: S, systemImage: String, action: @escaping () -> Void) {
        self.init(action: action) { SwiftUI.Label(title, systemImage: systemImage) }
    }
    init(_ titleKey: LocalizedStringKey, systemImage: String, role: ButtonRole?, action: @escaping () -> Void) {
        self.init(role: role, action: action) { SwiftUI.Label(titleKey, systemImage: systemImage) }
    }
    @_disfavoredOverload
    init<S: StringProtocol>(_ title: S, systemImage: String, role: ButtonRole?, action: @escaping () -> Void) {
        self.init(role: role, action: action) { SwiftUI.Label(title, systemImage: systemImage) }
    }
}
