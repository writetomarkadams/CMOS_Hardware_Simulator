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

    func canvasFrame(in size: CGSize, extent: CGSize) -> CGRect {
        // Canvas drawing and SwiftUI hit testing both need positive local coordinates,
        // including when the visible world extends left of or above zero.
        let topLeft = worldPoint(at: .zero)
        let bottomRight = worldPoint(at: CGPoint(x: size.width, y: size.height))
        let x = min(0, topLeft.x - 24)
        let y = min(0, topLeft.y - 24)
        return CGRect(x: x, y: y, width: max(extent.width, bottomRight.x) - x,
                      height: max(extent.height, bottomRight.y) - y)
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

enum WorkbenchNavigationStyle: String, CaseIterable {
    static let preferenceKey = "workbenchNavigationStyle"

    case kiCad = "KiCad"
    case macOS = "macOS"

    func scrollMode(x: CGFloat, y: CGFloat, command: Bool) -> WorkbenchScrollMode {
        if command || (self == .kiCad && abs(y) >= abs(x)) { return .zoom }
        return self == .kiCad ? .horizontalPan : .pan
    }
}

enum WorkbenchScrollMode: Equatable {
    case zoom, horizontalPan, pan

    func apply(x: CGFloat, y: CGFloat, precise: Bool, momentum: Bool,
               at point: CGPoint, to viewport: inout WorkbenchViewport) {
        let multiplier: CGFloat = precise ? 1 : 10
        switch self {
        case .zoom:
            if !momentum {
                viewport.zoom(to: viewport.scale * exp(y * multiplier * 0.015), around: point)
            }
        case .horizontalPan:
            viewport.pan(x: x * multiplier, y: 0)
        case .pan:
            viewport.pan(x: x * multiplier, y: y * multiplier)
        }
    }
}

/// A passive view that intercepts navigation events only inside the workbench viewport.
struct WorkbenchNavigation: NSViewRepresentable {
    let style: WorkbenchNavigationStyle
    let pan: (CGFloat, CGFloat) -> Void
    let zoom: (CGFloat, CGPoint) -> Void
    let scroll: (WorkbenchScrollMode, CGFloat, CGFloat, Bool, Bool, CGPoint) -> Void
    let editShortcut: (String) -> Bool

    func makeNSView(context: Context) -> EventView { EventView() }

    func updateNSView(_ view: EventView, context: Context) {
        view.style = style
        view.pan = pan
        view.zoom = zoom
        view.scroll = scroll
        view.editShortcut = editShortcut
    }

    static func dismantleNSView(_ view: EventView, coordinator: ()) {
        view.stopMonitoring()
    }

    final class EventView: NSView {
        var style = WorkbenchNavigationStyle.kiCad {
            didSet { if oldValue != style { scrollMode = nil } }
        }
        var pan: ((CGFloat, CGFloat) -> Void)?
        var zoom: ((CGFloat, CGPoint) -> Void)?
        var scroll: ((WorkbenchScrollMode, CGFloat, CGFloat, Bool, Bool, CGPoint) -> Void)?
        var editShortcut: ((String) -> Bool)?
        private var monitor: Any?
        private var resignObserver: NSObjectProtocol?
        private var spaceDown = false
        private var panButton: Int?
        private var pinchAnchor: CGPoint?
        private var scrollMode: WorkbenchScrollMode?

        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard let window else { return }
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: window, queue: nil
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.resetInput() }
            }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [
                .scrollWheel, .magnify, .keyDown, .keyUp,
                .leftMouseDown, .leftMouseDragged, .leftMouseUp,
                .otherMouseDown, .otherMouseDragged, .otherMouseUp
            ]) { [weak self] event in
                guard let self else { return event }
                return self.handle(event)
            }
        }

        private func resetInput() {
            spaceDown = false
            panButton = nil
            pinchAnchor = nil
            scrollMode = nil
        }

        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
            monitor = nil
            resignObserver = nil
            resetInput()
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            if event.type == .keyUp, event.keyCode == 49, spaceDown {
                spaceDown = false
                return nil
            }
            guard let window, event.window === window, window.attachedSheet == nil else { return event }
            switch event.type {
            case .leftMouseDragged, .otherMouseDragged:
                if panButton == event.buttonNumber {
                    pan?(event.deltaX, event.deltaY)
                    return nil
                }
            case .leftMouseUp, .otherMouseUp:
                if panButton == event.buttonNumber {
                    panButton = nil
                    return nil
                }
            default:
                break
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
            // Finish a claimed pinch even when its event location leaves the canvas.
            if event.type == .magnify, (pinchAnchor != nil || bounds.contains(point)) {
                handlePinch(event, at: point)
                return nil
            }
            if event.type == .scrollWheel, !bounds.contains(point) {
                scrollMode = nil
            }
            guard bounds.contains(point) else { return event }
            switch event.type {
            case .scrollWheel:
                handleScroll(event, at: point)
                return nil
            case .keyDown where event.keyCode == 49:
                guard !(window.firstResponder is NSTextView),
                      event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
                else { return event }
                if !event.isARepeat { spaceDown = true }
                return nil
            case .leftMouseDown where spaceDown:
                if panButton == nil, pinchAnchor == nil { beginPan(button: 0) }
                return nil
            case .leftMouseDown where panButton != nil || pinchAnchor != nil:
                return nil
            case .otherMouseDown where event.buttonNumber == 2:
                if panButton == nil, pinchAnchor == nil, NSEvent.pressedMouseButtons & 1 == 0 {
                    beginPan(button: 2)
                }
                return nil
            default:
                return event
            }
        }

        private func beginPan(button: Int) {
            panButton = button
            scrollMode = nil
        }

        private func handlePinch(_ event: NSEvent, at point: CGPoint) {
            if event.phase == .ended || event.phase == .cancelled {
                pinchAnchor = nil
                return
            }
            guard panButton == nil, NSEvent.pressedMouseButtons & 1 == 0 else { return }
            scrollMode = nil
            if event.phase == .began || pinchAnchor == nil { pinchAnchor = point }
            zoom?(1 + event.magnification, pinchAnchor ?? point)
            if event.phase.isEmpty { pinchAnchor = nil }
        }

        private func handleScroll(_ event: NSEvent, at point: CGPoint) {
            guard panButton == nil, pinchAnchor == nil, NSEvent.pressedMouseButtons & 1 == 0 else {
                scrollMode = nil
                return
            }
            let x = event.scrollingDeltaX
            let y = event.scrollingDeltaY
            if !event.momentumPhase.isEmpty {
                if let scrollMode {
                    scroll?(scrollMode, x, y, event.hasPreciseScrollingDeltas, true, point)
                }
                if event.momentumPhase == .ended || event.momentumPhase == .cancelled { scrollMode = nil }
                return
            }
            if event.phase == .began || event.phase == .mayBegin || event.phase.isEmpty {
                scrollMode = nil
            }
            if event.phase == .cancelled {
                scrollMode = nil
                return
            }
            guard x != 0 || y != 0 else { return }
            let mode = scrollMode ?? style.scrollMode(x: x, y: y, command: event.modifierFlags.contains(.command))
            if !event.phase.isEmpty { scrollMode = mode }
            scroll?(mode, x, y, event.hasPreciseScrollingDeltas, false, point)
        }
    }
}
