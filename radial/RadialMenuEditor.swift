import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Helpers

private func colorFromHex(_ hex: String) -> Color {
    let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    guard h.count == 6, let val = UInt64(h, radix: 16) else { return .blue }
    return Color(red: Double((val >> 16) & 0xFF) / 255,
                 green: Double((val >> 8) & 0xFF) / 255,
                 blue: Double(val & 0xFF) / 255)
}

extension Color {
    fileprivate func toHex() -> String {
        let nsColor: NSColor
        if let c = NSColor(self).usingColorSpace(.sRGB) {
            nsColor = c
        } else if let c = NSColor(self).usingColorSpace(.deviceRGB) {
            nsColor = c
        } else {
            return "#808080"
        }
        return String(format: "#%02X%02X%02X",
                      Int(round(nsColor.redComponent * 255)),
                      Int(round(nsColor.greenComponent * 255)),
                      Int(round(nsColor.blueComponent * 255)))
    }
}

// MARK: - Curated SF Symbol library

private struct SFSymbolGroup: Identifiable {
    let id: String
    let label: String
    let symbols: [String]
}

private let sfSymbolGroups: [SFSymbolGroup] = [
    SFSymbolGroup(id: "media", label: "Media", symbols: [
        "play.fill", "pause.fill", "playpause.fill", "stop.fill",
        "forward.fill", "backward.fill", "forward.end.fill", "backward.end.fill",
        "speaker.fill", "speaker.plus.fill", "speaker.minus.fill", "speaker.slash.fill",
        "speaker.wave.2.fill", "music.note", "music.note.list", "music.mic",
        "headphones", "airpodspro", "hifispeaker.fill", "radio.fill",
        "play.circle.fill", "pause.circle.fill", "play.rectangle.fill",
        "tv.fill", "film.fill", "camera.fill", "video.fill",
    ]),
    SFSymbolGroup(id: "apps", label: "Apps", symbols: [
        "safari.fill", "message.fill", "envelope.fill", "calendar",
        "note.text", "doc.fill", "folder.fill", "photo.fill",
        "map.fill", "phone.fill", "facetime.fill", "cart.fill",
        "terminal.fill", "hammer.fill", "wrench.fill", "gear",
        "book.fill", "newspaper.fill", "graduationcap.fill", "globe",
        "paintbrush.fill", "pencil", "scissors", "ruler.fill",
        "clock.fill", "timer", "alarm.fill", "stopwatch.fill",
    ]),
    SFSymbolGroup(id: "system", label: "System", symbols: [
        "gearshape.fill", "slider.horizontal.3", "switch.2",
        "wifi", "network", "antenna.radiowaves.left.and.right",
        "battery.100", "bolt.fill", "sun.max.fill", "moon.fill",
        "desktopcomputer", "laptopcomputer", "display", "keyboard.fill",
        "printer.fill", "externaldrive.fill", "cpu.fill", "memorychip.fill",
        "lock.fill", "lock.open.fill", "key.fill", "shield.fill",
        "eye.fill", "eye.slash.fill", "hand.raised.fill",
        "power", "restart", "sleep", "wake",
        "magnifyingglass", "camera.viewfinder", "qrcode", "barcode",
    ]),
    SFSymbolGroup(id: "windows", label: "Windows", symbols: [
        "macwindow", "macwindow.on.rectangle", "rectangle.3.group",
        "rectangle.split.2x1.fill", "rectangle.split.1x2.fill",
        "rectangle.split.2x2.fill", "rectangle.split.3x1.fill",
        "square.grid.2x2.fill", "square.grid.3x3.fill",
        "sidebar.left", "sidebar.right", "sidebar.squares.left",
        "arrow.up.left.and.arrow.down.right", "arrow.down.right.and.arrow.up.left",
        "minus.square", "xmark.square", "plus.square",
        "rectangle.portrait", "rectangle.landscape.rotate",
        "pip.fill", "uiwindow.split.2x1",
    ]),
    SFSymbolGroup(id: "arrows", label: "Arrows", symbols: [
        "arrow.up", "arrow.down", "arrow.left", "arrow.right",
        "arrow.up.circle.fill", "arrow.down.circle.fill",
        "arrow.left.circle.fill", "arrow.right.circle.fill",
        "arrow.clockwise", "arrow.counterclockwise",
        "arrow.uturn.left", "arrow.uturn.right",
        "arrow.up.arrow.down", "arrow.left.arrow.right",
        "chevron.up", "chevron.down", "chevron.left", "chevron.right",
        "arrowshape.turn.up.left.fill", "arrowshape.turn.up.right.fill",
    ]),
    SFSymbolGroup(id: "common", label: "Common", symbols: [
        "star.fill", "heart.fill", "bookmark.fill", "tag.fill",
        "bell.fill", "flag.fill", "pin.fill", "mappin",
        "house.fill", "building.fill", "building.2.fill",
        "person.fill", "person.2.fill", "person.crop.circle.fill",
        "hand.thumbsup.fill", "hand.thumbsdown.fill", "hand.wave.fill",
        "lightbulb.fill", "flashlight.on.fill", "flame.fill",
        "trash.fill", "tray.fill", "archivebox.fill",
        "paperplane.fill", "link", "paperclip", "scissors",
        "plus", "minus", "xmark", "checkmark",
        "questionmark.circle.fill", "exclamationmark.triangle.fill",
        "info.circle.fill", "bolt.circle.fill",
    ]),
]

// MARK: - SF Symbol Picker

private struct SFSymbolPicker: View {
    @Binding var selectedSymbol: String
    @State private var search = ""
    @State private var selectedGroup = "media"
    @Environment(\.dismiss) var dismiss

