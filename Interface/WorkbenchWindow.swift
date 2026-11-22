import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class WorkbenchFileWorkflow {
    enum Decision {
        case save, discard, cancel
    }

    static let shared = WorkbenchFileWorkflow()
    private var isBusy = false
    private(set) var isQuitting = false

    // AppKit modal panels run a nested event loop. Reject reentrant actions
    // while a choice, file panel, or error alert is open.
    @discardableResult
    func perform(_ action: () -> Bool) -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        defer { isBusy = false }
        return action()
    }

    func permitsLeaving(_ bench: Workbench, decide: () -> Decision, save: () -> Bool) -> Bool {
        guard bench.isDirty else { return true }
        switch decide() {
        case .save: return save() && !bench.isDirty
        case .discard: return true
        case .cancel: return false
        }
    }

    func permitsLeaving(_ bench: Workbench) -> Bool {
        permitsLeaving(bench, decide: {
            let alert = NSAlert()
            let name = bench.documentURL?.lastPathComponent ?? "Untitled"
            alert.messageText = "Do you want to save the changes to “\(name)”?"
            alert.informativeText = "Your changes will be lost if you don’t save them."
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
            alert.addButton(withTitle: "Don’t Save").keyEquivalent = "\u{8}"
            switch alert.runModal() {
            case .alertFirstButtonReturn: return .save
            case .alertThirdButtonReturn: return .discard
            default: return .cancel
            }
        }, save: { save(bench) })
    }

    func save(_ bench: Workbench, saveAs: Bool = false) -> Bool {
        var url = saveAs ? nil : bench.documentURL
        if url == nil {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = bench.documentURL?.deletingPathExtension().lastPathComponent ?? "Circuit"
            guard panel.runModal() == .OK else { return false }
            url = panel.url
        }
        guard let url else { return false }
        do {
            try bench.save(to: url)
            return true
        } catch {
            showError(error)
            return false
        }
    }

    func showError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }

    func requestQuit(checks: [() -> Bool]) -> Bool {
        perform {
            guard checks.allSatisfy({ $0() }) else { return false }
            isQuitting = true
            return true
        }
    }
}

@MainActor
final class WorkbenchAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let windows = sender.orderedWindows + sender.windows
        var seen = Set<ObjectIdentifier>()
        let checks: [() -> Bool] = windows.compactMap { window in
            guard seen.insert(ObjectIdentifier(window)).inserted,
                  let delegate = window.delegate as? WorkbenchWindowDelegate else { return nil }
            return {
                if delegate.bench?.isDirty == true { window.makeKeyAndOrderFront(nil) }
                return delegate.permitsLeaving()
            }
        }
        return WorkbenchFileWorkflow.shared.requestQuit(checks: checks) ? .terminateNow : .terminateCancel
    }
}

@MainActor
final class WorkbenchWindowDelegate: NSObject, NSWindowDelegate {
    weak var bench: Workbench?
    weak var window: NSWindow?
    private weak var previousDelegate: (any NSWindowDelegate)?

    func attach(to window: NSWindow?) {
        if self.window?.delegate === self { self.window?.delegate = previousDelegate }
        self.window = window
        previousDelegate = window?.delegate
        window?.delegate = self
    }

    func permitsLeaving() -> Bool {
        guard let bench else { return true }
        return WorkbenchFileWorkflow.shared.permitsLeaving(bench)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let workflow = WorkbenchFileWorkflow.shared
        if workflow.isQuitting { return true }
        return workflow.perform {
            guard previousDelegate?.windowShouldClose?(sender) != false else { return false }
            return permitsLeaving()
        }
    }

    // SwiftUI still receives the window delegate callbacks it installed.
    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || previousDelegate?.responds(to: selector) == true
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        if previousDelegate?.responds(to: selector) == true { return previousDelegate }
        return super.forwardingTarget(for: selector)
    }
}

struct WorkbenchWindowBridge: NSViewRepresentable {
    let bench: Workbench
    let isDirty: Bool

    func makeNSView(context: Context) -> WindowObserver {
        let view = WindowObserver()
        view.delegate.bench = bench
        return view
    }

    func updateNSView(_ view: WindowObserver, context: Context) {
        view.isDirty = isDirty
        view.window?.isDocumentEdited = isDirty
    }

    static func dismantleNSView(_ view: WindowObserver, coordinator: ()) {
        view.delegate.attach(to: nil)
    }

    final class WindowObserver: NSView {
        let delegate = WorkbenchWindowDelegate()
        var isDirty = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            delegate.attach(to: window)
            window?.isDocumentEdited = isDirty
        }
    }
}
