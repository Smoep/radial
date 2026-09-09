import AppKit
import CoreGraphics

/// Floating overlay that shows a radial countdown ring at the cursor position
/// while the candidate hold timer is running.
final class CandidateOverlay {

    private(set) var overlayWindow: NSWindow?
    private var contentView: RingView?
    private var displayLink: CVDisplayLink?
    private var startTime: CFTimeInterval = 0
    private var duration: CFTimeInterval = 0.6
    /// A short fixed delay prevents a flash during ordinary quick taps.
    private let visualDelay: CFTimeInterval = 0.15

    private let ringSize: CGFloat = 40

    func show(at screenPoint: NSPoint, duration: CFTimeInterval) {
        self.duration = duration
        self.startTime = CACurrentMediaTime()

        if overlayWindow == nil {
            let ring = RingView(frame: NSRect(x: 0, y: 0, width: ringSize, height: ringSize))
            self.contentView = ring

            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: ringSize, height: ringSize),
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
            w.contentView = ring
            self.overlayWindow = w
        }

        // Position centered on cursor. NSPoint is in bottom-left coords.
        let origin = NSPoint(
            x: screenPoint.x - ringSize / 2,
            y: screenPoint.y - ringSize / 2
        )
        overlayWindow?.setFrameOrigin(origin)
        contentView?.progress = 0
        // Don't show yet — wait for visual delay in tick().
        overlayWindow?.orderOut(nil)

        startDisplayLink()
    }

    func hide() {
        stopDisplayLink()
        overlayWindow?.orderOut(nil)
    }

    // MARK: - Display link

    private func startDisplayLink() {
        stopDisplayLink()

        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let link else { return }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(link, { _, _, _, _, _, refcon -> CVReturn in
            guard let refcon else { return kCVReturnSuccess }
            let svc = Unmanaged<CandidateOverlay>.fromOpaque(refcon).takeUnretainedValue()
            DispatchQueue.main.async { svc.tick() }
            return kCVReturnSuccess
        }, selfPtr)
        CVDisplayLinkStart(link)
        displayLink = link
    }

    private func stopDisplayLink() {
        if let link = displayLink {
            CVDisplayLinkStop(link)
        }
        displayLink = nil
    }

    private func tick() {
        let elapsed = CACurrentMediaTime() - startTime

        // Don't show until visual delay has passed.
        if elapsed < visualDelay {
            return
        }

        // Show window on first tick after delay.
        if !(overlayWindow?.isVisible ?? false) {
            overlayWindow?.orderFrontRegardless()
        }

        // Map elapsed time after delay to progress over remaining duration.
        let activeDuration = duration - visualDelay
        let progress = min((elapsed - visualDelay) / activeDuration, 1.0)
        contentView?.progress = CGFloat(progress)
        contentView?.needsDisplay = true

        if progress >= 1.0 {
            stopDisplayLink()
        }
    }
}

// MARK: - Ring drawing view

private final class RingView: NSView {
    var progress: CGFloat = 0

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius: CGFloat = min(bounds.width, bounds.height) / 2 - 4
        let lineWidth: CGFloat = 4.0

        // Background ring (dim yellow).
        ctx.setStrokeColor(NSColor.systemYellow.withAlphaComponent(0.15).cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.strokePath()

        // Progress arc (bright yellow, clockwise from 12 o'clock).
        guard progress > 0 else { return }
        let startAngle: CGFloat = .pi / 2  // 12 o'clock
        let endAngle = startAngle + (.pi * 2 * progress)  // clockwise (counter-clockwise in CG)

        ctx.setStrokeColor(NSColor.systemYellow.withAlphaComponent(0.9).cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        ctx.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        ctx.strokePath()

        // Center dot.
        let dotRadius: CGFloat = 2.5
        ctx.setFillColor(NSColor.systemYellow.withAlphaComponent(0.75).cgColor)
        ctx.fillEllipse(in: CGRect(
            x: center.x - dotRadius,
            y: center.y - dotRadius,
            width: dotRadius * 2,
            height: dotRadius * 2
        ))
    }
}
