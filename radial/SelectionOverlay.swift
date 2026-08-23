import AppKit
import SwiftUI
import QuartzCore

private final class NonActivatingOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Slice content metrics

/// How far inside the ring's mid-radius the icon sits.
private let radialIconInset: CGFloat = 14
/// How far outside the ring's mid-radius the label sits.
private let radialLabelOutset: CGFloat = 13
/// Fraction of a slice's arc the label may occupy, leaving padding at both edges.
private let radialLabelArcFraction: CGFloat = 0.78
/// How far a subcategory tab protrudes past the ring. Must stay under the
/// gap to the next ring (`SessionEngine.ringGap`) so rings never collide.
private let subcategoryTabHeight: CGFloat = 4.5

/// Floating overlay window that shows a radial pie menu at the cursor
/// when the trackpad is engaged. Individual glass elements, macOS 26 style.
/// Supports recursive sub-category rings.
final class SelectionOverlay {

    private var window: NSPanel?
    private var hostView: NSHostingView<OverlayRadialView>?
    /// Panels whose WindowServer backing became stale after a Space topology
    /// change. Keep them alive until the transition has fully settled; releasing
    /// an AppKit/SwiftUI panel from inside the Space notification can race queued
    /// display work and crash in objc_release.
    private var retiredWindows: [NSPanel] = []
    private var retiredWindowCleanup: DispatchWorkItem?

    /// Screen-space center of the overlay (after show).
    var center: CGPoint = .zero

    func show(engine: SessionEngine) {
        let size = CGFloat(engine.overlayWindowSize)

        if window == nil {
            let frame = NSRect(x: 0, y: 0, width: size, height: size)
            let view = OverlayRadialView(engine: engine)
            let hv = NSHostingView(rootView: view)
            hv.frame = frame
            // Layer-backed so appear/disappear run as GPU-composited
            // Core Animation transitions instead of CPU redraws.
            hv.wantsLayer = true
            hv.layerContentsRedrawPolicy = .onSetNeedsDisplay
            self.hostView = hv

            let w = NonActivatingOverlayPanel(
                contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            w.isOpaque = false
            w.backgroundColor = .clear
            w.level = .screenSaver
            w.ignoresMouseEvents = true
            w.hasShadow = false
            w.becomesKeyOnlyIfNeeded = true
            w.hidesOnDeactivate = false
            w.collectionBehavior = [.canJoinAllSpaces, .stationary]
            w.contentView = hv
            self.window = w
        } else {
            let frame = NSRect(x: 0, y: 0, width: size, height: size)
            hostView?.frame = frame
            hostView?.rootView = OverlayRadialView(engine: engine)
        }

        let cursorLoc = NSEvent.mouseLocation
        let unclampedOrigin = NSPoint(
            x: cursorLoc.x - size / 2,
            y: cursorLoc.y - size / 2
        )
        let origin = clampedOrigin(for: unclampedOrigin, windowSize: size, cursorLoc: cursorLoc)
        center = CGPoint(x: origin.x + size / 2, y: origin.y + size / 2)
        window?.setFrame(NSRect(origin: origin, size: NSSize(width: size, height: size)), display: true)
        if center != CGPoint(x: cursorLoc.x, y: cursorLoc.y) {
            moveCursor(to: center)
        }
        window?.alphaValue = 1.0
        window?.orderFrontRegardless()
        playAppear()
    }

    /// Resize the window in place (keeping it centred) after the menu depth
    /// changed — e.g. when switching between the app menu and the Global Menu.
    func resize(engine: SessionEngine) {
        guard let window, window.isVisible else { return }
        let size = CGFloat(engine.overlayWindowSize)
        guard abs(window.frame.width - size) > 0.5 else { return }

        let cursorLoc = NSEvent.mouseLocation
        let unclampedOrigin = NSPoint(x: center.x - size / 2, y: center.y - size / 2)
        let origin = clampedOrigin(for: unclampedOrigin, windowSize: size, cursorLoc: cursorLoc)
        let newCenter = CGPoint(x: origin.x + size / 2, y: origin.y + size / 2)

        hostView?.frame = NSRect(x: 0, y: 0, width: size, height: size)
        window.setFrame(NSRect(origin: origin, size: NSSize(width: size, height: size)), display: true)
        if newCenter != center {
            center = newCenter
            moveCursor(to: newCenter)
        }
    }

    private func clampedOrigin(for origin: NSPoint, windowSize: CGFloat, cursorLoc: NSPoint) -> NSPoint {
        let screen = NSScreen.screens.first { $0.frame.contains(cursorLoc) } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return origin }

        let maxX = max(visibleFrame.minX, visibleFrame.maxX - windowSize)
        let maxY = max(visibleFrame.minY, visibleFrame.maxY - windowSize)
        return NSPoint(
            x: min(max(origin.x, visibleFrame.minX), maxX),
            y: min(max(origin.y, visibleFrame.minY), maxY)
        )
    }

