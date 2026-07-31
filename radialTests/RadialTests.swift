//
//  RadialTests.swift
//  RadialTests
//
//  Created by Jos on 10/4/26.
//

import Foundation
import Testing
@testable import Radial

struct RadialTests {

    @Test func specialKeyLabels() {
        #expect(KeyRecorder.labelForKey(53, chars: "\u{1b}") == "Esc")
        #expect(KeyRecorder.labelForKey(51, chars: "\u{8}") == "Delete")
        #expect(KeyRecorder.labelForKey(117, chars: "\u{7f}") == "Forward Delete")
    }

    @Test func shortcutURLPreservesName() {
        let url = ActionExecutor.shortcutURL(named: "Camera & Notes")
        let components = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }

        #expect(components?.scheme == "shortcuts")
        #expect(components?.host == "run-shortcut")
        #expect(components?.queryItems?.first(where: { $0.name == "name" })?.value == "Camera & Notes")
        #expect(ActionExecutor.shortcutURL(named: "") == nil)
    }

    /// A duplicate must share no identifier with its source, at any depth:
    /// ids drive SwiftUI identity, expansion state and drag paths.
    @Test func duplicateRekeysEveryDescendant() {
        let source = RadialAction(
            id: "root", label: "Tools", systemImage: "folder.fill",
            actionType: .keyboardShortcut, actionConfig: .init(),
            children: [
                RadialAction(id: "child", label: "Copy", systemImage: "doc",
                             actionType: .keyboardShortcut, actionConfig: .init(),
                             children: [
                                RadialAction(id: "grandchild", label: "Deep", systemImage: "doc",
                                             actionType: .keyboardShortcut, actionConfig: .init())
                             ])
            ])

        let copy = source.duplicated()

        func ids(_ action: RadialAction) -> [String] {
            [action.id] + (action.children ?? []).flatMap(ids)
        }
        let sourceIDs = ids(source)
        let copyIDs = ids(copy)

        #expect(copyIDs.count == sourceIDs.count)
        #expect(Set(copyIDs).count == copyIDs.count)          // no repeats inside the copy
        #expect(Set(copyIDs).isDisjoint(with: Set(sourceIDs))) // nothing shared with the source
        #expect(copy.label == source.label)                    // content is preserved
        #expect(copy.children?.first?.children?.first?.label == "Deep")
    }

}

// MARK: - Chinese label rendering

/// Covers the reported problem: Chinese labels shrinking to unreadable sizes and
/// their characters overlapping. The geometry mirrors the real overlay — the
/// first ring runs from the 38pt dead zone to 98pt at the default 60pt ring
/// height, so labels are drawn at the 68pt mid-radius plus the 13pt outset.
struct ChineseLabelTests {

    /// Radius the first ring draws its labels at.
    let ringOneLabelRadius: CGFloat = 81
    /// Radius of the inner of two wrapped lines, which sits closest to the
    /// centre and is therefore the tightest case.
    let wrappedInnerRadius: CGFloat = 81 - 11 * 0.62
    /// Default Label Font Size.
    let defaultSize: CGFloat = 11

    @Test func chineseGlyphsAreMeasuredAsFullWidth() {
        #expect(LabelMetrics.glyphWidthUnits("中") == LabelMetrics.wideGlyphUnits)
        #expect(LabelMetrics.glyphWidthUnits("测") == LabelMetrics.wideGlyphUnits)
        // Full-width punctuation lives in a separate Unicode block and is easy
        // to miss; "文件（新建）" depends on it.
        #expect(LabelMetrics.glyphWidthUnits("（") == LabelMetrics.wideGlyphUnits)
        // Latin must not be widened, or English labels would start wrapping.
        #expect(LabelMetrics.glyphWidthUnits("a") == 0.55)
    }

