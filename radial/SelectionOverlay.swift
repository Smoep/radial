import AppKit
import SwiftUI
import QuartzCore

/// Floating overlay window that shows a radial pie menu at the cursor
/// when the trackpad is engaged. Individual glass elements, macOS 26 style.
/// Supports recursive sub-category rings.
final class SelectionOverlay {

    private var window: NSWindow?
    private var hostView: NSHostingView<OverlayRadialView>?

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

            let w = NSWindow(
                contentRect: frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            w.isOpaque = false
            w.backgroundColor = .clear
            w.level = .screenSaver
            w.ignoresMouseEvents = true
            w.hasShadow = false
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

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let categories = RadialMenuStore.shared.categories
            guard !categories.isEmpty else { return }

            let selectedCat = engine.selectedCategoryIndex
            let reveal = CGFloat(engine.revealProgress)
            let startOffset = -CGFloat.pi / 2  // 12 o'clock
            let gap: CGFloat = 3

            let innerR = CGFloat(engine.ringInnerRadius(depth: 0))
            let outerR = CGFloat(engine.ringOuterRadius(depth: 0))

            // ── Center glass hub (scales in) ──
            let centerScale = min(reveal * 3, 1.0)
            let centerR = innerR * centerScale
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

            if reveal > 0.5 {
                let hintAlpha = min((Double(reveal) - 0.5) * 4, 1.0)
                drawHubContent(context: context, center: center,
                               radius: centerR, engine: engine,
                               categories: categories, alpha: hintAlpha)
            }

            let catCount = categories.count
            let catAngle = (2 * CGFloat.pi) / CGFloat(catCount)
            let gapAngle = gap / ((innerR + outerR) / 2)
            let revealAngle = reveal * 2 * CGFloat.pi

            // ── Ring 0: category slices (full 360°) ──
            for i in 0..<catCount {
                let cat = categories[i]
                let a1 = startOffset + catAngle * CGFloat(i) + gapAngle / 2
                let a2 = startOffset + catAngle * CGFloat(i + 1) - gapAngle / 2
                let isSelected = selectedCat == i

                let sliceCCWStart = catAngle * CGFloat(catCount - 1 - i)
                if sliceCCWStart >= revealAngle { continue }
                let sliceRevealFrac = min((revealAngle - sliceCCWStart) / catAngle, 1.0)
                let clippedA1 = a2 - sliceRevealFrac * (a2 - a1)
                let color = colorFromHex(cat.colorHex)

                drawGlassSlice(context: context, center: center,
                               innerR: innerR + 2, outerR: outerR - 2,
                               a1: clippedA1, a2: a2,
                               color: color, isSelected: isSelected,
                               baseOpacity: 0.55)

                guard sliceRevealFrac > 0.7 else { continue }
                let labelAlpha = min((sliceRevealFrac - 0.7) / 0.3, 1.0)
                let midA = (a1 + a2) / 2
                let labelR = (innerR + outerR) / 2
                let iconPt = pointOnCircle(center, labelR - 12, midA)

                drawRotatedIcon(
                    systemName: cat.systemImage, context: context,
                    at: iconPt, angle: midA,
                    fontSize: isSelected ? 20 : 17, opacity: labelAlpha
                )
                drawCurvedLabel(
                    cat.label, context: context, center: center,
                    radius: labelR + 16, midAngle: midA,
                    fontSize: CGFloat(AppSettings.shared.menuLabelFontSize), maxAngle: (a2 - a1) * 0.92,
                    opacity: 0.9 * labelAlpha
                )
            }

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

                // Parent determines color and center angle.
                let parentCatIdx = engine.selectionPath[0]
                let color = colorFromHex(categories[parentCatIdx].colorHex)

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
                                   baseOpacity: 0.75)

                    let isSubcat = item.isSubcategory

                    guard actRevealFrac > 0.7 else { continue }
                    let actLabelAlpha = min((actRevealFrac - 0.7) / 0.3, 1.0)
                    let midA = (a1 + a2) / 2
                    let labelR = (rInner + rOuter) / 2
                    let iconPt = pointOnCircle(center, labelR - 12, midA)

