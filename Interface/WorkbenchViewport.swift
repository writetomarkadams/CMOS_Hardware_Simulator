import AppKit
import SwiftUI

var workbenchShiftPressed: Bool {
    (NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags).contains(.shift)
}

/// The canvas and all of its gestures use world coordinates beneath this transform.
struct WorkbenchViewport {
    private(set) var scale: CGFloat = 1
    private(set) var origin: CGPoint = .zero

    func worldPoint(at point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - origin.x) / scale, y: (point.y - origin.y) / scale)
    }

    func screenPoint(at world: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + world.x * scale, y: origin.y + world.y * scale)
    }

    mutating func zoom(to requested: CGFloat, around point: CGPoint) {
        let clamped = min(4, max(0.25, requested))
        guard scale != clamped else { return }
        let anchor = worldPoint(at: point)
        scale = clamped
        origin = CGPoint(x: point.x - anchor.x * scale, y: point.y - anchor.y * scale)
    }

    mutating func pan(x: CGFloat, y: CGFloat) {
        origin.x += x
        origin.y += y
    }

    mutating func fit(_ bounds: CGRect, in size: CGSize) {
        let inset: CGFloat = 28
        guard size.width > inset * 2, size.height > inset * 2 else { return }
        let requested = min((size.width - inset * 2) / max(1, bounds.width),
                            (size.height - inset * 2) / max(1, bounds.height))
        scale = min(4, max(0.25, requested))
        origin = CGPoint(x: size.width / 2 - bounds.midX * scale,
                         y: size.height / 2 - bounds.midY * scale)
    }

    mutating func reveal(top: CGFloat) {
        origin = CGPoint(x: 0, y: -top * scale)
    }
}

/// A passive view that intercepts navigation events only inside the workbench viewport.
struct WorkbenchNavigation: NSViewRepresentable {
    let pan: (CGFloat, CGFloat) -> Void
    let zoom: (CGFloat, CGPoint) -> Void
    let editShortcut: (String) -> Bool

    func makeNSView(context: Context) -> EventView { EventView() }

    func updateNSView(_ view: EventView, context: Context) {
        view.pan = pan
        view.zoom = zoom
        view.editShortcut = editShortcut
    }

    static func dismantleNSView(_ view: EventView, coordinator: ()) {
        view.stopMonitoring()
    }

    final class EventView: NSView {
        var pan: ((CGFloat, CGFloat) -> Void)?
        var zoom: ((CGFloat, CGPoint) -> Void)?
        var editShortcut: ((String) -> Bool)?
        private var monitor: Any?
        private var spaceDown = false
        private var panning = false
        private var pinchAnchor: CGPoint?

        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [
                .scrollWheel, .magnify, .keyDown, .keyUp, .leftMouseDown, .leftMouseDragged, .leftMouseUp
            ]) { [weak self] event in
                guard let self else { return event }
                return self.handle(event)
            }
        }

        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            spaceDown = false
            panning = false
            pinchAnchor = nil
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            if event.type == .keyUp, event.keyCode == 49, spaceDown {
                spaceDown = false
                return nil
            }
            guard let window, event.window === window, window.attachedSheet == nil else { return event }
            if panning {
                if event.type == .leftMouseDragged {
                    pan?(event.deltaX, event.deltaY)
                    return nil
                }
                if event.type == .leftMouseUp {
                    panning = false
                    return nil
                }
            }
            if event.type == .keyDown, !(window.firstResponder is NSTextView) {
                let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
                if modifiers == .command,
                   let key = event.charactersIgnoringModifiers?.lowercased(), ["c", "v", "d"].contains(key),
                   !event.isARepeat, editShortcut?(key) == true { return nil }
                if modifiers.isEmpty, [51, 117].contains(event.keyCode),
                   !event.isARepeat, editShortcut?("delete") == true { return nil }
            }
            let location = event.type == .keyDown ? window.mouseLocationOutsideOfEventStream : event.locationInWindow
            let point = convert(location, from: nil)
            guard bounds.contains(point) else { return event }
            switch event.type {
            case .scrollWheel:
                if event.modifierFlags.contains(.command) {
                    zoom?(exp(event.scrollingDeltaY * 0.015), point)
                } else {
                    let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
                    pan?(event.scrollingDeltaX * multiplier, event.scrollingDeltaY * multiplier)
                }
                return nil
            case .magnify:
                if event.phase == .began || pinchAnchor == nil { pinchAnchor = point }
                zoom?(1 + event.magnification, pinchAnchor ?? point)
                if event.phase == .ended || event.phase == .cancelled { pinchAnchor = nil }
                return nil
            case .keyDown where event.keyCode == 49:
                guard !(window.firstResponder is NSTextView),
                      event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
                else { return event }
                spaceDown = true
                return nil
            case .leftMouseDown where spaceDown:
                panning = true
                return nil
            default:
                return event
            }
        }
    }
}
