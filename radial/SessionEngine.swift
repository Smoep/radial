import Foundation
import AppKit
import Observation
import CoreGraphics

/// Central coordinator: receives trackpad events, drives the radial pie menu,
/// computes the selected category/action, and fires mapped actions on release.
@Observable
final class SessionEngine {

    // MARK: - Published state

    private(set) var phase: GesturePhase = .idle
    /// Normalised touch X (0 = left, 1 = right).
    private(set) var liveXProgress: Double = 0
    /// Normalised touch Y (0 = bottom, 1 = top).
    private(set) var liveYProgress: Double = 0
    /// Current zone ID under the finger (e.g. "Z1") — kept for compatibility.
    private(set) var liveZoneID: String = "-"
    /// Zone index — kept for compatibility.
    private(set) var liveZoneIndex: Int = 0
    /// 0–1 progress toward activation during candidate hold phase.
    private(set) var candidateHoldProgress: Double = 0
    /// The zone ID that was finalized on last release.
    private(set) var finalizedZoneID: String? = nil
    /// Description of the last fired action.
    private(set) var lastFiredActionDescription: String? = nil
    /// Whether a finger is currently on the trackpad.
    private(set) var isTouching: Bool = false
    /// Whether the session is running.
    private(set) var isRunning: Bool = false
    /// Brief flash signal for the UI.
    private(set) var flashZoneID: String? = nil

    // MARK: - Radial selection state

    /// Selection path: index chosen at each depth (0 = category, 1 = action, 2+ = sub-action).
    private(set) var selectionPath: [Int] = []
    /// How many levels are locked (moving outward locks previous rings).
    private(set) var lockedDepth: Int = 0
    /// Finger angle in radians from center (measured from 12 o'clock, CW).
    private(set) var fingerAngle: Double = 0
    /// Finger distance from center in screen points.
    private(set) var fingerRadius: Double = 0
    /// Reveal animation progress 0→1 (sweeps slices in counter-clockwise).
    private(set) var revealProgress: Double = 0
    /// Per-depth reveal animation progress.
    private(set) var ringRevealProgress: [Double] = []

    // Legacy compatibility
    var selectedCategoryIndex: Int? { selectionPath.indices.contains(0) ? selectionPath[0] : nil }
    var selectedActionIndex: Int? { selectionPath.indices.contains(1) ? selectionPath[1] : nil }
    var categoryLocked: Bool { lockedDepth >= 1 }
    var outerRevealProgress: Double { ringRevealProgress.indices.contains(1) ? ringRevealProgress[1] : 0 }

    // MARK: - Dependencies

    let settings: AppSettings
    let trackpad: TrackpadService
    private let mouse = MouseTriggerService()
    private let stateMachine: GestureStateMachine
    private let selectionOverlay = SelectionOverlay()

    /// Screen-space center of the overlay (set on engage).
    private var overlayCenter: CGPoint = .zero

    private var pollTimer: Timer? = nil
    private var revealStartTime: CFTimeInterval = 0
    private let revealDuration: CFTimeInterval = 0.35
    /// Per-depth reveal start times and tracking.
    private var ringRevealStartTimes: [CFTimeInterval] = []
    private let ringRevealDuration: CFTimeInterval = 0.25
    /// Tracks which item triggered each ring's reveal.
    private var lastRevealedAtDepth: [Int?] = []

    // MARK: - Typing detection

    /// Global key-event monitor for pause-while-typing AND hotkey trigger.
    private var keyMonitor: Any?
    private var hotkeyMonitor: Any?
    /// Timestamp of last hotkey key-down (used for double-tap detection).
    private var lastHotkeyPressTime: CFTimeInterval = 0
    /// Timestamp of last detected keystroke.
    private var lastKeystrokeTime: CFTimeInterval = 0
    /// Cooldown after last keystroke before tracking resumes (seconds).
    private let typingCooldown: CFTimeInterval = 0.2
    /// Whether we're currently suppressed due to typing.
    var isPausedForTyping: Bool {
        guard settings.pauseWhileTyping else { return false }
        return CACurrentMediaTime() - lastKeystrokeTime < typingCooldown
    }

    // MARK: - Ring geometry (fixed per-item width, dynamic window)

