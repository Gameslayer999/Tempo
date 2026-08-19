import AppKit
import SwiftUI

/// Real notch geometry read from `NSScreen`, with a fallback for notchless
/// displays. Computed once at process start; shared by the panel (window sizing
/// and positioning) and ContentView (interior layout), so both agree exactly.
enum NotchGeometry {
    static let sidePadding: CGFloat = 110
    static let panelHeight: CGFloat = 190

    static let targetScreen: NSScreen? =
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main

    private static let raw: (width: CGFloat, height: CGFloat) = {
        guard let screen = targetScreen else { return (200, 32) }
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let width = screen.frame.width - left.width - right.width
            let height = screen.safeAreaInsets.top
            if width > 0, height > 0 { return (width, height) }
        }
        return (200, 32) // notchless fallback: centered 200x32 strip
    }()

    static let notchWidth: CGFloat = raw.width
    static let notchHeight: CGFloat = raw.height
    static let stripHeight: CGFloat = notchHeight
    static let panelWidth: CGFloat = notchWidth + sidePadding * 2

    static var screenFrame: NSRect {
        targetScreen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }
}

/// NSHostingView that only accepts mouse events inside the shape SwiftUI is
/// currently drawing (the collapsed strip, or the full expanded panel).
///
/// The panel window is always sized to the expanded (max) dimensions so the
/// window frame never has to animate — only the SwiftUI content inside
/// animates, which avoids NSWindow frame-animation jank. But that means most
/// of the window is empty/transparent while collapsed, and a plain
/// NSHostingView would still claim every mouse event anywhere in its bounds
/// (breaking Agent Guideline #3: never swallow clicks meant for other apps).
/// Overriding `hitTest` to return nil outside the active rect makes AppKit
/// route those clicks to whatever window is beneath us instead.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    private let stripRect: CGRect
    private let fullRect: CGRect
    private let isDisplayedExpandedProvider: () -> Bool

    init(stripRect: CGRect, fullRect: CGRect, isDisplayedExpandedProvider: @escaping () -> Bool, rootView: Content) {
        self.stripRect = stripRect
        self.fullRect = fullRect
        self.isDisplayedExpandedProvider = isDisplayedExpandedProvider
        super.init(rootView: rootView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @available(*, unavailable)
    required init(rootView: Content) {
        fatalError("use init(stripRect:fullRect:isDisplayedExpandedProvider:rootView:) instead")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let activeRect = isDisplayedExpandedProvider() ? fullRect : stripRect
        guard activeRect.contains(point) else { return nil }
        return super.hitTest(point)
    }
}

/// Borderless, non-activating panel that hugs the notch. Collapsed it draws a
/// black strip flush with the notch; a click expands it below the notch.
@MainActor
final class NotchPanel: NSPanel {
    private var globalClickMonitor: Any?
    private let state: AppState

    init(state: AppState, content: ContentView) {
        self.state = state

        let panelWidth = NotchGeometry.panelWidth
        let panelHeight = NotchGeometry.panelHeight
        let stripHeight = NotchGeometry.stripHeight
        let screenFrame = NotchGeometry.screenFrame

        let origin = NSPoint(
            x: screenFrame.midX - panelWidth / 2,
            y: screenFrame.maxY - panelHeight
        )
        let frame = NSRect(origin: origin, size: NSSize(width: panelWidth, height: panelHeight))

        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)

        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false

        // Passthrough rect tracks "displayed-expanded" (hover OR pin), not
        // just the pinned flag: hovering the strip must grow the reachable
        // region immediately so the mouse can travel down into the controls
        // without ever leaving the active rect. Stability: fullRect always
        // contains stripRect (the full panel strictly encloses the strip at
        // its top edge), so the moment displayed-expanded flips true the
        // active rect only ever grows around a mouse point that was already
        // inside it — it can never eject the pointer and force a spurious
        // exit/collapse. No dead-zone headroom is needed for this (unlike the
        // old subtle hover-grow), since the rect flip is instant rather than
        // animated.
        let hostingView = PassthroughHostingView(
            stripRect: CGRect(
                x: 0,
                y: panelHeight - stripHeight,
                width: panelWidth,
                height: stripHeight
            ),
            fullRect: CGRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            isDisplayedExpandedProvider: { [weak state] in state?.displayedExpanded ?? false },
            rootView: content
        )
        contentView = hostingView

        // Click outside the panel (in another app, or the desktop) unpins
        // and collapses the expanded view. Global monitors only fire for
        // events outside our own app's windows, which is exactly "outside"
        // here.
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            guard let self, self.state.isExpanded || self.state.isHovered else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                self.state.isExpanded = false
                self.state.isHovered = false
            }
        }
    }

    deinit {
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
        }
    }
}