    private var filteredSymbols: [String] {
        let all = sfSymbolGroups.flatMap { $0.symbols }
        if search.isEmpty {
            return sfSymbolGroups.first { $0.id == selectedGroup }?.symbols ?? all
        }
        return Array(Set(all)).filter { $0.localizedCaseInsensitiveContains(search) }.sorted()
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Choose Icon").font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            TextField("Search icons…", text: $search)
                .textFieldStyle(.roundedBorder)

            if search.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(sfSymbolGroups) { group in
                            Button(group.label) { selectedGroup = group.id }
                                .font(.caption.weight(selectedGroup == group.id ? .bold : .regular))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(selectedGroup == group.id ? Color.accentColor.opacity(0.2) : Color.clear,
                                            in: Capsule())
                                .buttonStyle(.plain)
                        }
                    }
                }
            }

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(44), spacing: 6), count: 7), spacing: 6) {
                    ForEach(filteredSymbols, id: \.self) { name in
                        Button {
                            selectedSymbol = name
                        } label: {
                            Image(systemName: name)
                                .font(.system(size: 18))
                                .frame(width: 40, height: 40)
                                .background(selectedSymbol == name ? Color.accentColor.opacity(0.3) : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(name)
                    }
                }
                .padding(4)
            }
        }
        .padding(16)
        .frame(width: 380, height: 400)
    }
}

// MARK: - Key Recorder

@Observable
final class KeyRecorder {
    var isRecording = false
    private var monitor: Any?
    var onCapture: ((Int, String, Bool, Bool, Bool, Bool) -> Void)?

    func start() {
        guard !isRecording else { return }
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { // Escape cancels recording
                self.stop()
                return nil
            }
            let code = Int(event.keyCode)
            let chars = event.charactersIgnoringModifiers ?? ""
            let label = Self.labelForKey(code, chars: chars)
            self.onCapture?(
                code, label,
                event.modifierFlags.contains(.command),
                event.modifierFlags.contains(.shift),
                event.modifierFlags.contains(.option),
                event.modifierFlags.contains(.control)
            )
            self.stop()
            return nil
        }
    }

    func stop() {
        isRecording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    deinit { stop() }

    static func labelForKey(_ code: Int, chars: String) -> String {
        switch code {
        case 49: return "Space"
        case 36: return "Return"
        case 48: return "Tab"
        case 51: return "Delete"
        case 126: return "↑"
        case 125: return "↓"
        case 123: return "←"
        case 124: return "→"
        case 122: return "F1"
        case 120: return "F2"
        case 99:  return "F3"
        case 118: return "F4"
        case 96:  return "F5"
        case 97:  return "F6"
        case 98:  return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default:  return chars.isEmpty ? "Key\(code)" : chars.uppercased()
        }
    }
}

// MARK: - Edit Target

private enum EditTarget: Identifiable {
    case category(Int)
    case action(path: [Int])  // [catIdx] or [catIdx, actIdx] or [catIdx, actIdx, subIdx, ...]

    var id: String {
        switch self {
        case .category(let i):      return "cat-\(i)"
        case .action(let path):     return "act-\(path.map(String.init).joined(separator: "-"))"
        }
    }
}

// MARK: - Action Drag & Drop Model

private let radialEditorSpace = "radialEditorSpace"

private struct RowRegion: Equatable {
    let path: [Int]
    let parentPath: [Int]
    let index: Int
    let isSubcategory: Bool
    let frame: CGRect
}

private struct ContainerRegion: Equatable {
    let parentPath: [Int]
    let appendIndex: Int
    let expandId: String
    let frame: CGRect
}

private struct DropTarget: Equatable {
    let parentPath: [Int]
    let index: Int
    let intoSubcategory: Bool
}

private struct RowRegionKey: PreferenceKey {
    static let defaultValue: [RowRegion] = []
    static func reduce(value: inout [RowRegion], nextValue: () -> [RowRegion]) {
        value.append(contentsOf: nextValue())
    }
}

private struct ContainerRegionKey: PreferenceKey {
    static let defaultValue: [ContainerRegion] = []
    static func reduce(value: inout [ContainerRegion], nextValue: () -> [ContainerRegion]) {
        value.append(contentsOf: nextValue())
    }
}

@Observable
private final class ActionDragController {
    @ObservationIgnored var rowRegions: [RowRegion] = []
    @ObservationIgnored var containerRegions: [ContainerRegion] = []
    @ObservationIgnored var sourceAction: RadialAction?
    @ObservationIgnored var expand: (String) -> Void = { _ in }

    var sourcePath: [Int]?
    var pointer: CGPoint = .zero
    var target: DropTarget?

    var isDragging: Bool { sourcePath != nil }

    func begin(path: [Int], action: RadialAction, at location: CGPoint) {
        sourcePath = path
        sourceAction = action
        pointer = location
        recomputeTarget()
    }

    func update(location: CGPoint) {
        pointer = location
        recomputeTarget()
    }

    private func recomputeTarget() {
        let newTarget = computeTarget()
        // Only write (and thus notify observers / invalidate rows) when the
        // resolved target actually changes. The pointer moves every frame but
        // the drop target only changes when crossing a boundary.
        if newTarget != target { target = newTarget }
    }