    /// Radius of the dead zone at center.
    static let deadZoneRadius: Double = 38
    /// Gap between rings.
    static let ringGap: Double = 3
    /// Padding around the outermost ring inside the window.
    static let overlayPadding: Double = 8

    /// The configured ring height (radial thickness) from settings.
    private var configuredRingHeight: Double { settings.ringHeight }

    /// Outer radius of ring at given depth (0 = categories).
    func ringOuterRadius(depth: Int) -> Double {
        return Self.deadZoneRadius + configuredRingHeight * Double(depth + 1) + Self.ringGap * Double(depth)
    }

    /// Inner radius of ring at given depth.
    func ringInnerRadius(depth: Int) -> Double {
        if depth == 0 { return Self.deadZoneRadius }
        return ringOuterRadius(depth: depth - 1) + Self.ringGap
    }

    /// Compute the spread angle for items at a given depth based on the fixed selection width.
    /// Depth 0 (categories) always fills 360°. Deeper rings use fixed arc-length per item.
    func spreadAngle(forItemCount count: Int, atDepth depth: Int) -> Double {
        if depth == 0 { return 2.0 * Double.pi }
        let midR = (ringInnerRadius(depth: depth) + ringOuterRadius(depth: depth)) / 2.0
        let sliceAngle = settings.selectionWidth / midR
        return sliceAngle * Double(count)
    }

    /// Angular width of one slice at the given depth.
    func sliceAngle(forItemCount count: Int, atDepth depth: Int) -> Double {
        return spreadAngle(forItemCount: count, atDepth: depth) / Double(count)
    }

    /// How many rings are currently visible (always at least 1 for categories).
    var activeRingCount: Int {
        // Categories (depth 0) + one ring for each locked depth that has items below it + the free ring
        let items = itemsAtDepth(selectionPath.count)
        if selectionPath.isEmpty { return 1 }
        return items.isEmpty ? selectionPath.count : selectionPath.count + 1
    }

    /// The outermost visible ring's outer radius.
    var outermostRadius: Double {
        return ringOuterRadius(depth: max(0, activeRingCount - 1))
    }

    /// Window size needed for the current maximum menu depth.
    var overlayWindowSize: Double {
        let maxD = maxMenuDepth()
        let outerR = ringOuterRadius(depth: maxD)
        return (outerR + Self.overlayPadding) * 2
    }

    /// Returns items (actions) visible at a given depth for the current selection path.
    func itemsAtDepth(_ depth: Int) -> [RadialAction] {
        let categories = RadialMenuStore.shared.categories
        if depth == 0 { return [] }  // depth 0 = categories (handled separately)
        if depth == 1 {
            // Actions of the selected category
            guard selectionPath.indices.contains(0),
                  selectionPath[0] < categories.count else { return [] }
            return categories[selectionPath[0]].actions
        }
        // Deeper: walk the children
        guard selectionPath.indices.contains(0),
              selectionPath[0] < categories.count else { return [] }
        var items = categories[selectionPath[0]].actions
        for d in 1..<depth {
            guard selectionPath.indices.contains(d),
                  selectionPath[d] < items.count else { return [] }
            items = items[selectionPath[d]].children ?? []
        }
        return items
    }

    /// Walk the menu tree to find maximum depth.
    func maxMenuDepth() -> Int {
        let categories = RadialMenuStore.shared.categories
        var maxD = 1  // at least categories + actions
        for cat in categories {
            let d = 1 + Self.maxChildDepth(cat.actions)
            maxD = max(maxD, d)
        }
        return maxD
    }

    private static func maxChildDepth(_ actions: [RadialAction]) -> Int {
        var maxD = 0
        for action in actions {
            if let children = action.children, !children.isEmpty {
                maxD = max(maxD, 1 + maxChildDepth(children))
            }
        }
        return maxD
    }

    // MARK: - Shared instance

    /// Singleton started at app launch so tracking works without opening settings.
    static let shared = SessionEngine(settings: .shared)

    // MARK: - Init

    init(settings: AppSettings) {
        self.settings     = settings
        self.trackpad     = TrackpadService()
        self.stateMachine = GestureStateMachine()
        self.trackpad.settings = settings
        self.trackpad.shouldSuppressActivation = { [weak self] in
            self?.isPausedForTyping ?? false
        }
        configureMouseTrigger()
    }