    private func moveCursor(to point: CGPoint) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }),
              let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return }
        let displayID = CGDirectDisplayID(screenNumber.uint32Value)
        let displayPoint = CGPoint(
            x: point.x - screen.frame.minX,
            y: screen.frame.maxY - point.y
        )
        CGDisplayMoveCursorToPoint(displayID, displayPoint)
    }

    func hide() {
        guard let layer = hostView?.layer, window?.isVisible == true else {
            window?.orderOut(nil)
            return
        }
        // Fade + slight shrink, then order out.
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            self?.window?.orderOut(nil)
            layer.opacity = 1
            layer.transform = CATransform3DIdentity
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1.0
        fade.toValue = 0.0
        fade.duration = 0.14
        fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
        let shrink = CABasicAnimation(keyPath: "transform.scale")
        shrink.fromValue = 1.0
        shrink.toValue = 0.94
        shrink.duration = 0.14
        shrink.timingFunction = CAMediaTimingFunction(name: .easeIn)
        layer.opacity = 0
        layer.add(fade, forKey: "tzFade")
        layer.add(shrink, forKey: "tzShrink")
        CATransaction.commit()
    }

    /// Remove the overlay from screen synchronously before launching an action
    /// that may capture the current display contents.
    func hideImmediately() {
        hostView?.layer?.removeAllAnimations()
        hostView?.layer?.opacity = 1
        hostView?.layer?.transform = CATransform3DIdentity
        window?.orderOut(nil)
        CATransaction.flush()
    }

    /// Retire the cached panel after a Space change. The next `show` creates a
    /// fresh panel on the current Space, while the old backing store is released
    /// only after WindowServer has finished the transition.
    func retireForSpaceChange() {
        hideImmediately()
        if let window {
            window.orderOut(nil)
            retiredWindows.append(window)
        }
        window = nil
        hostView = nil
        center = .zero

        retiredWindowCleanup?.cancel()
        let cleanup = DispatchWorkItem { [weak self] in
            guard let self else { return }
            for panel in self.retiredWindows { panel.close() }
            self.retiredWindows.removeAll()
        }
        retiredWindowCleanup = cleanup
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: cleanup)
    }

    private func playAppear() {
        guard let layer = hostView?.layer else { return }
        layer.removeAllAnimations()
        layer.opacity = 1
        layer.transform = CATransform3DIdentity
        // Anchor scale at the center of the view.
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.position = CGPoint(x: layer.bounds.midX, y: layer.bounds.midY)

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.0
        fade.toValue = 1.0
        fade.duration = 0.16
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let pop = CASpringAnimation(keyPath: "transform.scale")
        pop.fromValue = 0.88
        pop.toValue = 1.0
        pop.mass = 0.7
        pop.stiffness = 260
        pop.damping = 20
        pop.duration = pop.settlingDuration

        layer.add(fade, forKey: "tzFade")
        layer.add(pop, forKey: "tzPop")
    }
}

// MARK: - Radial menu view (recursive glass rings)

private struct OverlayRadialView: View {
    var engine: SessionEngine

    /// How far the outgoing/incoming rings rotate during a menu switch.
    private static let switchRotation: CGFloat = 0.30

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let rootItems = engine.activeItems
            guard !rootItems.isEmpty else { return }

            let reveal = CGFloat(engine.revealProgress)
            let startOffset = -CGFloat.pi / 2  // 12 o'clock
            let gap: CGFloat = 3

            let innerR = CGFloat(engine.ringInnerRadius(depth: 0))
            let outerR = CGFloat(engine.ringOuterRadius(depth: 0))

            // ── Center glass hub (scales in, then stays put across switches) ──
            let centerR = innerR * CGFloat(engine.hubScale)
            let centerRect = CGRect(
                x: center.x - centerR, y: center.y - centerR,
                width: centerR * 2, height: centerR * 2
            )
            let centerCircle = Circle().path(in: centerRect)
            let hubOp = AppSettings.shared.overlayOpacity
            context.fill(
                centerCircle,
                with: .radialGradient(
                    Gradient(colors: [Color(white: 0.22).opacity(hubOp),
                                      Color(white: 0.06).opacity(hubOp)]),
                    center: CGPoint(x: center.x, y: center.y - centerR * 0.4),
                    startRadius: 0, endRadius: max(centerR, 1)
                )
            )
            context.stroke(centerCircle, with: .color(.white.opacity(0.35 * hubOp)), lineWidth: 0.5)

            let hubAlpha = engine.hubAlpha
            if hubAlpha > 0.001 {
                drawHubContent(context: context, center: center,
                               radius: centerR, engine: engine,
                               rootItems: rootItems, alpha: hubAlpha)
            }

            // ── Menu switch: old slices fade + rotate anti-clockwise out while
            //    the new ones fade + rotate anti-clockwise in. ──
            let switchT = CGFloat(engine.switchProgress)
            if switchT < 1, !engine.outgoingItems.isEmpty {
                var outCtx = rotated(context, around: center, by: -Self.switchRotation * switchT)
                outCtx.opacity = Double(1 - switchT)
                drawRootRing(context: outCtx, center: center,
                             items: engine.outgoingItems,
                             innerR: innerR, outerR: outerR, gap: gap,
                             startOffset: startOffset, reveal: 1, selectedIdx: nil)
            }

            // ── Ring 0: first-ring slices (full 360°) ──
            let ringCtx = switchT < 1
                ? rotated(context, around: center, by: Self.switchRotation * (1 - switchT))
                : context
            drawRootRing(context: ringCtx, center: center, items: rootItems,
                         innerR: innerR, outerR: outerR, gap: gap,
                         startOffset: startOffset, reveal: reveal,
                         selectedIdx: engine.selectedCategoryIndex)

            // ── Deeper rings (recursive) ──
            let activeDepth = engine.activeRingCount
            guard activeDepth > 1 else { return }

