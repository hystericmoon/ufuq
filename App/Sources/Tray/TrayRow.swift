import AppKit
import SwiftUI
import UfuqCore
import UniformTypeIdentifiers

/// Focus id of the empty drop zone, so the keyboard can land on a tray with nothing in it.
enum TrayFocus {
    static let zoneID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
}

/// Accepts dropped files into the tray; used by the open panel and the floating tray.
struct TrayDropModifier: ViewModifier {
    @ObservedObject var tray: TrayController
    @State private var targeted = false

    func body(content: Content) -> some View {
        content
            .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
                tray.handleDrop(providers)
            }
            .onChange(of: targeted) { _, value in tray.dropTargeted = value }
    }
}

extension View {
    func trayDrop(_ tray: TrayController) -> some View { modifier(TrayDropModifier(tray: tray)) }
}

/// The row under the bento tiles: pinned folders, then the items, with a drop-zone state.
struct TrayRow: View {
    @ObservedObject var tray: TrayController
    var focus: FocusState<UUID?>.Binding
    var focusable = true

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: BentoLayout.tileRadius, style: .continuous)
        HStack(spacing: BentoLayout.gap) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(tray.pinned, id: \.self) { PinnedChip(path: $0, tray: tray) }
                    if tray.items.isEmpty {
                        emptyZone
                    } else {
                        ForEach(tray.items) { item in
                            TrayItemView(item: item, tray: tray, focus: focus, focusable: focusable)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            trailing
        }
        .padding(.horizontal, BentoLayout.tilePadding - 4)
        .frame(maxWidth: .infinity)
        .frame(height: BentoLayout.trayRowHeight)
        .background(shape.fill(Tokens.Fill.tile))
        .overlay(
            shape.strokeBorder(
                Tokens.textSecondary,
                style: StrokeStyle(lineWidth: tray.dropTargeted ? 2 : 1, dash: [4, 3]))
                .opacity(tray.items.isEmpty || tray.dragActive || tray.dropTargeted ? 1 : 0))
        .contentShape(shape)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tray")
    }

    private var emptyZone: some View {
        Text("Drop files here")
            .font(Tokens.Typography.caption)
            .foregroundStyle(Tokens.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal, 8)
            .modifier(ZoneFocus(enabled: focusable, focus: focus))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Tray, empty")
            .accessibilityHint("Drop files here, or use Add to Ufuq Tray from the Services menu")
    }

    @ViewBuilder
    private var trailing: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if let text = tray.errorText {
                Text(text)
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.stateCritical)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 140, alignment: .trailing)
                    .onTapGesture { tray.clearError() }
                    .accessibilityLabel("Error: \(text)")
            } else if let status = tray.statusText {
                Text(status)
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.accentPrayer)
                    .lineLimit(1)
                    .frame(maxWidth: 140, alignment: .trailing)
                    .accessibilityLabel(status)
            }
            HStack(spacing: 8) {
                Button("OCR") { tray.captureScreenOCR() }
                    .buttonStyle(.plain)
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.textSecondary)
                    .frame(minHeight: 28)
                    .accessibilityLabel("Capture text from screen")
                if tray.canCombineTrayToPDF {
                    Button("PDF") { tray.combineTrayToPDF() }
                        .buttonStyle(.plain)
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(Tokens.accentPrayer)
                        .frame(minHeight: 28)
                        .accessibilityLabel("Combine tray items to PDF")
                }
                if !tray.items.isEmpty {
                    Button("Clear") { tray.clear() }
                        .buttonStyle(.plain)
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(Tokens.textSecondary)
                        .frame(minHeight: 28)
                        .accessibilityLabel("Clear Tray")
                }
            }
        }
    }
}

private struct ZoneFocus: ViewModifier {
    let enabled: Bool
    var focus: FocusState<UUID?>.Binding

    func body(content: Content) -> some View {
        if enabled {
            content
                .focusable()
                .focusEffectDisabled()
                .focused(focus, equals: TrayFocus.zoneID)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Tokens.textPrimary, lineWidth: 2)
                        .opacity(focus.wrappedValue == TrayFocus.zoneID ? 1 : 0))
        } else {
            content
        }
    }
}

