// Pill.swift — the small button that sits beside the text box you're typing in.

import AppKit
import SwiftUI

/// A panel that floats over every app and space without ever taking the keyboard.
final class FloatingPanel: NSPanel {
    init(size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Takes the click even though Penlight isn't the active app.
final class FirstMouseHost<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class PillModel: ObservableObject {
    enum Look { case idle, busy, done }
    @Published var look: Look = .idle
    @Published var hover = false
}

struct PillView: View {
    @ObservedObject var model: PillModel
    let tap: () -> Void
    @State private var spin = false

    var body: some View {
        ZStack {
            Circle().fill(Brand.gradient)
                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
                .shadow(color: Brand.violet.opacity(0.45), radius: model.hover ? 5 : 3, y: 1)
            switch model.look {
            case .idle:
                Nib().fill(.white, style: FillStyle(eoFill: true))
                    .frame(width: 8, height: 12)
                    .rotationEffect(.degrees(35))
            case .busy:
                Circle().trim(from: 0, to: 0.7)
                    .stroke(.white, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    .frame(width: 11, height: 11)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .onAppear { withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) { spin = true } }
                    .onDisappear { spin = false }
            case .done:
                Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
            }
        }
        .frame(width: 22, height: 22)
        .scaleEffect(model.hover ? 1.12 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: model.hover)
        .frame(width: 30, height: 30)
        .contentShape(Circle())
        .onHover { model.hover = $0 }
        .onTapGesture(perform: tap)
        .help("Write with \(App.name)  \(Hotkey.label)")
        .accessibilityLabel("Write with \(App.name)")
        .accessibilityAddTraits(.isButton)
    }
}

final class Pill {
    static let shared = Pill()
    var onTap: ((Target) -> Void)?
    let model = PillModel()
    private let size = NSSize(width: 30, height: 30)
    private lazy var panel: FloatingPanel = {
        let p = FloatingPanel(size: size)
        p.contentView = FirstMouseHost(rootView: PillView(model: model) { [weak self] in
            if let t = self?.target { self?.onTap?(t) }
        })
        return p
    }()
    private(set) var target: Target?
    private var doneUntil = Date.distantPast

    /// Shows the button beside `t`, or hides it when nil.
    func show(_ t: Target?) {
        target = t
        guard let t else {
            // Keep the ✓ a moment after writing even though the box lost focus.
            if Date() < doneUntil { return }
            panel.orderOut(nil); return
        }
        panel.setFrameOrigin(place(for: AX.cocoa(t.frame)))
        if !panel.isVisible { panel.alphaValue = 0; panel.orderFrontRegardless(); panel.animator().alphaValue = 1 }
    }

    /// Just outside the box's right edge, level with its last line. Inside when there's no room.
    private func place(for f: CGRect) -> NSPoint {
        let vis = AX.screen(for: f)?.visibleFrame ?? f
        let lineY = f.minY + min(f.height, 34) / 2 - size.height / 2
        var p = NSPoint(x: f.maxX + 2, y: lineY)
        if p.x + size.width > vis.maxX || f.width > vis.width * 0.8 {
            p = NSPoint(x: f.maxX - size.width - 2, y: f.minY + 2)
        }
        p.x = min(max(p.x, vis.minX), vis.maxX - size.width)
        p.y = min(max(p.y, vis.minY), vis.maxY - size.height)
        return p
    }

    func busy(_ on: Bool) { model.look = on ? .busy : .idle }

    func flashDone() {
        model.look = .done
        doneUntil = Date().addingTimeInterval(1.4)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            guard let self else { return }
            if self.model.look == .done { self.model.look = .idle }
            if self.target == nil { self.panel.orderOut(nil) }
        }
    }

    func hide() { target = nil; panel.orderOut(nil) }
}