            for depth in 1..<activeDepth {
                let items = engine.itemsAtDepth(depth)
                guard !items.isEmpty else { continue }

                let ringReveal: CGFloat
                if depth < engine.ringRevealProgress.count {
                    ringReveal = CGFloat(engine.ringRevealProgress[depth])
                } else {
                    ringReveal = 0
                }

                let rInner = CGFloat(engine.ringInnerRadius(depth: depth))
                let rOuter = CGFloat(engine.ringOuterRadius(depth: depth))

                // Parent determines the center angle; colour is inherited unless
                // the item overrides it.
                let inheritedHex = engine.inheritedColorHex(atDepth: depth)

                let parentMidAngleCW = engine.midAngleForItem(atDepth: depth - 1)
                // Convert CW-from-12 to canvas angle (CCW-from-3)
                let parentMidAngle = startOffset + CGFloat(parentMidAngleCW)

                let itemCount = items.count
                let totalSpread = CGFloat(engine.spreadAngle(forItemCount: itemCount, atDepth: depth))
                let sliceAngle = totalSpread / CGFloat(itemCount)
                let arcStart = parentMidAngle - totalSpread / 2
                let ringGapAngle = gap / ((rInner + rOuter) / 2)
                let ringRevealAngle = ringReveal * totalSpread

                let selectedIdx = engine.selectionPath.indices.contains(depth) ? engine.selectionPath[depth] : nil

                for j in 0..<itemCount {
                    let item = items[j]
                    let color = colorFromHex(item.colorHex ?? inheritedHex)
                    let a1 = arcStart + sliceAngle * CGFloat(j) + ringGapAngle / 2
                    let a2 = arcStart + sliceAngle * CGFloat(j + 1) - ringGapAngle / 2
                    let isSelected = selectedIdx == j

                    let sliceCCWStart = sliceAngle * CGFloat(itemCount - 1 - j)
                    if sliceCCWStart >= ringRevealAngle { continue }
                    let actRevealFrac = min((ringRevealAngle - sliceCCWStart) / sliceAngle, 1.0)
                    let clippedA1 = a2 - actRevealFrac * (a2 - a1)

                    drawGlassSlice(context: context, center: center,
                                   innerR: rInner + 2, outerR: rOuter,
                                   a1: clippedA1, a2: a2,
                                   color: color, isSelected: isSelected,
                                   baseOpacity: 0.75,
                                   tabMid: item.isSubcategory ? (a1 + a2) / 2 : nil)

                    guard actRevealFrac > 0.7 else { continue }
                    let actLabelAlpha = min((actRevealFrac - 0.7) / 0.3, 1.0)
                    let midA = (a1 + a2) / 2
                    let labelR = (rInner + rOuter) / 2
                    let iconPt = pointOnCircle(center, labelR - radialIconInset, midA)

                    if let icon = customIcon(for: item) {
                        drawRotatedAppIcon(
                            icon, context: context,
                            at: iconPt, angle: midA,
                            size: isSelected ? 32 : 28, opacity: actLabelAlpha
                        )
                    } else {
                        drawRotatedIcon(
                            systemName: item.systemImage, context: context,
                            at: iconPt, angle: midA,
                            fontSize: isSelected ? 20 : 17, opacity: actLabelAlpha
                        )
                    }

                    drawCurvedLabel(
                        item.label, context: context, center: center,
                        radius: labelR + radialLabelOutset, midAngle: midA,
                        fontSize: CGFloat(AppSettings.shared.menuLabelFontSize),
                        maxAngle: (a2 - a1) * radialLabelArcFraction,
                        opacity: (isSelected ? 1.0 : 0.8) * actLabelAlpha
                    )
                }
            }
        }
    }

    // MARK: - Drawing helpers

    /// A copy of `context` rotated by `angle` around `center`.
    /// Positive angles rotate clockwise (the canvas y-axis points down), so
    /// negative angles produce the anti-clockwise motion used throughout.
    private func rotated(_ context: GraphicsContext, around center: CGPoint, by angle: CGFloat) -> GraphicsContext {
        var ctx = context
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: .radians(angle))
        ctx.translateBy(x: -center.x, y: -center.y)
        return ctx
    }

    /// Draw the innermost ring, sweeping in anti-clockwise as `reveal` goes 0→1.
    private func drawRootRing(
        context: GraphicsContext, center: CGPoint,
        items: [RadialAction],
        innerR: CGFloat, outerR: CGFloat, gap: CGFloat,
        startOffset: CGFloat, reveal: CGFloat, selectedIdx: Int?
    ) {
        let count = items.count
        guard count > 0 else { return }
        let catAngle = (2 * CGFloat.pi) / CGFloat(count)
        let gapAngle = gap / ((innerR + outerR) / 2)
        let revealAngle = reveal * 2 * CGFloat.pi

        for i in 0..<count {
            let item = items[i]
            let a1 = startOffset + catAngle * CGFloat(i) + gapAngle / 2
            let a2 = startOffset + catAngle * CGFloat(i + 1) - gapAngle / 2
            let isSelected = selectedIdx == i

            let sliceCCWStart = catAngle * CGFloat(count - 1 - i)
            if sliceCCWStart >= revealAngle { continue }
            let sliceRevealFrac = min((revealAngle - sliceCCWStart) / catAngle, 1.0)
            let clippedA1 = a2 - sliceRevealFrac * (a2 - a1)
            let color = colorFromHex(item.colorHex ?? radialDefaultColorHex)

            drawGlassSlice(context: context, center: center,
                           innerR: innerR + 2, outerR: outerR - 2,
                           a1: clippedA1, a2: a2,
                           color: color, isSelected: isSelected,
                           baseOpacity: 0.55,
                           tabMid: item.isSubcategory ? (a1 + a2) / 2 : nil)

            guard sliceRevealFrac > 0.7 else { continue }
            let labelAlpha = min((sliceRevealFrac - 0.7) / 0.3, 1.0)
            let midA = (a1 + a2) / 2
            let labelR = (innerR + outerR) / 2
            let iconPt = pointOnCircle(center, labelR - radialIconInset, midA)

            if let icon = customIcon(for: item) {
                drawRotatedAppIcon(
                    icon, context: context,
                    at: iconPt, angle: midA,
                    size: isSelected ? 32 : 28, opacity: labelAlpha
                )
            } else {
                drawRotatedIcon(
                    systemName: item.systemImage, context: context,
                    at: iconPt, angle: midA,
                    fontSize: isSelected ? 20 : 17, opacity: labelAlpha
                )
            }
            drawCurvedLabel(
                item.label, context: context, center: center,
                radius: labelR + radialLabelOutset, midAngle: midA,
                fontSize: CGFloat(AppSettings.shared.menuLabelFontSize),
                maxAngle: (a2 - a1) * radialLabelArcFraction,
                opacity: 0.9 * labelAlpha
            )
        }
    }

    /// Draws one slice. `tabMid`, when set, adds a small pointed tab budding out
    /// of the outer rim at that angle to mark a slice that opens a deeper ring.
    /// The tab is part of the slice's own path, so the gradient, sheen, stroke
    /// and glow all flow through it without a seam.
    private func drawGlassSlice(
        context: GraphicsContext, center: CGPoint,
        innerR: CGFloat, outerR: CGFloat,
        a1: CGFloat, a2: CGFloat,
        color: Color, isSelected: Bool,
        baseOpacity: Double,
        tabMid: CGFloat? = nil
    ) {
        // Selected slice pops outward slightly.
        let outR = isSelected ? outerR + 4 : outerR
        let mid = (a1 + a2) / 2
        // Overall overlay opacity: 1.0 = solid, lower = see-through.
        let op = AppSettings.shared.overlayOpacity

        var path = Path()
        path.move(to: pointOnCircle(center, innerR, a1))
        if let tabAngle = tabMid, !isSelected,
           let halfSpan = subcategoryTabHalfSpan(outerR: outR, sliceAngle: a2 - a1) {
            let dA = halfSpan / outR
            // Skip while the slice is still sweeping in and the rim is clipped.
            if tabAngle - dA > a1, tabAngle + dA < a2 {
                let tipR = outR + subcategoryTabHeight
                path.addArc(center: center, radius: outR,
                            startAngle: .radians(a1), endAngle: .radians(tabAngle - dA),
                            clockwise: false)
                path.addLine(to: pointOnCircle(center, tipR - 1.5, tabAngle - dA * 0.3))
                path.addQuadCurve(to: pointOnCircle(center, tipR - 1.5, tabAngle + dA * 0.3),
                                  control: pointOnCircle(center, tipR + 1.2, tabAngle))
                path.addLine(to: pointOnCircle(center, outR, tabAngle + dA))
                path.addArc(center: center, radius: outR,
                            startAngle: .radians(tabAngle + dA), endAngle: .radians(a2),
                            clockwise: false)
            } else {
                path.addArc(center: center, radius: outR,
                            startAngle: .radians(a1), endAngle: .radians(a2), clockwise: false)
            }
        } else {
            path.addArc(center: center, radius: outR,
                        startAngle: .radians(a1), endAngle: .radians(a2), clockwise: false)
        }
        path.addLine(to: pointOnCircle(center, innerR, a2))
        path.addArc(center: center, radius: innerR,
                     startAngle: .radians(a2), endAngle: .radians(a1), clockwise: true)
        path.closeSubpath()

        _ = baseOpacity
        // Solid dark backing whose alpha is driven by the opacity setting:
        // at 100% it fully hides the screen behind the slice.
        var shadowCtx = context
        shadowCtx.addFilter(.shadow(color: .black.opacity((isSelected ? 0.45 : 0.30) * op),
                                    radius: isSelected ? 7 : 4, x: 0, y: 2))
        shadowCtx.fill(path, with: .color(Color(white: 0.13).opacity(op)))

        // Radial glass gradient: darker at the inner edge, tinted brighter outward.
        let gInner = pointOnCircle(center, innerR, mid)
        let gOuter = pointOnCircle(center, outR, mid)
        context.fill(
            path,
            with: .linearGradient(
                Gradient(colors: [
                    color.opacity((isSelected ? 0.28 : 0.12) * op),
                    color.opacity((isSelected ? 0.62 : 0.32) * op)
                ]),
                startPoint: gInner, endPoint: gOuter
            )
        )
        // Top sheen.
        context.fill(
            path,
            with: .linearGradient(
                Gradient(colors: [.white.opacity((isSelected ? 0.14 : 0.07) * op),
                                  .white.opacity(0.0)]),
                startPoint: gOuter, endPoint: gInner
            )
        )
        context.stroke(path, with: .color(.white.opacity((isSelected ? 0.60 : 0.22) * op)),
                       lineWidth: isSelected ? 1.0 : 0.5)
        if isSelected {
            var glowCtx = context
            glowCtx.addFilter(.blur(radius: 7))
            glowCtx.stroke(path, with: .color(color.opacity(0.55 * op)), lineWidth: 3)
        }
    }

    /// Hub content: highlighted item's name (wrapped to two lines if needed),
    /// or a dismiss ✕ when nothing is highlighted.
    private func drawHubContent(
        context: GraphicsContext, center: CGPoint,
        radius: CGFloat, engine: SessionEngine,
        rootItems: [RadialAction], alpha: Double
    ) {
        var label: String? = nil
        let path = engine.selectionPath
        if let rootIdx = path.first, rootItems.indices.contains(rootIdx) {
            label = rootItems[rootIdx].label
            // Deepest highlighted item wins.
            for depth in stride(from: path.count - 1, through: 1, by: -1) {
                let items = engine.itemsAtDepth(depth)
                if items.indices.contains(path[depth]) {
                    label = items[path[depth]].label
                    break
                }
            }
        }

        guard let label else {
            drawHubControl(context: context, center: center, engine: engine, alpha: alpha)
            return
        }

        let maxLines = AppSettings.shared.menuLabelWrappingEnabled ? HubLabelMetrics.maximumLines : 1
        let layout = HubLabelMetrics.layout(for: RadialAction.singleLine(label),
                                            radius: radius, maxLines: maxLines)
        let lineHeight = layout.size * HubLabelMetrics.lineSpacing
        for (index, line) in layout.lines.enumerated() {
            let offset = (CGFloat(index) - CGFloat(layout.lines.count - 1) / 2) * lineHeight
            context.draw(hubText(line, size: layout.size, alpha: alpha),
                         at: CGPoint(x: center.x, y: center.y + offset))
        }
    }

    private func hubText(_ s: String, size: CGFloat, alpha: Double) -> Text {
        Text(s)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.92 * alpha))
    }

    /// The centre control, shown when nothing is highlighted:
    /// • app menu on screen → a globe, meaning "switch to the Global Menu"
    /// • switched to Global → the app's icon, meaning "switch back"
    /// • no app menu for this app → ✕, which closes the overlay
    private func drawHubControl(
        context: GraphicsContext, center: CGPoint,
        engine: SessionEngine, alpha: Double
    ) {
        guard engine.canSwitchMenus else {
            context.draw(
                Text("✕")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5 * alpha)),
                at: center
            )
            return
        }

        if !engine.showingAppMenu,
           let appPath = engine.appMenuRef?.appPath,
           let icon = AppIconCache.icon(forAppPath: appPath) {
            var iconCtx = context
            iconCtx.opacity = alpha
            iconCtx.draw(Image(nsImage: icon),
                         in: CGRect(x: center.x - 11, y: center.y - 11, width: 22, height: 22))
            return
        }

        let symbol = engine.showingAppMenu ? "globe" : "arrow.uturn.backward"
        context.draw(
            Text(Image(systemName: symbol))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.65 * alpha)),
            at: center
        )
    }

    private func pointOnCircle(_ center: CGPoint, _ radius: CGFloat, _ angle: CGFloat) -> CGPoint {
        CGPoint(x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle))
    }

    /// The item's own Finder icon — the app's, or the target file's or folder's —
    /// when it has one and the "use its own icon" toggle is on.
    private func customIcon(for item: RadialAction) -> NSImage? {
        guard !item.isSubcategory else { return nil }
        switch item.actionType {
        case .openApplication:
            guard item.actionConfig.useAppIcon ?? true,
                  let path = item.actionConfig.appPath else { return nil }
            return AppIconCache.icon(forAppPath: path)
        case .openFolder, .openFile:
            guard item.actionConfig.useFileIcon ?? true,
                  let path = item.actionConfig.targetPath else { return nil }
            return AppIconCache.icon(forFilePath: path)
        default:
            return nil
        }
    }

    /// Marks a slice that opens a deeper ring.
    ///
    /// Kept short enough to stay inside the gap before the next ring, and
    /// narrowed on thin slices so it never spills into the neighbouring gap.
    /// Returns `nil` when the slice is too thin for a legible tab.
    private func subcategoryTabHalfSpan(outerR: CGFloat, sliceAngle: CGFloat) -> CGFloat? {
        let halfSpan = min(7.0, outerR * sliceAngle * 0.22)
        return halfSpan > 1.5 ? halfSpan : nil
    }

    /// Draw an icon rotated to follow the arc at the given angle. The name is
    /// either an SF Symbol or a literal glyph (emoji, letter, CJK character),
    /// which is drawn as text so it renders instead of coming out blank.
    private func drawRotatedIcon(
        systemName: String,
        context: GraphicsContext,
        at point: CGPoint,
        angle: CGFloat,
        fontSize: CGFloat,
        opacity: Double
    ) {
        // Mirror the same logic used by drawCurvedText: icons in the upper half
        // (sin ≤ 0) point outward; icons in the lower half point inward.
        // Both branches keep rotation in [-π/2, π/2] so the icon is never upside-down.
        let rotation = sin(angle) <= 0 ? angle + .pi / 2 : angle - .pi / 2
        var iconCtx = context
        iconCtx.translateBy(x: point.x, y: point.y)
        iconCtx.rotate(by: .radians(rotation))

        let isSymbol = IconGlyph.isSymbolName(systemName)
        let glyph = isSymbol ? systemName : IconGlyph.glyph(systemName)
        // Glyphs render heavier than a symbol at the same point size, and each
        // extra character has to fit the same slice, so they are set smaller.
        let scale: CGFloat
        switch glyph.count {
        case 1:  scale = 0.9
        case 2:  scale = 0.7
        default: scale = 0.55
        }
        let content = isSymbol ? Text(Image(systemName: systemName)) : Text(glyph)
        iconCtx.draw(
            content
                .font(.system(size: isSymbol ? fontSize : fontSize * scale, weight: .medium))
                .foregroundStyle(.white.opacity(opacity)),
            at: .zero
        )
    }

    /// Draw an application's own icon rotated to follow the arc at the given angle.
    private func drawRotatedAppIcon(
        _ image: NSImage,
        context: GraphicsContext,
        at point: CGPoint,
        angle: CGFloat,
        size: CGFloat,
        opacity: Double
    ) {
        let rotation = sin(angle) <= 0 ? angle + .pi / 2 : angle - .pi / 2
        var iconCtx = context
        iconCtx.opacity = opacity
        iconCtx.translateBy(x: point.x, y: point.y)
        iconCtx.rotate(by: .radians(rotation))
        let rect = CGRect(x: -size / 2, y: -size / 2, width: size, height: size)
        iconCtx.draw(Image(nsImage: image), in: rect)
    }

    /// Draw a slice label, wrapping onto two curved lines when enabled and needed.
    private func drawCurvedLabel(
        _ text: String,
        context: GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        midAngle: CGFloat,
        fontSize: CGFloat,
        maxAngle: CGFloat,
        opacity: Double
    ) {
        // A break the user typed is a deliberate instruction, so it is honoured
        // even when automatic wrapping is switched off.
        let explicit = RadialAction.labelLines(from: text)
        if explicit.count == 2 {
            drawTwoCurvedLines(explicit[0], explicit[1], context: context, center: center,
                               radius: radius, midAngle: midAngle,
                               fontSize: fontSize, maxAngle: maxAngle, opacity: opacity)
            return
        }

        let text = explicit[0]
        let fitsOneLine = estimatedTextWidth(Array(text), size: fontSize) / radius <= maxAngle

        if AppSettings.shared.menuLabelWrappingEnabled,
           !fitsOneLine,
              let (line1, line2) = LabelMetrics.balancedLineSplit(text) {
            drawTwoCurvedLines(line1, line2, context: context, center: center,
                               radius: radius, midAngle: midAngle,
                               fontSize: fontSize, maxAngle: maxAngle, opacity: opacity)
            return
        }

        drawCurvedText(text, context: context, center: center,
                       radius: radius, midAngle: midAngle,
                       fontSize: fontSize, maxAngle: maxAngle, opacity: opacity)
    }

    /// Draws two lines straddling the label radius. Slices below the centre read
    /// the other way round, so the lines swap there to keep the first one on the
    /// side the user reads as "top".
    private func drawTwoCurvedLines(
        _ line1: String,
        _ line2: String,
        context: GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        midAngle: CGFloat,
        fontSize: CGFloat,
        maxAngle: CGFloat,
        opacity: Double
    ) {
        let flipped = sin(midAngle) > 0
        let dr = fontSize * 0.62
        let lineSize = max(8, fontSize - 1)
        drawCurvedText(flipped ? line2 : line1, context: context, center: center,
                       radius: radius + dr, midAngle: midAngle,
                       fontSize: lineSize, maxAngle: maxAngle, opacity: opacity)
        drawCurvedText(flipped ? line1 : line2, context: context, center: center,
                       radius: radius - dr, midAngle: midAngle,
                       fontSize: lineSize, maxAngle: maxAngle, opacity: opacity)
    }

    private func drawCurvedText(
        _ text: String,
        context: GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        midAngle: CGFloat,
        fontSize: CGFloat,
        maxAngle: CGFloat,
        opacity: Double
    ) {
        var chars = Array(text)
        guard !chars.isEmpty, maxAngle > 0 else { return }

        var size = LabelMetrics.fittedFontSize(chars, radius: radius,
                                               maxAngle: maxAngle, requested: fontSize)
        func arcAngle(_ chars: [Character], size: CGFloat) -> CGFloat {
            estimatedTextWidth(chars, size: size) / radius
        }
        if arcAngle(chars, size: size) > maxAngle {
            let maxUnits = maxAngle * radius / size
            let ellipsis: Character = "\u{2026}"
            let ellipsisUnits = glyphWidthUnits(ellipsis)
            var kept: [Character] = []
            var usedUnits: CGFloat = 0
            for char in chars {
                let nextUnits = glyphWidthUnits(char)
                if usedUnits + nextUnits + ellipsisUnits > maxUnits { break }
                kept.append(char)
                usedUnits += nextUnits
            }
            if kept.count < chars.count {
                chars = kept.isEmpty ? [ellipsis] : kept + [ellipsis]
            }
        }

        let totalWidth = estimatedTextWidth(chars, size: size)
        let totalAngle = totalWidth / radius
        let readsCW = sin(midAngle) <= 0
        var consumedWidth: CGFloat = 0

        for char in chars {
            let charWidth = glyphWidthUnits(char) * size
            let centerOffset = consumedWidth + charWidth / 2
            let charAngle: CGFloat
            let rotation: CGFloat

            if readsCW {
                charAngle = midAngle - totalAngle / 2 + centerOffset / radius
                rotation = charAngle + .pi / 2
            } else {
                charAngle = midAngle + totalAngle / 2 - centerOffset / radius
                rotation = charAngle - .pi / 2
            }
            consumedWidth += charWidth

            let pt = CGPoint(
                x: center.x + radius * cos(charAngle),
                y: center.y + radius * sin(charAngle)
            )

            var charCtx = context
            charCtx.translateBy(x: pt.x, y: pt.y)
            charCtx.rotate(by: .radians(rotation))
            charCtx.draw(
                Text(String(char))
                    .font(.system(size: size, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(opacity)),
                at: .zero
            )
        }
    }

    private func estimatedTextWidth(_ chars: [Character], size: CGFloat) -> CGFloat {
        LabelMetrics.textWidth(chars, size: size)
    }

    private func estimatedTextUnits(_ chars: [Character]) -> CGFloat {
        LabelMetrics.textUnits(chars)
    }

    private func glyphWidthUnits(_ char: Character) -> CGFloat {
        LabelMetrics.glyphWidthUnits(char)
    }

    private func colorFromHex(_ hex: String) -> Color {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard h.count == 6, let val = UInt64(h, radix: 16) else { return .blue }
        let r = Double((val >> 16) & 0xFF) / 255
        let g = Double((val >> 8) & 0xFF) / 255
        let b = Double(val & 0xFF) / 255
        return Color(red: r, green: g, blue: b)
    }
}