    /// Wire the isolated mouse trigger to the shared engagement API.
    private func configureMouseTrigger() {
        mouse.settings           = settings
        mouse.isEngaged          = { [weak self] in self?.trackpad.isEngaged ?? false }
        mouse.hasTrackpadContact = { [weak self] in self?.trackpad.hasFingerContact ?? false }
        mouse.canActivate        = { true }
        mouse.onOpen             = { [weak self] in self?.trackpad.engage(external: true) }
        mouse.onDismiss          = { [weak self] in self?.dismissOverlay() }
        mouse.onSelect           = { [weak self] in self?.trackpad.triggerExternalRelease() }
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        stateMachine.reset()
        trackpad.start()
        mouse.start()

        // Combined monitor: pause-while-typing detection + hotkey trigger.
        // One monitor handles both so the hotkey is never treated as a "typing" keystroke.
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return }
            // Skip if this key matches the configured hotkey (handled by hotkeyMonitor).
            if self.isHotkeyEvent(event) { return }
            guard self.settings.pauseWhileTyping else { return }
            self.lastKeystrokeTime = CACurrentMediaTime()
            // Kill any in-progress candidate or engagement immediately.
            if self.trackpad.isEngaged {
                self.dismissOverlay()
            } else if self.trackpad.isTouching {
                self.trackpad.disengage()
            }
        }

        // Separate monitor for keyUp so we can finalize on hotkey release.
        hotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.settings.hotkeyEnabled, self.settings.hotkeyKeyCode >= 0 else { return }
            switch event.type {
            case .flagsChanged:
                // Modifier key double-tap (⌘⌘, ⇧⇧, etc.)
                guard self.settings.hotkeyMode == .doubleTap,
                      Int(event.keyCode) == self.settings.hotkeyKeyCode else { return }
                let flag = AppSettings.modifierFlagForKeyCode(self.settings.hotkeyKeyCode)
                guard !flag.isEmpty, event.modifierFlags.contains(flag) else { return } // press only
                self.handleDoubleTap()
            case .keyDown where !event.isARepeat:
                guard Int(event.keyCode) == self.settings.hotkeyKeyCode else { return }
                if self.settings.hotkeyMode == .combo {
                    guard self.isHotkeyEvent(event) else { return }
                    if self.trackpad.isEngaged { self.dismissOverlay() }
                    else { self.trackpad.engage(external: true) }
                } else {
                    guard !AppSettings.isModifierKeyCode(self.settings.hotkeyKeyCode) else { return }
                    self.handleDoubleTap()
                }
            default: break
            }
        }

        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        guard isRunning else { return }
        pollTimer?.invalidate()
        pollTimer = nil
        trackpad.stop()
        mouse.stop()
        stateMachine.reset()
        if let m = keyMonitor    { NSEvent.removeMonitor(m); keyMonitor    = nil }
        if let m = hotkeyMonitor { NSEvent.removeMonitor(m); hotkeyMonitor = nil }
        isRunning = false
        phase = .idle
        isTouching = false
    }

    // MARK: - Tick

    private var wasTouchingLastTick: Bool = false

    private func tick() {
        let touching = trackpad.isTouching
        let engaged = trackpad.isEngaged
        let phases = trackpad.consumePhases()
        let clicked = trackpad.consumeClick()

        if touching != isTouching {
            isTouching = touching
        }

        // Suppress activation while typing.
        let typingSuppressed = isPausedForTyping

        let newPhase: GesturePhase
        if engaged && !typingSuppressed {
            newPhase = .active
        } else if touching && !typingSuppressed {
            newPhase = .candidate
        } else {
            newPhase = .idle
        }

        if phase != newPhase {
            if newPhase == .active {
                selectionPath = []
                lockedDepth = 0
                fingerAngle = 0
                fingerRadius = 0
                revealProgress = 0
                ringRevealProgress = []
                ringRevealStartTimes = []
                lastRevealedAtDepth = []
                revealStartTime = CACurrentMediaTime()
                selectionOverlay.show(engine: self)
                overlayCenter = selectionOverlay.center
            } else if phase == .active {
                selectionOverlay.hide()
            }
            phase = newPhase
        }

        candidateHoldProgress = 0

        // Animate reveal progress.
        if phase == .active {
            let now = CACurrentMediaTime()
            let elapsed = now - revealStartTime
            let t = min(elapsed / revealDuration, 1.0)
            // ease-out cubic
            let eased = 1.0 - pow(1.0 - t, 3.0)
            if abs(eased - revealProgress) > 0.001 {
                revealProgress = eased
            }

            updateRadialSelectionFromCursor()

            // Per-depth ring reveal animations.
            let neededDepths = activeRingCount
            // Ensure arrays are big enough.
            while ringRevealProgress.count < neededDepths {
                ringRevealProgress.append(0)
                ringRevealStartTimes.append(now)
                lastRevealedAtDepth.append(nil)
            }
            // Trim if we went shallower.
            if ringRevealProgress.count > neededDepths {
                ringRevealProgress.removeSubrange(neededDepths...)
                ringRevealStartTimes.removeSubrange(neededDepths...)
                lastRevealedAtDepth.removeSubrange(neededDepths...)
            }

            for d in 0..<neededDepths {
                // Check if the parent selection changed (triggers new reveal).
                let parentIdx = d > 0 && selectionPath.indices.contains(d - 1) ? selectionPath[d - 1] : -1
                if d < lastRevealedAtDepth.count && lastRevealedAtDepth[d] != parentIdx {
                    lastRevealedAtDepth[d] = parentIdx
                    ringRevealProgress[d] = 0
                    ringRevealStartTimes[d] = now
                }
                if ringRevealProgress[d] < 1.0 {
                    let dur = d == 0 ? revealDuration : ringRevealDuration
                    let rElapsed = now - ringRevealStartTimes[d]
                    let rT = min(rElapsed / dur, 1.0)
                    let rEased = 1.0 - pow(1.0 - rT, 3.0)
                    if abs(rEased - ringRevealProgress[d]) > 0.001 {
                        ringRevealProgress[d] = rEased
                    }
                }
            }
        }

        // Handle click while overlay is active.
        if clicked && phase == .active {
            handleOverlayClick()
        }

        wasTouchingLastTick = touching
    }

    // MARK: - Radial selection (cursor-driven)

    private func updateRadialSelectionFromCursor() {
        let cursorLoc = NSEvent.mouseLocation
        let dx = cursorLoc.x - overlayCenter.x
        let dy = cursorLoc.y - overlayCenter.y
        let pixelDist = sqrt(dx * dx + dy * dy)
        if abs(pixelDist - fingerRadius) > 0.5 { fingerRadius = pixelDist }

        // Escape: cursor too far beyond outermost ring → dismiss.
        if pixelDist > outermostRadius + 100 {
            dismissOverlay()
            return
        }

        // CW angle from 12 o'clock.
        var cwAngle = Double.pi / 2 - atan2(dy, dx)
        if cwAngle < 0 { cwAngle += 2 * Double.pi }
        if cwAngle >= 2 * Double.pi { cwAngle -= 2 * Double.pi }
        if abs(cwAngle - fingerAngle) > 0.005 { fingerAngle = cwAngle }

        let categories = RadialMenuStore.shared.categories
        guard !categories.isEmpty else { return }

        // Dead zone: reset everything.
        if pixelDist < Self.deadZoneRadius {
            selectionPath = []
            lockedDepth = 0
            return
        }

        // Determine which depth ring the cursor is in.
        var cursorDepth = 0
        for d in 0..<10 {
            if pixelDist >= ringInnerRadius(depth: d) && pixelDist < ringOuterRadius(depth: d) {
                cursorDepth = d
                break
            }
            if pixelDist >= ringOuterRadius(depth: d) {
                cursorDepth = d + 1
            }
        }

        // Depth 0: category selection (full 360°).
        let catCount = categories.count
        let catAngle = (2 * Double.pi) / Double(catCount)

        let firstRingThickness = ringOuterRadius(depth: 0) - ringInnerRadius(depth: 0)
        let flexibleBoundary = ringInnerRadius(depth: 0)
            + firstRingThickness * (settings.categoryFlexibilityPercent / 100.0)
        // Purely positional: the category can change whenever the cursor is in the
        // inner flexible band of the first ring. There is no permanent commit — moving
        // outward (or into a deeper ring) simply keeps the current category, and
        // returning to the flexible band re-enables switching.
        let canChangeCategory = selectionPath.isEmpty
            || (cursorDepth == 0 && pixelDist < flexibleBoundary)

        if canChangeCategory {
            let catIdx = Int(cwAngle / catAngle) % catCount
            if selectionPath.isEmpty {
                selectionPath = [catIdx]
            } else {
                selectionPath[0] = catIdx
            }
            lockedDepth = 1
        }

        // If cursor is in depth 0 ring area and there's no deeper ring yet, we're done.
        if cursorDepth == 0 {
            // Truncate path to just category.
            if selectionPath.count > 1 {
                selectionPath = [selectionPath[0]]
                lockedDepth = 1
            }
            return
        }

        // Deeper rings: fixed arc-length per item, centered on parent.

        for depth in 1...cursorDepth {
            let items = itemsAtDepth(depth)
            guard !items.isEmpty else { break }

            // Parent's mid-angle determines the spread center.
            let parentMidAngle = midAngleForItem(atDepth: depth - 1)

            let itemCount = items.count
            let totalSpread = spreadAngle(forItemCount: itemCount, atDepth: depth)
            let sliceAngle = totalSpread / Double(itemCount)
            let arcStart = parentMidAngle - totalSpread / 2

            // Select item from angle.
            var relAngle = cwAngle - arcStart
            // Normalize to [0, 2π) to handle wrap-around correctly.
            relAngle = relAngle.truncatingRemainder(dividingBy: 2 * Double.pi)
            if relAngle < 0 { relAngle += 2 * Double.pi }
            // If outside the arc, clamp to the nearest edge.
            if relAngle > totalSpread {
                let distToEnd = relAngle - totalSpread
                let distToStart = 2 * Double.pi - relAngle
                relAngle = distToStart < distToEnd ? 0 : totalSpread
            }
            let itemIdx = min(itemCount - 1, Int(relAngle / sliceAngle))

            if depth < cursorDepth {
                // Lock this depth.
                if selectionPath.count <= depth {
                    selectionPath.append(itemIdx)
                } else if lockedDepth <= depth {
                    selectionPath[depth] = itemIdx
                }
                lockedDepth = max(lockedDepth, depth + 1)
            } else {
                // Current depth: free selection.
                if selectionPath.count <= depth {
                    selectionPath.append(itemIdx)
                } else {
                    selectionPath[depth] = itemIdx
                }
            }
        }

        // Truncate path beyond cursor depth.
        if selectionPath.count > cursorDepth + 1 {
            selectionPath = Array(selectionPath.prefix(cursorDepth + 1))
            lockedDepth = min(lockedDepth, cursorDepth + 1)
        }

        // Update legacy zone ID.
        updateLegacyZoneID()
    }

    /// Mid-angle of the selected item at a given depth (CW from 12 o'clock).
    func midAngleForItem(atDepth depth: Int) -> Double {
        let categories = RadialMenuStore.shared.categories
        guard selectionPath.indices.contains(depth) else { return 0 }
        let idx = selectionPath[depth]

        if depth == 0 {
            let catAngle = (2 * Double.pi) / Double(categories.count)
            return catAngle * (Double(idx) + 0.5)
        }

        // Deeper items: fixed arc-length per item, centered on parent.
        let parentMidAngle = midAngleForItem(atDepth: depth - 1)
        let items = itemsAtDepth(depth)
        guard !items.isEmpty else { return parentMidAngle }
        let totalSpread = spreadAngle(forItemCount: items.count, atDepth: depth)
        let itemSlice = totalSpread / Double(items.count)
        let arcStart = parentMidAngle - totalSpread / 2
        return arcStart + itemSlice * (Double(idx) + 0.5)
    }

    private func updateLegacyZoneID() {
        let categories = RadialMenuStore.shared.categories
        guard selectionPath.indices.contains(0),
              selectionPath[0] < categories.count else {
            if liveZoneID != "-" { liveZoneID = "-" }
            return
        }
        let cat = categories[selectionPath[0]]
        if selectionPath.count == 1 {
            if liveZoneID != cat.label { liveZoneID = cat.label }
            return
        }
        // Walk the path to find the deepest selected item.
        var items = cat.actions
        var label = cat.label
        for d in 1..<selectionPath.count {
            guard selectionPath[d] < items.count else { break }
            let item = items[selectionPath[d]]
            label = item.label
            items = item.children ?? []
        }
        if liveZoneID != label { liveZoneID = label }
    }

    // MARK: - Click handling

    /// Called when user clicks while overlay is showing.
    private func handleOverlayClick() {
        // Dead zone → just dismiss.
        if fingerRadius < Self.deadZoneRadius || selectionPath.isEmpty {
            dismissOverlay()
            return
        }

        // Walk selection path to find the deepest selected action.
        let categories = RadialMenuStore.shared.categories
        guard selectionPath[0] < categories.count else { dismissOverlay(); return }
        let cat = categories[selectionPath[0]]

        if selectionPath.count == 1 {
            // Only category selected, no action → dismiss.
            dismissOverlay()
            return
        }

        // Walk to the deepest item.
        var items = cat.actions
        var selectedAction: RadialAction?
        var pathLabels = [cat.label]
        for d in 1..<selectionPath.count {
            guard selectionPath[d] < items.count else { break }
            let item = items[selectionPath[d]]
            pathLabels.append(item.label)
            if d == selectionPath.count - 1 {
                selectedAction = item
            }
            items = item.children ?? []
        }

        guard let action = selectedAction else { dismissOverlay(); return }

        // If it's a subcategory, don't execute — user needs to go deeper.
        if action.isSubcategory {
            return
        }

        finalizedZoneID = pathLabels.joined(separator: " → ")
        lastFiredActionDescription = action.label

        flashZoneID = action.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            if self?.flashZoneID == action.id { self?.flashZoneID = nil }
        }

        executeAfterOverlayDismiss(action)
    }

    /// Returns true if `event` matches the configured keyboard shortcut.
    private func isHotkeyEvent(_ event: NSEvent) -> Bool {
        guard settings.hotkeyEnabled, settings.hotkeyKeyCode >= 0 else { return false }
        guard Int(event.keyCode) == settings.hotkeyKeyCode else { return false }
        if settings.hotkeyMode == .doubleTap { return true }  // keyCode match is enough
        let expected = NSEvent.ModifierFlags(rawValue: UInt(settings.hotkeyModifiers))
            .intersection([.command, .option, .shift, .control])
        let actual = event.modifierFlags
            .intersection([.command, .option, .shift, .control])
        return actual == expected
    }

    /// Double-tap trigger: fire on second press within the configured window.
    private func handleDoubleTap() {
        let now = CACurrentMediaTime()
        if now - lastHotkeyPressTime < settings.doubleTapWindow {
            lastHotkeyPressTime = 0  // reset so triple-tap doesn't re-fire
            if trackpad.isEngaged { dismissOverlay() }
            else { trackpad.engage(external: true) }
        } else {
            lastHotkeyPressTime = now
        }
    }

    private func dismissOverlay() {
        trackpad.disengage()
        selectionOverlay.hide()
        phase = .idle
        selectionPath = []
        lockedDepth = 0
        fingerRadius = 0
        fingerAngle = 0
    }

    private func executeAfterOverlayDismiss(_ action: RadialAction) {
        let mapping = action.asMapping
        let shouldExecute = !settings.isTestMode
        dismissOverlay()
        guard shouldExecute else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            ActionExecutor.execute(mapping)
        }
    }

    private func finalizeRadialSelection() {
        let categories = RadialMenuStore.shared.categories
        guard selectionPath.count >= 2,
              selectionPath[0] < categories.count else {
            finalizedZoneID = nil
            lastFiredActionDescription = nil
            return
        }

        let cat = categories[selectionPath[0]]
        var items = cat.actions
        var selectedAction: RadialAction?
        var pathLabels = [cat.label]
        for d in 1..<selectionPath.count {
            guard selectionPath[d] < items.count else { break }
            let item = items[selectionPath[d]]
            pathLabels.append(item.label)
            if d == selectionPath.count - 1 { selectedAction = item }
            items = item.children ?? []
        }

        guard let action = selectedAction, !action.isSubcategory else {
            finalizedZoneID = nil
            lastFiredActionDescription = nil
            return
        }

        finalizedZoneID = pathLabels.joined(separator: " → ")
        lastFiredActionDescription = action.label

        flashZoneID = action.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            if self?.flashZoneID == action.id { self?.flashZoneID = nil }
        }

        executeAfterOverlayDismiss(action)
    }

    func clearFinalizedValue() {
        finalizedZoneID = nil
        lastFiredActionDescription = nil
    }
}