    private func computeTarget() -> DropTarget? {
        guard let source = sourcePath else { return nil }
        let store = RadialMenuStore.shared
        let p = pointer

        // A) Drop *into* a subcategory when hovering the middle band of its row.
        if let row = rowRegions.first(where: { $0.frame.contains(p) }), row.isSubcategory {
            let bandHalf = row.frame.height * 0.25
            if abs(p.y - row.frame.midY) <= bandHalf,
               store.canMoveAction(from: source, toParentPath: row.path) {
                let count = store.actionAt(path: row.path)?.children?.count ?? 0
                return DropTarget(parentPath: row.path, index: count, intoSubcategory: true)
            }
        }

        // B) Determine which list (container) the pointer is over. Prefer the
        //    innermost (deepest) container so nested subcategories win.
        guard let container = containerRegions
            .filter({ $0.frame.contains(p) })
            .sorted(by: { $0.parentPath.count > $1.parentPath.count })
            .first,
            store.canMoveAction(from: source, toParentPath: container.parentPath)
        else { return nil }

        // C) Insertion index = number of sibling rows whose vertical midpoint is
        //    above the pointer. Using midpoints (instead of per-row frame
        //    containment) avoids the gaps between rows that made the indicator
        //    flicker down to the bottom when moving between the last items.
        let index = rowRegions
            .filter { $0.parentPath == container.parentPath }
            .reduce(into: 0) { count, row in if p.y > row.frame.midY { count += 1 } }
        return DropTarget(parentPath: container.parentPath, index: index, intoSubcategory: false)
    }

    func commit() {
        guard let source = sourcePath, let t = target else { reset(); return }
        let store = RadialMenuStore.shared
        let intoId: String? = t.intoSubcategory ? store.actionAt(path: t.parentPath)?.id : nil
        // Clear the visual drag state FIRST so the insertion line / preview
        // disappear instantly, then perform the (unanimated) move. Resetting
        // inside an animation made the bottom indicator fade out after release.
        reset()
        if let id = intoId { expand(id) }
        _ = store.moveAction(from: source, toParentPath: t.parentPath, insertionIndex: t.index)
    }

    func reset() {
        sourcePath = nil
        sourceAction = nil
        target = nil
    }
}

// MARK: - Radial Menu Editor

struct RadialMenuEditor: View {
    @State private var editTarget: EditTarget?
    @State private var expanded: Set<String> = []
    @State private var catDragId: String?
    @State private var catDragOffset: CGFloat = 0
    @State private var drag = ActionDragController()

    var body: some View {
        let store = RadialMenuStore.shared

        VStack(alignment: .leading, spacing: 8) {
            // ── Category list ──
            ForEach(Array(store.categories.enumerated()), id: \.element.id) { ci, cat in
                VStack(alignment: .leading, spacing: 4) {
                    // ── Category header ──
                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal")
                            .font(.callout).foregroundStyle(.tertiary)
                            .frame(width: 20)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 8)
                                    .onChanged { value in
                                        catDragId = cat.id
                                        catDragOffset = value.translation.height
                                    }
                                    .onEnded { value in
                                        defer {
                                            withAnimation(.easeOut(duration: 0.2)) {
                                                catDragId = nil; catDragOffset = 0
                                            }
                                        }
                                        guard let fromIdx = store.categories.firstIndex(where: { $0.id == cat.id }) else { return }
                                        let steps = Int(round(value.translation.height / 58))
                                        let targetIdx = max(0, min(store.categories.count - 1, fromIdx + steps))
                                        if targetIdx != fromIdx {
                                            withAnimation(.easeInOut(duration: 0.25)) {
                                                store.categories.move(
                                                    fromOffsets: IndexSet(integer: fromIdx),
                                                    toOffset: targetIdx > fromIdx ? targetIdx + 1 : targetIdx)
                                            }
                                        }
                                    }
                            )

                        Button { toggle(cat.id) } label: {
                            Image(systemName: expanded.contains(cat.id) ? "chevron.down" : "chevron.right")
                                .font(.callout.weight(.medium))
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Image(systemName: cat.systemImage)
                            .font(.title3)
                            .foregroundStyle(colorFromHex(cat.colorHex))
                            .frame(width: 24)
                        Text(cat.label)
                            .font(.body.weight(.semibold))
                        Spacer()
                        Text("\(cat.actions.count) actions")
                            .font(.caption).foregroundStyle(.secondary)

                        Button { store.categories.remove(at: ci) } label: {
                            Image(systemName: "trash")
                                .font(.callout)
                                .foregroundStyle(.red.opacity(0.6))
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Delete category")
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editTarget = .category(ci)
                    }

                    // ── Actions (when expanded) ──
                    if expanded.contains(cat.id) {
                        ActionListView(
                            actions: cat.actions,
                            path: [ci],
                            editTarget: $editTarget,
                            expanded: $expanded,
                            drag: drag,
                            indent: 26
                        )

                        HStack(spacing: 16) {
                            Button {
                                let a = RadialAction(
                                    id: UUID().uuidString,
                                    label: "New Action",
                                    systemImage: "bolt.fill",
                                    actionType: .keyboardShortcut,
                                    actionConfig: .init()
                                )
                                store.categories[ci].actions.append(a)
                                editTarget = .action(path: [ci, store.categories[ci].actions.count - 1])
                            } label: {
                                Label("Add Action", systemImage: "plus")
                                    .font(.callout)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)

                            Button {
                                let sub = RadialAction(
                                    id: UUID().uuidString,
                                    label: "New Subcategory",
                                    systemImage: "folder.fill",
                                    actionType: .keyboardShortcut,
                                    actionConfig: .init(),
                                    children: []
                                )
                                store.categories[ci].actions.append(sub)
                                let newIdx = store.categories[ci].actions.count - 1
                                expanded.insert(sub.id)
                                editTarget = .action(path: [ci, newIdx])
                            } label: {
                                Label("Add Subcategory", systemImage: "folder.badge.plus")
                                    .font(.callout)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.orange)
                        }
                        .padding(.leading, 30)
                        .padding(.top, 2)
                    }
                }
                .padding(8)
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: ContainerRegionKey.self, value: [ContainerRegion(
                            parentPath: [ci],
                            appendIndex: cat.actions.count,
                            expandId: cat.id,
                            frame: geo.frame(in: .named(radialEditorSpace))
                        )])
                    }
                )
                .overlay {
                    if drag.isDragging, drag.target?.parentPath == [ci] {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.accentColor.opacity(0.7), lineWidth: 1.5)
                    }
                }
                .offset(y: catDragId == cat.id ? catDragOffset : 0)
                .zIndex(catDragId == cat.id ? 10 : 0)
                .opacity(catDragId == cat.id ? 0.85 : 1)
                .scaleEffect(catDragId == cat.id ? 1.02 : 1)
                .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.7), value: catDragOffset)
                .animation(.easeInOut(duration: 0.15), value: catDragId)
            }

            // ── Add Category ──
            Button {
                let c = RadialCategory(
                    id: UUID().uuidString,
                    label: "New",
                    systemImage: "star.fill",
                    colorHex: "#808080",
                    actions: []
                )
                store.categories.append(c)
                expanded.insert(c.id)
                editTarget = .category(store.categories.count - 1)
            } label: {
                Label("Add Category", systemImage: "plus.circle.fill")
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
            .padding(.top, 4)
        }
        .coordinateSpace(.named(radialEditorSpace))
        .onPreferenceChange(RowRegionKey.self) { drag.rowRegions = $0 }
        .onPreferenceChange(ContainerRegionKey.self) { drag.containerRegions = $0 }
        .overlay(alignment: .topLeading) {
            FloatingDragPreview(drag: drag)
        }
        .onAppear { drag.expand = { id in expanded.insert(id) } }
        .sheet(item: $editTarget) { target in
            switch target {
            case .category(let idx):
                if idx < store.categories.count {
                    CategoryEditorSheet(catIdx: idx)
                } else {
                    EmptyView()
                }
            case .action(let path):
                if let action = RadialMenuStore.shared.actionAt(path: path) {
                    if action.isSubcategory {
                        SubcategoryEditorSheet(path: path)
                    } else {
                        ActionEditorSheet(path: path)
                    }
                } else {
                    EmptyView()
                }
            }
        }
    }

    private func toggle(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) }
        else { expanded.insert(id) }
    }
}