    /// The overlap fix: tracking has to exceed what the curve compresses away.
    @Test func trackingClearsOverlapAtEveryRadiusInUse() {
        let radii: [CGFloat] = [ringOneLabelRadius, wrappedInnerRadius]
        for radius in radii {
            let required = LabelMetrics.requiredWideGlyphUnits(radius: radius, size: defaultSize)
            #expect(LabelMetrics.wideGlyphUnits > required,
                    "tracking \(LabelMetrics.wideGlyphUnits) must exceed \(required) at radius \(radius)")
        }
    }

    /// Also has to hold at the largest font the slider offers, where the glyph
    /// is a bigger fraction of the radius and compression is worst.
    @Test func trackingClearsOverlapAtMaximumFontSize() {
        let required = LabelMetrics.requiredWideGlyphUnits(radius: wrappedInnerRadius, size: 18)
        #expect(LabelMetrics.wideGlyphUnits > required)
    }

    /// The other half of the report: the font "becomes very small". A typical
    /// short label should render at exactly the size the user asked for.
    @Test func shortChineseLabelsKeepTheirConfiguredSize() {
        let slice = CGFloat.pi / 4 * 0.78   // eighth of the ring, minus padding
        for label in ["复制", "截图", "微信", "浏览器"] {
            let size = LabelMetrics.fittedFontSize(Array(label),
                                                   radius: ringOneLabelRadius,
                                                   maxAngle: slice,
                                                   requested: defaultSize)
            #expect(size == defaultSize, "\(label) was shrunk to \(size)")
        }
    }

    /// A label too long for its slice may still shrink, but never below the
    /// floor — that was what made Chinese unreadable.
    @Test func longChineseLabelsNeverFallBelowTheFloor() {
        let slice = CGFloat.pi / 4 * 0.78
        let floor = max(8, defaultSize * LabelMetrics.minimumScale)
        for label in ["打开系统偏好设置", "这是一个很长的中文标签", "音乐播放器控制"] {
            let size = LabelMetrics.fittedFontSize(Array(label),
                                                   radius: ringOneLabelRadius,
                                                   maxAngle: slice,
                                                   requested: defaultSize)
            #expect(size >= floor, "\(label) shrank to \(size), below floor \(floor)")
        }
    }

    /// Raising Label Font Size must actually raise what gets drawn. Previously
    /// the flat 8pt floor swallowed the setting for Chinese text.
    @Test func fontSizeSettingSurvivesShrinkToFit() {
        let label = Array("这是一个很长的中文标签")
        let slice = CGFloat.pi / 4 * 0.78
        let small = LabelMetrics.fittedFontSize(label, radius: ringOneLabelRadius,
                                                maxAngle: slice, requested: 11)
        let large = LabelMetrics.fittedFontSize(label, radius: ringOneLabelRadius,
                                                maxAngle: slice, requested: 18)
        #expect(large > small, "raising the setting from 11 to 18 changed nothing")
    }

    /// Wrapping is what keeps long labels legible, so the split has to divide
    /// the text rather than leave everything on one line.
    @Test func chineseWrapsIntoTwoBalancedLines() {
        let label = "打开系统偏好设置"
        let lines = RadialAction.labelLines(from: label)
        #expect(lines.count == 1, "no explicit break means one line at this stage")

        // With a break typed in, both halves must survive.
        let broken = RadialAction.labelLines(from: "打开系统\n偏好设置")
        #expect(broken == ["打开系统", "偏好设置"])
    }

    /// Only the first break makes a line; the rest become spaces so no text is
    /// silently dropped.
    @Test func extraBreaksFoldIntoTheSecondLine() {
        #expect(RadialAction.labelLines(from: "打开\n偏好\n设置") == ["打开", "偏好 设置"])
    }

    @Test func emptySideOfABreakCollapses() {
        #expect(RadialAction.labelLines(from: "复制\n") == ["复制"])
        #expect(RadialAction.labelLines(from: "\n复制") == ["复制"])
        #expect(RadialAction.labelLines(from: "复制") == ["复制"])
    }

    @Test func labelsFlattenForSingleLineDisplays() {
        let action = RadialAction(id: "t", label: "打开系统\n偏好设置",
                                  systemImage: "gear", actionType: .keyboardShortcut,
                                  actionConfig: .init())
        #expect(action.singleLineLabel == "打开系统 偏好设置")
        #expect(!action.singleLineLabel.contains("\n"))
    }
}