// MARK: - Label metrics

/// Text measurement for labels drawn along a curve.
///
/// Pure arithmetic, kept out of the drawing code so the spacing and
/// shrink-to-fit rules can be tested without a window.
///
/// Each character is drawn separately, centred on its own point, so these
/// widths have to cover the *ink* a glyph puts on screen rather than the font's
/// advance. Measured in the rounded semibold system font at 11pt and 18pt:
/// Latin ink peaks around 0.89 em, CJK around 0.91 em, and emoji reach 1.25 em.
enum LabelMetrics {

    /// Advance allowed for full-width glyphs, in multiples of the font size.
    ///
    /// Comfortably above the 0.91 em of ink CJK actually draws. The headroom
    /// matters because characters are spaced by arc length at the label radius
    /// while each glyph is a square centred there, so its inner edge sits where
    /// the same angle spans less arc.
    static let wideGlyphUnits: CGFloat = 1.15

    /// Advance allowed for emoji, which are far wider than any text glyph:
    /// 1.25 em of ink at 11pt against a 1.455 em advance. Treating them as
    /// ordinary characters at 0.55 made them collide with whatever followed.
    static let emojiUnits: CGFloat = 1.45

    /// Shrink-to-fit floor, as a fraction of the requested size. Bounded
    /// relative to the setting rather than at a flat 8pt so the Label Font Size
    /// control keeps real authority: wide scripts used to collapse to the floor
    /// on every slice, where now an over-long label ellipsizes instead.
    static let minimumScale: CGFloat = 0.75