// MARK: - Floating Drag Preview

/// Isolated view so that reading `drag.pointer` every frame only invalidates
/// this small preview, not the entire editor body (rows + GeometryReaders).
private struct FloatingDragPreview: View {
    let drag: ActionDragController

    var body: some View {
        if drag.isDragging, let action = drag.sourceAction {
            HStack(spacing: 8) {
                Image(systemName: action.isSubcategory ? "folder.fill" : action.systemImage)
                    .foregroundStyle(action.isSubcategory ? .orange : .secondary)
                Text(action.label).font(.callout)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(0.5)))
            .shadow(radius: 6, y: 3)
            .opacity(0.95)
            .position(drag.pointer)
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Recursive Action List

private struct ActionListView: View {
    let actions: [RadialAction]
    let path: [Int]  // parent path (e.g. [catIdx] or [catIdx, actIdx])
    @Binding var editTarget: EditTarget?
    @Binding var expanded: Set<String>
    let drag: ActionDragController
    let indent: CGFloat

    var body: some View {
        let store = RadialMenuStore.shared
        ForEach(Array(actions.enumerated()), id: \.element.id) { ai, action in
            let actionPath = path + [ai]
            let isLast = ai == actions.count - 1
            let intoHighlight = drag.target?.intoSubcategory == true && drag.target?.parentPath == actionPath
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 10)).foregroundStyle(.quaternary)
                        .frame(width: 16)
                        .contentShape(Rectangle())
                        .help("Drag row to move")

                    if action.isSubcategory {
                        Button { toggleExpand(action.id) } label: {
                            Image(systemName: expanded.contains(action.id) ? "chevron.down" : "chevron.right")
                                .font(.system(size: 10, weight: .medium))
                                .frame(width: 16, height: 16)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    rowIcon(action)
                    Text(action.label)
                        .font(.callout)
                        .fontWeight(action.isSubcategory ? .medium : .regular)
                    if action.isSubcategory {
                        Text("\(action.children?.count ?? 0) items")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if !action.isSubcategory {
                        Text(shortcutBadge(action))
                            .font(.caption).foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }

                    Button {
                        store.removeAction(at: actionPath)
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(.red.opacity(0.4))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Delete")
                }
                .padding(.leading, indent)
                .padding(.vertical, 4)
                .background(intoHighlight ? Color.accentColor.opacity(0.14) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6))
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: RowRegionKey.self, value: [RowRegion(
                            path: actionPath,
                            parentPath: path,
                            index: ai,
                            isSubcategory: action.isSubcategory,
                            frame: geo.frame(in: .named(radialEditorSpace))
                        )])
                    }
                )
                .overlay(alignment: .top) {
                    if let t = drag.target, !t.intoSubcategory, t.parentPath == path, t.index == ai {
                        insertionLine
                    }
                }
                .overlay(alignment: .bottom) {
                    if isLast, let t = drag.target, !t.intoSubcategory, t.parentPath == path, t.index == ai + 1 {
                        insertionLine
                    }
                }
                .contentShape(Rectangle())
                .opacity(drag.sourcePath == actionPath ? 0.4 : 1)
                .onTapGesture {
                    editTarget = .action(path: actionPath)
                }
                .gesture(
                    DragGesture(minimumDistance: 6, coordinateSpace: .named(radialEditorSpace))
                        .onChanged { value in
                            if drag.sourcePath == nil {
                                drag.begin(path: actionPath, action: action, at: value.location)
                            } else {
                                drag.update(location: value.location)
                            }
                        }
                        .onEnded { _ in
                            drag.commit()
                        }
                )

                // Recursive children
                if action.isSubcategory && expanded.contains(action.id) {
                    ActionListView(
                        actions: action.children ?? [],
                        path: actionPath,
                        editTarget: $editTarget,
                        expanded: $expanded,
                        drag: drag,
                        indent: indent + 20
                    )

                    HStack(spacing: 16) {
                        Button {
                            let a = RadialAction(
                                id: UUID().uuidString,
                                label: "New Action",
                                systemImage: "bolt.fill",
                                actionType: .keyboardShortcut,
                                actionConfig: .init()
                            )
                            store.appendAction(a, at: actionPath)
                            if let children = store.actionAt(path: actionPath)?.children {
                                editTarget = .action(path: actionPath + [children.count - 1])
                            }
                        } label: {
                            Label("Add Action", systemImage: "plus")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)

                        Button {
                            let sub = RadialAction(
                                id: UUID().uuidString,
                                label: "New Subcategory",
                                systemImage: "folder.fill",
                                actionType: .keyboardShortcut,
                                actionConfig: .init(),
                                children: []
                            )
                            store.appendAction(sub, at: actionPath)
                            if let children = store.actionAt(path: actionPath)?.children {
                                expanded.insert(sub.id)
                                editTarget = .action(path: actionPath + [children.count - 1])
                            }
                        } label: {
                            Label("Add Subcategory", systemImage: "folder.badge.plus")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.orange)
                    }
                    .padding(.leading, indent + 24)
                    .padding(.top, 2)
                    .padding(.vertical, 4)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: ContainerRegionKey.self, value: [ContainerRegion(
                                parentPath: actionPath,
                                appendIndex: action.children?.count ?? 0,
                                expandId: action.id,
                                frame: geo.frame(in: .named(radialEditorSpace))
                            )])
                        }
                    )
                }
            }
        }
    }

    private var insertionLine: some View {
        Capsule()
            .fill(Color.accentColor)
            .frame(height: 2)
            .padding(.leading, indent)
    }

    private func toggleExpand(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) }
        else { expanded.insert(id) }
    }

    @ViewBuilder
    private func rowIcon(_ action: RadialAction) -> some View {
        if !action.isSubcategory,
           action.actionType == .openApplication,
              action.actionConfig.useAppIcon ?? true,
           let path = action.actionConfig.appPath,
           let icon = AppIconCache.icon(forAppPath: path) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 24, height: 24)
                .frame(width: 28)
        } else {
            Image(systemName: action.isSubcategory ? "folder.fill" : action.systemImage)
                .font(.body).foregroundStyle(action.isSubcategory ? .orange : .secondary)
                .frame(width: 20)
        }
    }

    private func shortcutBadge(_ action: RadialAction) -> String {
        switch action.actionType {
        case .keyboardShortcut: return action.asMapping.displayDescription
        case .openApplication: return action.actionConfig.appPath ?? ""
        case .shortcutsApp:    return action.actionConfig.shortcutName ?? "Shortcut"
        case .shellCommand:    return "Shell"
        case .mediaControl:    return action.actionConfig.mediaAction?.rawValue ?? ""
        case .automation:
            let count = action.actionConfig.automationSteps?.count ?? 0
            return count == 1 ? "1 step" : "\(count) steps"
        }
    }
}