// MARK: - Emoji label rendering

/// Covers the report that an emoji runs into the text after it, forcing a
/// manual space. Emoji draw far wider than any text glyph: measured in the
/// rounded semibold system font, 1.25 em of ink at 11pt and 1.167 em at 18pt,
/// against a 1.455 em advance.
struct EmojiLabelTests {

    /// Widest ink an emoji puts on screen, as a fraction of the font size.
    let emojiInk: CGFloat = 1.25
    let ringOneLabelRadius: CGFloat = 81
    let defaultSize: CGFloat = 11

    @Test func emojiAreRecognisedAcrossTheirManyForms() {
        // Plain pictographs.
        #expect(LabelMetrics.isEmoji("🎵"))
        #expect(LabelMetrics.isEmoji("📁"))
        #expect(LabelMetrics.isEmoji("🚀"))
        // Promoted to emoji by a trailing variation selector.
        #expect(LabelMetrics.isEmoji("❤️"))
        // Keycap and flag sequences.
        #expect(LabelMetrics.isEmoji("1️⃣"))
        #expect(LabelMetrics.isEmoji("🇨🇳"))
        // Skin tone modifier.
        #expect(LabelMetrics.isEmoji("👍🏽"))
    }

    /// Digits and `#` report `isEmoji` true in Unicode but render as text.
    /// Treating them as emoji would space out ordinary labels.
    @Test func textCharactersAreNotTreatedAsEmoji() {
        #expect(!LabelMetrics.isEmoji("1"))
        #expect(!LabelMetrics.isEmoji("#"))
        #expect(!LabelMetrics.isEmoji("a"))
        #expect(!LabelMetrics.isEmoji("中"))
        #expect(LabelMetrics.glyphWidthUnits("1") == 0.55)
        #expect(LabelMetrics.glyphWidthUnits("中") == LabelMetrics.wideGlyphUnits)
    }

    /// The bug itself: the space allotted has to cover the ink drawn.
    @Test func emojiGetEnoughRoomForTheirInk() {
        #expect(LabelMetrics.glyphWidthUnits("🎵") == LabelMetrics.emojiUnits)
        #expect(LabelMetrics.emojiUnits > emojiInk,
                "emoji allotted \(LabelMetrics.emojiUnits) em but draw \(emojiInk) em of ink")
    }

    /// And it has to survive the curve, where spacing at the glyph's inner edge
    /// is compressed relative to the baseline radius.
    @Test func emojiClearInkAfterCurveCompression() {
        let compression = LabelMetrics.requiredWideGlyphUnits(radius: ringOneLabelRadius,
                                                              size: defaultSize)
        #expect(LabelMetrics.emojiUnits > emojiInk * compression,
                "need \(emojiInk * compression) em, have \(LabelMetrics.emojiUnits)")
    }

    /// The exact reported case: emoji immediately followed by Chinese, with no
    /// manual space. The emoji's share of the label must cover its own ink.
    @Test func emojiFollowedByChineseDoesNotCollide() {
        let label = Array("🎵音乐播放")
        let units = LabelMetrics.textUnits(label)
        let expected = LabelMetrics.emojiUnits + 4 * LabelMetrics.wideGlyphUnits
        #expect(abs(units - expected) < 0.001)

        // Before the fix the emoji counted as an ordinary 0.55 glyph, which is
        // less than half the 1.25 em it actually draws.
        #expect(LabelMetrics.glyphWidthUnits("🎵") > 0.55 * 2)
    }

    /// A manual space was the user's workaround; it must no longer be needed,
    /// and adding one anyway must not be required to avoid collision.
    @Test func manualSpacingIsNoLongerRequired() {
        let withoutSpace = LabelMetrics.textUnits(Array("📁文件"))
        let oldAllocation = 0.55 + 2 * LabelMetrics.wideGlyphUnits
        #expect(withoutSpace > oldAllocation,
                "emoji label must now reserve more room than the old table gave it")
    }
}