    static func glyphWidthUnits(_ char: Character) -> CGFloat {
        // Emoji first: some are drawn from scalars that also fall inside the
        // full-width ranges below, and they need the wider allowance.
        if isEmoji(char) { return emojiUnits }
        if char.isWhitespace { return 0.35 }
        if char.unicodeScalars.contains(where: isWideGlyphScalar) { return wideGlyphUnits }
        if char.unicodeScalars.allSatisfy({ CharacterSet.punctuationCharacters.contains($0) }) { return 0.45 }
        return 0.55
    }

    /// Whether a character is rendered as emoji.
    ///
    /// Tests emoji *presentation* rather than `isEmoji`, which is also true of
    /// plain digits and `#`. A trailing U+FE0F is what promotes an otherwise
    /// textual symbol like ❤ or a keycap to its emoji form.
    static func isEmoji(_ char: Character) -> Bool {
        for scalar in char.unicodeScalars {
            if scalar.properties.isEmojiPresentation { return true }
            if scalar.value == 0xFE0F { return true }
        }
        return false
    }

    static func textUnits(_ chars: [Character]) -> CGFloat {
        chars.reduce(CGFloat(0)) { $0 + glyphWidthUnits($1) }
    }

    static func textWidth(_ chars: [Character], size: CGFloat) -> CGFloat {
        textUnits(chars) * size
    }