// MARK: - Category Editor Sheet

private struct CategoryEditorSheet: View {
    let catIdx: Int
    @State private var name: String
    @State private var icon: String
    @State private var color: Color
    @State private var showIconPicker = false
    @Environment(\.dismiss) var dismiss

    init(catIdx: Int) {
        self.catIdx = catIdx
        let cat = RadialMenuStore.shared.categories[catIdx]
        _name  = State(initialValue: cat.label)
        _icon  = State(initialValue: cat.systemImage)
        _color = State(initialValue: colorFromHex(cat.colorHex))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Category").font(.headline)

            HStack {
                Text("Name").frame(width: 60, alignment: .leading)
                TextField("Category name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("Icon").frame(width: 60, alignment: .leading)
                TextField("SF Symbol name", text: $icon)
                    .textFieldStyle(.roundedBorder)
                Button { showIconPicker = true } label: {
                    Image(systemName: icon)
                        .font(.title3).frame(width: 30, height: 30)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Browse icons")
            }
            HStack {
                Text("Color").frame(width: 60, alignment: .leading)
                ColorPicker("", selection: $color, supportsOpacity: false)
                    .labelsHidden()
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save(); dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
        .sheet(isPresented: $showIconPicker) {
            SFSymbolPicker(selectedSymbol: $icon)
        }
    }

    private func save() {
        let store = RadialMenuStore.shared
        guard catIdx < store.categories.count else { return }
        store.categories[catIdx].label = name
        store.categories[catIdx].systemImage = icon
        store.categories[catIdx].colorHex = color.toHex()
    }
}

// MARK: - Action Editor Sheet

private struct ActionEditorSheet: View {
    let path: [Int]
    @State private var draft: RadialAction
    @State private var recorder = KeyRecorder()
    @State private var showIconPicker = false
    @State private var shortcutNames: [String] = []
    @State private var isLoadingShortcuts = false
    @Environment(\.dismiss) var dismiss

    init(path: [Int]) {
        self.path = path
        _draft = State(initialValue: RadialMenuStore.shared.actionAt(path: path) ?? RadialAction(
            id: UUID().uuidString, label: "?", systemImage: "questionmark", actionType: .keyboardShortcut, actionConfig: .init()))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Action").font(.headline)

            // Name
            HStack {
                Text("Name").frame(width: 70, alignment: .leading)
                TextField("Action name", text: $draft.label)
                    .textFieldStyle(.roundedBorder)
            }
            if shouldShowSymbolPicker {
                HStack {
                    Text("Icon").frame(width: 70, alignment: .leading)
                    TextField("SF Symbol", text: $draft.systemImage)
                        .textFieldStyle(.roundedBorder)
                    Button { showIconPicker = true } label: {
                        Image(systemName: draft.systemImage)
                            .font(.title3).frame(width: 30, height: 30)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help("Browse icons")
                }
            }
            // Type
            HStack {
                Text("Type").frame(width: 70, alignment: .leading)
                Picker("", selection: $draft.actionType) {
                    ForEach(ActionType.allCases, id: \.self) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .labelsHidden()
                .onChange(of: draft.actionType) { _, newType in
                    if newType == .openApplication, draft.actionConfig.useAppIcon == nil {
                        draft.actionConfig.useAppIcon = true
                    }
                    if newType == .automation, (draft.actionConfig.automationSteps ?? []).isEmpty {
                        draft.actionConfig.automationSteps = [
                            AutomationStep(actionType: .shortcutsApp, config: .init(), delayAfterMs: 1000)
                        ]
                    }
                }
            }

            Divider()

            // Type-specific configuration
            Group {
                switch draft.actionType {
                case .keyboardShortcut: keyboardConfig
                case .openApplication: appConfig
                case .shortcutsApp:    shortcutsConfig
                case .shellCommand:    shellConfig
                case .mediaControl:    mediaConfig
                case .automation:      automationConfig
                }
            }

            Spacer().frame(height: 8)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save(); dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear { loadShortcutNames() }
        .onDisappear { recorder.stop() }
        .sheet(isPresented: $showIconPicker) {
            SFSymbolPicker(selectedSymbol: $draft.systemImage)
        }
    }

    private var shouldShowSymbolPicker: Bool {
        draft.actionType != .openApplication || !(draft.actionConfig.useAppIcon ?? true)
    }

    // MARK: Keyboard config

    private var keyboardConfig: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Shortcut").frame(width: 70, alignment: .leading)
                Button {
                    recorder.onCapture = { code, label, cmd, shift, opt, ctrl in
                        draft.actionConfig.keyCode = code
                        draft.actionConfig.keyLabel = label
                        draft.actionConfig.keyChar = label.lowercased()
                        draft.actionConfig.useCommand = cmd
                        draft.actionConfig.useShift = shift
                        draft.actionConfig.useOption = opt
                        draft.actionConfig.useControl = ctrl
                    }
                    recorder.start()
                } label: {
                    Text(recorder.isRecording ? "Press any key…" : currentShortcutDisplay)
                        .foregroundStyle(recorder.isRecording ? .orange : .primary)
                }
                .font(.callout.monospaced())
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                .buttonStyle(.plain)
            }

            HStack(spacing: 12) {
                Text("Mods").frame(width: 70, alignment: .leading)
                Toggle("⌘", isOn: optBoolBinding(\.useCommand)).toggleStyle(.checkbox)
                Toggle("⇧", isOn: optBoolBinding(\.useShift)).toggleStyle(.checkbox)
                Toggle("⌥", isOn: optBoolBinding(\.useOption)).toggleStyle(.checkbox)
                Toggle("⌃", isOn: optBoolBinding(\.useControl)).toggleStyle(.checkbox)
            }
        }
    }

    private var currentShortcutDisplay: String {
        var m = ""
        if draft.actionConfig.useControl == true { m += "⌃" }
        if draft.actionConfig.useOption == true  { m += "⌥" }
        if draft.actionConfig.useShift == true   { m += "⇧" }
        if draft.actionConfig.useCommand == true { m += "⌘" }
        let key = draft.actionConfig.keyLabel ?? draft.actionConfig.keyChar?.uppercased() ?? ""
        return key.isEmpty ? "Click to record" : m + key
    }

    private func optBoolBinding(_ kp: WritableKeyPath<RadialAction.ActionConfig, Bool?>) -> Binding<Bool> {
        Binding(
            get: { draft.actionConfig[keyPath: kp] ?? false },
            set: { draft.actionConfig[keyPath: kp] = $0 }
        )
    }

    // MARK: App config

    private var appConfig: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("App").frame(width: 70, alignment: .leading)
                Text(draft.actionConfig.appPath ?? "No app selected")
                    .font(.callout)
                    .foregroundStyle(draft.actionConfig.appPath == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Browse…") {
                    let panel = NSOpenPanel()
                    panel.title = "Choose Application"
                    panel.allowedContentTypes = [.application]
                    panel.directoryURL = URL(fileURLWithPath: "/Applications")
                    panel.allowsMultipleSelection = false
                    panel.canChooseDirectories = false
                    panel.canChooseFiles = true
                    if panel.runModal() == .OK, let url = panel.url {
                        draft.actionConfig.appPath = url.path
                        // Auto-fill label from app name if still default
                        if draft.label == "New Action" {
                            draft.label = url.deletingPathExtension().lastPathComponent
                        }
                    }
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 8) {
                Spacer().frame(width: 70)
                Toggle("Use app's own icon", isOn: Binding(
                    get: { draft.actionConfig.useAppIcon ?? true },
                    set: { draft.actionConfig.useAppIcon = $0 }
                ))
                .disabled(draft.actionConfig.appPath == nil)
                Spacer()
                if draft.actionConfig.useAppIcon ?? true,
                   let path = draft.actionConfig.appPath,
                   let icon = AppIconCache.icon(forAppPath: path) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 30, height: 30)
                }
            }
        }
    }

    // MARK: Shortcuts config

    private var shortcutsConfig: some View {
        HStack {
            Text("Shortcut").frame(width: 70, alignment: .leading)
            Picker("", selection: Binding(
                get: { draft.actionConfig.shortcutName ?? "" },
                set: { name in
                    draft.actionConfig.shortcutName = name
                    if !name.isEmpty, draft.label == "New Action" || draft.label == "?" {
                        draft.label = name
                    }
                }
            )) {
                Text(isLoadingShortcuts ? "Loading…" : "Select Shortcut").tag("")
                ForEach(shortcutPickerOptions, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)

            Button("Refresh") { loadShortcutNames(force: true) }
                .disabled(isLoadingShortcuts)
        }
    }

    private var shortcutPickerOptions: [String] {
        let current = draft.actionConfig.shortcutName ?? ""
        if current.isEmpty || shortcutNames.contains(current) { return shortcutNames }
        return [current] + shortcutNames
    }

    private func loadShortcutNames(force: Bool = false) {
        guard force || shortcutNames.isEmpty else { return }
        guard !isLoadingShortcuts else { return }
        isLoadingShortcuts = true
        Task {
            let names = await Self.fetchShortcutNames()
            await MainActor.run {
                shortcutNames = names
                isLoadingShortcuts = false
            }
        }
    }

    private static func fetchShortcutNames() async -> [String] {
        await Task.detached {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["list"]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { return [] }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard let output = String(data: data, encoding: .utf8) else { return [] }
                return output
                    .split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            } catch {
                return []
            }
        }.value
    }

    // MARK: Shell config

    private var shellConfig: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Command")
            TextEditor(text: Binding(
                get: { draft.actionConfig.shellCommand ?? "" },
                set: { draft.actionConfig.shellCommand = $0 }
            ))
            .font(.system(.caption, design: .monospaced))
            .frame(height: 60)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
        }
    }

    // MARK: Media config

    private var mediaConfig: some View {
        HStack {
            Text("Action").frame(width: 70, alignment: .leading)
            Picker("", selection: Binding(
                get: { draft.actionConfig.mediaAction ?? .playPause },
                set: { draft.actionConfig.mediaAction = $0 }
            )) {
                ForEach(MediaActionType.allCases, id: \.self) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .labelsHidden()
        }
    }

    // MARK: Automation config

    private var automationConfig: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Runs each step in order, waiting the set delay before the next.")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            let steps = draft.actionConfig.automationSteps ?? []
            if steps.isEmpty {
                Text("No steps yet — add one below.")
                    .font(.callout).foregroundStyle(.tertiary)
            }
            ForEach(Array(steps.enumerated()), id: \.element.id) { idx, _ in
                AutomationStepEditor(
                    index: idx,
                    step: stepBinding(idx),
                    isLast: idx == steps.count - 1,
                    shortcutNames: shortcutNames,
                    isLoadingShortcuts: isLoadingShortcuts,
                    onRefreshShortcuts: { loadShortcutNames(force: true) },
                    onDelete: { deleteStep(idx) }
                )
            }

            Button { addStep() } label: {
                Label("Add Step", systemImage: "plus.circle.fill").font(.callout)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
        }
    }

    private func stepBinding(_ index: Int) -> Binding<AutomationStep> {
        Binding(
            get: {
                let steps = draft.actionConfig.automationSteps ?? []
                return index < steps.count
                    ? steps[index]
                    : AutomationStep(actionType: .shortcutsApp, config: .init())
            },
            set: { newValue in
                var steps = draft.actionConfig.automationSteps ?? []
                guard index < steps.count else { return }
                steps[index] = newValue
                draft.actionConfig.automationSteps = steps
            }
        )
    }

    private func addStep() {
        var steps = draft.actionConfig.automationSteps ?? []
        steps.append(AutomationStep(actionType: .shortcutsApp, config: .init(), delayAfterMs: 1000))
        draft.actionConfig.automationSteps = steps
    }

    private func deleteStep(_ index: Int) {
        var steps = draft.actionConfig.automationSteps ?? []
        guard index < steps.count else { return }
        steps.remove(at: index)
        draft.actionConfig.automationSteps = steps
    }

    private func save() {
        let store = RadialMenuStore.shared
        guard store.actionAt(path: path) != nil else { return }
        // Preserve existing children when saving edits.
        if let existing = store.actionAt(path: path) {
            draft.children = existing.children
        }
        store.setAction(draft, at: path)
    }
}