                    let iconName = isSubcat ? "folder.fill" : item.systemImage
                    if !isSubcat,
                       item.actionType == .openApplication,
                              item.actionConfig.useAppIcon ?? true,
                       let appPath = item.actionConfig.appPath,
                       let appIcon = AppIconCache.icon(forAppPath: appPath) {
                        drawRotatedAppIcon(
                            appIcon, context: context,
                            at: iconPt, angle: midA,
                            size: isSelected ? 32 : 28, opacity: actLabelAlpha
                        )
                    } else {
                        drawRotatedIcon(
                            systemName: iconName, context: context,
                            at: iconPt, angle: midA,
                            fontSize: isSelected ? 20 : 17, opacity: actLabelAlpha
                        )
                    }

                    drawCurvedLabel(
                        item.label, context: context, center: center,
                        radius: labelR + 16, midAngle: midA,
                        fontSize: CGFloat(AppSettings.shared.menuLabelFontSize), maxAngle: (a2 - a1) * 0.92,
                        opacity: (isSelected ? 1.0 : 0.8) * actLabelAlpha
                    )

                    // Subcategory: draw a chevron above the label pointing outward.
                    if isSubcat {
                        let chevronR = rOuter - 6
                        let chevronPt = pointOnCircle(center, chevronR, midA)
                        drawRotatedIcon(
                            systemName: "chevron.up", context: context,
                            at: chevronPt, angle: midA,
                            fontSize: 10, opacity: actLabelAlpha * 0.8
                        )
                    }
                }
            }
        }
    }

    // MARK: - Drawing helpers

    private func drawGlassSlice(
        context: GraphicsContext, center: CGPoint,
        innerR: CGFloat, outerR: CGFloat,
        a1: CGFloat, a2: CGFloat,
        color: Color, isSelected: Bool,
        baseOpacity: Double
    ) {
        // Selected slice pops outward slightly.
        let outR = isSelected ? outerR + 4 : outerR
        let mid = (a1 + a2) / 2
        // Overall overlay opacity: 1.0 = solid, lower = see-through.
        let op = AppSettings.shared.overlayOpacity

        var path = Path()
        path.move(to: pointOnCircle(center, innerR, a1))
        path.addArc(center: center, radius: outR,
                     startAngle: .radians(a1), endAngle: .radians(a2), clockwise: false)
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
        categories: [RadialCategory], alpha: Double
    ) {
        var label: String? = nil
        let path = engine.selectionPath
        if let catIdx = engine.selectedCategoryIndex, categories.indices.contains(catIdx) {
            label = categories[catIdx].label
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
            context.draw(
                Text("✕")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5 * alpha)),
                at: center
            )
            return
        }

        // Fit inside the hub: wrap two-word labels, shrink otherwise.
        let maxWidth = radius * 1.75
        func fontSize(for text: String) -> CGFloat {
            let fitted = maxWidth / (CGFloat(text.count) * 0.55)
            return min(11, max(8, fitted))
        }
        let words = label.split(separator: " ").map(String.init)
        let oneLineSize = fontSize(for: label)
        if words.count >= 2, CGFloat(label.count) * 0.55 * 11 > maxWidth {
            let split = (words.count + 1) / 2
            let l1 = words[0..<split].joined(separator: " ")
            let l2 = words[split...].joined(separator: " ")
            let size = min(fontSize(for: l1), fontSize(for: l2))
            context.draw(hubText(l1, size: size, alpha: alpha),
                         at: CGPoint(x: center.x, y: center.y - size * 0.62))
            context.draw(hubText(l2, size: size, alpha: alpha),
                         at: CGPoint(x: center.x, y: center.y + size * 0.62))
        } else {
            context.draw(hubText(label, size: oneLineSize, alpha: alpha), at: center)
        }
    }

    private func hubText(_ s: String, size: CGFloat, alpha: Double) -> Text {
        Text(s)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.92 * alpha))
    }

    private func pointOnCircle(_ center: CGPoint, _ radius: CGFloat, _ angle: CGFloat) -> CGPoint {
        CGPoint(x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle))
    }

    /// Draw an SF Symbol icon rotated to follow the arc at the given angle.
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
        iconCtx.draw(
            Text(Image(systemName: systemName))
                .font(.system(size: fontSize, weight: .medium))
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
        let fitsOneLine = estimatedTextWidth(Array(text), size: fontSize) / radius <= maxAngle

        if AppSettings.shared.menuLabelWrappingEnabled,
           !fitsOneLine,
           let (line1, line2) = splitLabelForWrapping(text) {
            let flipped = sin(midAngle) > 0
            let dr = fontSize * 0.62
            let lineSize = max(8, fontSize - 1)
            drawCurvedText(flipped ? line2 : line1, context: context, center: center,
                           radius: radius + dr, midAngle: midAngle,
                           fontSize: lineSize, maxAngle: maxAngle, opacity: opacity)
            drawCurvedText(flipped ? line1 : line2, context: context, center: center,
                           radius: radius - dr, midAngle: midAngle,
                           fontSize: lineSize, maxAngle: maxAngle, opacity: opacity)
            return
        }

        drawCurvedText(text, context: context, center: center,
                       radius: radius, midAngle: midAngle,
                       fontSize: fontSize, maxAngle: maxAngle, opacity: opacity)
    }

    private func splitLabelForWrapping(_ text: String) -> (String, String)? {
        let words = text.split(separator: " ").map(String.init)
        if words.count >= 2 {
            var best = (words[0], words[1...].joined(separator: " "))
            var bestDiff = abs(estimatedTextUnits(Array(best.0)) - estimatedTextUnits(Array(best.1)))
            for k in 2..<words.count {
                let line1 = words[0..<k].joined(separator: " ")
                let line2 = words[k...].joined(separator: " ")
                let diff = abs(estimatedTextUnits(Array(line1)) - estimatedTextUnits(Array(line2)))
                if diff < bestDiff { bestDiff = diff; best = (line1, line2) }
            }
            return best
        }

        let chars = Array(text)
        guard chars.count >= 2 else { return nil }
        var bestIndex = 1
        var bestDiff = CGFloat.greatestFiniteMagnitude
        for index in 1..<chars.count {
            let left = estimatedTextUnits(Array(chars[..<index]))
            let right = estimatedTextUnits(Array(chars[index...]))
            let diff = abs(left - right)
            if diff < bestDiff { bestDiff = diff; bestIndex = index }
        }
        return (String(chars[..<bestIndex]), String(chars[bestIndex...]))
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

        let minFontSize: CGFloat = 8
        func arcAngle(_ chars: [Character], size: CGFloat) -> CGFloat {
            estimatedTextWidth(chars, size: size) / radius
        }
        var size = fontSize
        let units = estimatedTextUnits(chars)
        if units > 0, arcAngle(chars, size: size) > maxAngle {
            let fitted = maxAngle * radius / units
            size = max(minFontSize, fitted)
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
        estimatedTextUnits(chars) * size
    }

    private func estimatedTextUnits(_ chars: [Character]) -> CGFloat {
        chars.reduce(CGFloat(0)) { $0 + glyphWidthUnits($1) }
    }

    private func glyphWidthUnits(_ char: Character) -> CGFloat {
        if char.isWhitespace { return 0.35 }
        if char.unicodeScalars.contains(where: isWideGlyphScalar) { return 1.0 }
        if char.unicodeScalars.allSatisfy({ CharacterSet.punctuationCharacters.contains($0) }) { return 0.45 }
        return 0.55
    }

    private func isWideGlyphScalar(_ scalar: UnicodeScalar) -> Bool {
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

    private func colorFromHex(_ hex: String) -> Color {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard h.count == 6, let val = UInt64(h, radix: 16) else { return .blue }
        let r = Double((val >> 16) & 0xFF) / 255
        let g = Double((val >> 8) & 0xFF) / 255
        let b = Double(val & 0xFF) / 255
        return Color(red: r, green: g, blue: b)
    }
}