    /// Splits text onto `count` lines by repeatedly halving the widest one.
    /// Stops early when a line can no longer be divided.
    static func balancedLines(_ text: String, count: Int) -> [String] {
        var lines = [text]
        while lines.count < count {
            guard let widest = lines.indices.max(by: {
                textUnits(Array(lines[$0])) < textUnits(Array(lines[$1]))
            }), let (first, second) = balancedLineSplit(lines[widest]) else { break }
            lines.replaceSubrange(widest...widest, with: [first, second])
        }
        return lines
    }

    static func balancedLineSplit(_ text: String) -> (String, String)? {
        let chars = Array(text)
        guard chars.count >= 2 else { return nil }

        var best: (String, String)?
        var bestDifference = CGFloat.greatestFiniteMagnitude
        for index in 1..<chars.count {
            let first = String(chars[..<index]).trimmingCharacters(in: .whitespaces)
            let second = String(chars[index...]).trimmingCharacters(in: .whitespaces)
            guard !first.isEmpty, !second.isEmpty else { continue }

            let difference = abs(textUnits(Array(first)) - textUnits(Array(second)))
            if difference < bestDifference {
                bestDifference = difference
                best = (first, second)
            }
        }
        return best
    }

    /// The size the text is actually drawn at: the requested size, shrunk only
    /// as far as the floor allows when it will not fit the available arc.
    static func fittedFontSize(_ chars: [Character], radius: CGFloat,
                               maxAngle: CGFloat, requested: CGFloat) -> CGFloat {
        let units = textUnits(chars)
        guard units > 0, radius > 0 else { return requested }
        guard textWidth(chars, size: requested) / radius > maxAngle else { return requested }
        let floorSize = max(8, requested * minimumScale)
        return max(floorSize, maxAngle * radius / units)
    }