// MARK: - Automation Step Editor

private struct AutomationStepEditor: View {
    let index: Int
    @Binding var step: AutomationStep
    let isLast: Bool
    let shortcutNames: [String]
    let isLoadingShortcuts: Bool
    let onRefreshShortcuts: () -> Void
    let onDelete: () -> Void

    @State private var recorder = KeyRecorder()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Step \(index + 1)").font(.callout.weight(.semibold))
                Spacer()
                Picker("", selection: $step.actionType) {
                    ForEach(ActionType.allCases.filter { $0 != .automation }, id: \.self) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 170)
                Button { onDelete() } label: {
                    Image(systemName: "trash").foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Remove step")
            }

            Group {
                switch step.actionType {
                case .keyboardShortcut: keyboardStep
                case .openApplication:  appStep
                case .shortcutsApp:     shortcutStep
                case .shellCommand:     shellStep
                case .mediaControl:     mediaStep
                case .automation:       EmptyView()
                }
            }

            if !isLast {
                HStack(spacing: 8) {
                    Text("Delay").frame(width: 50, alignment: .leading).font(.callout)
                    Slider(value: Binding(
                        get: { Double(step.delayAfterMs) },
                        set: { step.delayAfterMs = Int($0) }
                    ), in: 0...20000, step: 50)
                    Text(String(format: "%.2f s", Double(step.delayAfterMs) / 1000))
                        .font(.caption.monospacedDigit())
                        .frame(width: 54, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
        .onDisappear { recorder.stop() }
    }

    // MARK: Per-type step editors

    private var keyboardStep: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                recorder.onCapture = { code, label, cmd, shift, opt, ctrl in
                    step.config.keyCode = code
                    step.config.keyLabel = label
                    step.config.keyChar = label.lowercased()
                    step.config.useCommand = cmd
                    step.config.useShift = shift
                    step.config.useOption = opt
                    step.config.useControl = ctrl
                }
                recorder.start()
            } label: {
                Text(recorder.isRecording ? "Press any key…" : shortcutDisplay)
                    .foregroundStyle(recorder.isRecording ? .orange : .primary)
            }
            .font(.callout.monospaced())
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            .buttonStyle(.plain)

            HStack(spacing: 12) {
                Toggle("⌘", isOn: cfgBool(\.useCommand)).toggleStyle(.checkbox)
                Toggle("⇧", isOn: cfgBool(\.useShift)).toggleStyle(.checkbox)
                Toggle("⌥", isOn: cfgBool(\.useOption)).toggleStyle(.checkbox)
                Toggle("⌃", isOn: cfgBool(\.useControl)).toggleStyle(.checkbox)
            }
        }
    }

    private var appStep: some View {
        HStack {
            Text(step.config.appPath ?? "No app selected")
                .font(.caption)
                .foregroundStyle(step.config.appPath == nil ? .secondary : .primary)
                .lineLimit(1).truncationMode(.middle)
            Spacer()
            Button("Browse…") {
                let panel = NSOpenPanel()
                panel.title = "Choose Application"
                panel.allowedContentTypes = [.application]
                panel.directoryURL = URL(fileURLWithPath: "/Applications")
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories = false
                if panel.runModal() == .OK, let url = panel.url {
                    step.config.appPath = url.path
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private var shortcutStep: some View {
        HStack {
            Picker("", selection: Binding(
                get: { step.config.shortcutName ?? "" },
                set: { step.config.shortcutName = $0 }
            )) {
                Text(isLoadingShortcuts ? "Loading…" : "Select Shortcut").tag("")
                ForEach(shortcutOptions, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
            Button("Refresh") { onRefreshShortcuts() }
                .disabled(isLoadingShortcuts)
        }
    }

    private var shellStep: some View {
        TextEditor(text: Binding(
            get: { step.config.shellCommand ?? "" },
            set: { step.config.shellCommand = $0 }
        ))
        .font(.system(.caption, design: .monospaced))
        .frame(height: 44)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
    }

    private var mediaStep: some View {
        HStack {
            Text("Action").frame(width: 60, alignment: .leading).font(.callout)
            Picker("", selection: Binding(
                get: { step.config.mediaAction ?? .playPause },
                set: { step.config.mediaAction = $0 }
            )) {
                ForEach(MediaActionType.allCases, id: \.self) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .labelsHidden()
        }
    }

    // MARK: Helpers

    private var shortcutOptions: [String] {
        let current = step.config.shortcutName ?? ""
        if current.isEmpty || shortcutNames.contains(current) { return shortcutNames }
        return [current] + shortcutNames
    }

    private var shortcutDisplay: String {
        var m = ""
        if step.config.useControl == true { m += "⌃" }
        if step.config.useOption == true  { m += "⌥" }
        if step.config.useShift == true   { m += "⇧" }
        if step.config.useCommand == true { m += "⌘" }
        let key = step.config.keyLabel ?? step.config.keyChar?.uppercased() ?? ""
        return key.isEmpty ? "Click to record" : m + key
    }

    private func cfgBool(_ kp: WritableKeyPath<RadialAction.ActionConfig, Bool?>) -> Binding<Bool> {
        Binding(
            get: { step.config[keyPath: kp] ?? false },
            set: { step.config[keyPath: kp] = $0 }
        )
    }
}

// MARK: - Subcategory Editor Sheet

private struct SubcategoryEditorSheet: View {
    let path: [Int]
    @State private var name: String
    @State private var icon: String
    @State private var showIconPicker = false
    @Environment(\.dismiss) var dismiss

    init(path: [Int]) {
        self.path = path
        let action = RadialMenuStore.shared.actionAt(path: path)
        _name = State(initialValue: action?.label ?? "")
        _icon = State(initialValue: action?.systemImage ?? "folder.fill")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Subcategory").font(.headline)

            HStack {
                Text("Name").frame(width: 60, alignment: .leading)
                TextField("Subcategory name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("Icon").frame(width: 60, alignment: .leading)
                TextField("SF Symbol name", text: $icon)
                    .textFieldStyle(.roundedBorder)
                Button { showIconPicker = true } label: {
                    Image(systemName: icon)
                        .font(.title3).frame(width: 30, height: 30)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Browse icons")
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save(); dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
        .sheet(isPresented: $showIconPicker) {
            SFSymbolPicker(selectedSymbol: $icon)
        }
    }

    private func save() {
        let store = RadialMenuStore.shared
        guard var action = store.actionAt(path: path) else { return }
        action.label = name
        action.systemImage = icon
        store.setAction(action, at: path)
    }
}