/// A pinned folder: one click opens it in Finder.
private struct PinnedChip: View {
    let path: String
    @ObservedObject var tray: TrayController

    var body: some View {
        let name = (path as NSString).lastPathComponent
        Button { tray.openPinned(path) } label: {
            HStack(spacing: 4) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable()
                    .frame(width: 16, height: 16)
                Text(name)
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 80)
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 28)
            .background(Capsule().fill(Tokens.Fill.tile))
        }
        .buttonStyle(.plain)
        .contextMenu { Button("Unpin Folder") { tray.unpin(path) } }
        .accessibilityLabel("Open pinned folder \(name)")
        .accessibilityAction(named: Text("Unpin Folder")) { tray.unpin(path) }
    }
}

/// One tray item: icon and name; drag it out, or use the menu, keys or VoiceOver actions.
struct TrayItemView: View {
    let item: TrayItem
    @ObservedObject var tray: TrayController
    var focus: FocusState<UUID?>.Binding
    var focusable = true
    @FocusState private var renameFocus: Bool

    var body: some View {
        let actions = TrayAction.available(for: item)
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                .resizable()
                .frame(width: 32, height: 32)
            if tray.renamingID == item.id {
                TextField("Name", text: $tray.renameText)
                    .textFieldStyle(.plain)
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.textPrimary)
                    .multilineTextAlignment(.center)
                    .focused($renameFocus)
                    .onSubmit { tray.commitRename(item) }
                    .onExitCommand { tray.cancelRename() }
                    .onAppear { renameFocus = true }
                    .accessibilityLabel("New name for \(item.name)")
            } else {
                Text(item.name)
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(width: 72, height: 60)
        .contentShape(Rectangle())
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .contextMenu {
            ForEach(actions) { action in
                Button(action.title) { tray.perform(action, on: item) }
            }
        }
        .modifier(ItemFocus(enabled: focusable, id: item.id, focus: focus))
        .onKeyPress(.return) {
            guard tray.renamingID == nil else { return .ignored }
            tray.perform(.open, on: item)
            return .handled
        }
        .onKeyPress(.delete) {
            guard tray.renamingID == nil else { return .ignored }
            moveFocusAway()
            tray.remove(item)
            return .handled
        }
        .onKeyPress(.leftArrow) { move(-1) }
        .onKeyPress(.rightArrow) { move(1) }
        .onKeyPress(characters: CharacterSet(charactersIn: "rsazpjhcdobnfRSAZPJHCDOBNF"), phases: .down) { press in
            guard tray.renamingID == nil, press.modifiers.isEmpty,
                  let character = press.characters.first,
                  let action = TrayAction.forKey(character), actions.contains(action) else { return .ignored }
            tray.perform(action, on: item)
            return .handled
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.name)
        .accessibilityValue(TrayController.spokenDetail(item))
        .accessibilityHint("Return opens. Delete removes. Drag to move it out.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { tray.perform(.open, on: item) }
        .accessibilityActions {
            ForEach(actions.filter { $0 != .open }) { action in
                Button(action.title) { tray.perform(action, on: item) }
            }
        }
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        guard tray.renamingID == nil,
              let index = tray.items.firstIndex(where: { $0.id == item.id }) else { return .ignored }
        let target = index + delta
        guard tray.items.indices.contains(target) else { return .handled }
        focus.wrappedValue = tray.items[target].id
        return .handled
    }

    /// Keeps keyboard focus in the row when the focused item goes away.
    private func moveFocusAway() {
        guard let index = tray.items.firstIndex(where: { $0.id == item.id }) else { return }
        let others = tray.items.filter { $0.id != item.id }
        if others.isEmpty {
            focus.wrappedValue = TrayFocus.zoneID
        } else {
            focus.wrappedValue = others[min(index, others.count - 1)].id
        }
    }
}

private struct ItemFocus: ViewModifier {
    let enabled: Bool
    let id: UUID
    var focus: FocusState<UUID?>.Binding

    func body(content: Content) -> some View {
        if enabled {
            content
                .focusable()
                .focusEffectDisabled()
                .focused(focus, equals: id)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Tokens.textPrimary, lineWidth: 2)
                        .opacity(focus.wrappedValue == id ? 1 : 0))
        } else {
            content
        }
    }
}