    /// The tracking a full-width glyph needs at this radius before its inner
    /// corners collide with its neighbour's. Spacing at the glyph's inner edge
    /// is compressed by `(radius - size/2) / radius`, so the advance has to be
    /// scaled up by the reciprocal to keep a full em clear.
    static func requiredWideGlyphUnits(radius: CGFloat, size: CGFloat) -> CGFloat {
        let innerRadius = radius - size / 2
        guard innerRadius > 0 else { return .greatestFiniteMagnitude }
        return radius / innerRadius
    }

    static func isWideGlyphScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x11FF,
             0x2E80...0xA4CF,
             0xAC00...0xD7AF,
             0xF900...0xFAFF,
             0xFE10...0xFE6F,
             0xFF00...0xFFEF:
            return true
        default:
            return false
        }
    }
}

// MARK: - Hub label layout

/// Text layout for the centre hub, where lines sit inside a circle rather than
/// a box: the width a line can use shrinks as it moves away from the middle.
/// Long names therefore wrap onto more lines instead of overflowing the rim.
enum HubLabelMetrics {
    static let maximumLines = 3
    static let maximumSize: CGFloat = 11
    static let minimumSize: CGFloat = 8
    /// Line pitch, in multiples of the font size.
    static let lineSpacing: CGFloat = 1.24
    /// Share of the hub radius the text may occupy, leaving a visual margin.
    static let fitFraction: CGFloat = 0.875

    /// The line breakdown and font size that best fit the hub.
    static func layout(for label: String, radius: CGFloat,
                       maxLines: Int = maximumLines) -> (lines: [String], size: CGFloat) {
        let fitRadius = radius * fitFraction
        var best: (lines: [String], size: CGFloat, overflow: CGFloat)?

        for count in 1...max(1, maxLines) {
            let lines = LabelMetrics.balancedLines(label, count: count)
            if count > 1, lines.count < count { break }

            let size = fittedSize(lines, fitRadius: fitRadius)
            let spill = overflow(lines, size: size, fitRadius: fitRadius)
            let improves = best.map { spill < $0.overflow || (spill == $0.overflow && size > $0.size) } ?? true
            if improves { best = (lines, size, spill) }
            if spill <= 0, size >= maximumSize { break }
        }

        guard let best else { return ([label], minimumSize) }
        // Wrapping alone cannot always win: one very long word, or wrapping
        // turned off, still leaves a line wider than the circle at the floor size.
        let lines = best.lines.enumerated().map { index, line in
            truncated(line, size: best.size,
                      toWidth: availableWidth(lineIndex: index, lineCount: best.lines.count,
                                              size: best.size, fitRadius: fitRadius))
        }
        return (lines, best.size)
    }

    /// Drops trailing characters until the line plus an ellipsis fits.
    static func truncated(_ line: String, size: CGFloat, toWidth width: CGFloat) -> String {
        var chars = Array(line)
        guard LabelMetrics.textWidth(chars, size: size) > width else { return line }

        let ellipsisWidth = LabelMetrics.textWidth(["\u{2026}"], size: size)
        while !chars.isEmpty {
            chars.removeLast()
            if LabelMetrics.textWidth(chars, size: size) + ellipsisWidth <= width { break }
        }
        return chars.isEmpty ? "" : String(chars) + "\u{2026}"
    }

    /// Largest size at which every line clears the circle. The usable width
    /// depends on the size itself, so this steps down until it settles.
    static func fittedSize(_ lines: [String], fitRadius: CGFloat) -> CGFloat {
        var size = maximumSize
        for _ in 0..<6 {
            var limit = maximumSize
            for (index, line) in lines.enumerated() {
                let units = LabelMetrics.textUnits(Array(line))
                guard units > 0 else { continue }
                let width = availableWidth(lineIndex: index, lineCount: lines.count,
                                           size: size, fitRadius: fitRadius)
                limit = min(limit, width / units)
            }
            let next = max(minimumSize, min(size, limit))
            if next >= size - 0.01 { return next }
            size = next
        }
        return size
    }

    /// How far the widest line sticks out past the circle, or 0 when it fits.
    static func overflow(_ lines: [String], size: CGFloat, fitRadius: CGFloat) -> CGFloat {
        var worst: CGFloat = 0
        for (index, line) in lines.enumerated() {
            let width = LabelMetrics.textWidth(Array(line), size: size)
            let available = availableWidth(lineIndex: index, lineCount: lines.count,
                                           size: size, fitRadius: fitRadius)
            worst = max(worst, width - available)
        }
        return worst
    }

    /// Chord width available to a line at its vertical offset from the centre.
    static func availableWidth(lineIndex: Int, lineCount: Int,
                               size: CGFloat, fitRadius: CGFloat) -> CGFloat {
        let offset = (CGFloat(lineIndex) - CGFloat(lineCount - 1) / 2) * size * lineSpacing
        let edge = abs(offset) + size / 2
        guard edge < fitRadius else { return 0 }
        return 2 * sqrt(fitRadius * fitRadius - edge * edge)
    }
}
