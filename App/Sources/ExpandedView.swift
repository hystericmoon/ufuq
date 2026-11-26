import SwiftUI
import UfuqCore

struct ExpandedView: View {
    let snapshot: PrayerSnapshot?
    let now: Date
    let topInset: CGFloat
    @Binding var selectedTab: ExpandedTab
    let focusToken: Int
    var onEscape: () -> Void = {}

    @FocusState private var keyFocus: ExpandedTab?
    @AccessibilityFocusState private var voiceOverFocus: ExpandedTab?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            tabs
            Group {
                switch selectedTab {
                case .prayer: PrayerPane(snapshot: snapshot, now: now)
                case .ai: AIPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 24)
        .padding(.top, topInset + 8)
        .padding(.bottom, 20)
        .onAppear { requestFocus() }
        .onChange(of: focusToken) { _, _ in requestFocus() }
        .onExitCommand { onEscape() }
    }

    private func requestFocus() {
        keyFocus = selectedTab
        voiceOverFocus = selectedTab
    }

    private var tabs: some View {
        HStack(spacing: 8) {
            ForEach(ExpandedTab.allCases) { tab in
                tabPill(tab)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Panels")
    }

    private func tabPill(_ tab: ExpandedTab) -> some View {
        let selected = tab == selectedTab
        let focused = keyFocus == tab
        return Text(tab.rawValue)
            .font(Tokens.Typography.collapsed)
            .foregroundStyle(selected ? Tokens.textPrimary : Tokens.textSecondary)
            .padding(.horizontal, 14)
            .frame(minHeight: 28)
            .background(Capsule().fill(selected ? Tokens.controlBg : Color.clear))
            .overlay(
                Capsule()
                    .stroke(Tokens.textPrimary, lineWidth: 2)
                    .opacity(focused ? 1 : 0))
            .contentShape(Capsule())
            .onTapGesture { selectedTab = tab }
            .focusable()
            .focusEffectDisabled()
            .focused($keyFocus, equals: tab)
            .accessibilityFocused($voiceOverFocus, equals: tab)
            .onKeyPress(keys: [.space, .return]) { _ in
                selectedTab = tab
                return .handled
            }
            .onKeyPress(.rightArrow) { move(from: tab, by: 1) }
            .onKeyPress(.leftArrow) { move(from: tab, by: -1) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tab.rawValue)
            .accessibilityValue(selected ? "selected" : "")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { selectedTab = tab }
    }

    private func move(from tab: ExpandedTab, by delta: Int) -> KeyPress.Result {
        let all = ExpandedTab.allCases
        guard let index = all.firstIndex(of: tab) else { return .ignored }
        let next = all[(index + delta + all.count) % all.count]
        selectedTab = next
        keyFocus = next
        return .handled
    }
}

private struct PrayerPane: View {
    let snapshot: PrayerSnapshot?
    let now: Date

    var body: some View {
        if let snapshot {
            HStack(alignment: .top, spacing: 24) {
                countdown(snapshot)
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 4) {
                    ForEach(snapshot.today, id: \.prayer) { slot in
                        row(slot, snapshot: snapshot)
                    }
                }
                .frame(width: 260)
            }
        } else {
            Text("Prayer times unavailable")
                .font(Tokens.Typography.collapsed)
                .foregroundStyle(Tokens.textSecondary)
        }
    }

    private func countdown(_ snapshot: PrayerSnapshot) -> some View {
        let next = snapshot.next
        let remaining = next.remaining(from: now)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Next: \(next.displayName)")
                .font(Tokens.Typography.title)
                .foregroundStyle(Tokens.textPrimary)
            Text(Self.countdownText(remaining))
                .font(Tokens.Typography.countdown)
                .monospacedDigit()
                .foregroundStyle(Tokens.accentPrayer)
            Text(snapshot.locationName)
                .font(Tokens.Typography.collapsed)
                .foregroundStyle(Tokens.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(next.displayName) in \(PrayerFormat.spoken(remaining)), \(snapshot.locationName)")
    }

    private func row(_ slot: SlotTime, snapshot: PrayerSnapshot) -> some View {
        let isNext = snapshot.nextSlot == slot.prayer
        let name = slot.prayer == .dzuhur && snapshot.date.isFriday ? "Jumat" : slot.prayer.displayName
        let time = PrayerFormat.clock(slot.time, in: snapshot.timeZone)
        return HStack {
            Text(name)
                .font(Tokens.Typography.collapsed)
                .foregroundStyle(isNext ? Tokens.accentPrayer : Tokens.textPrimary)
            if isNext {
                Text("Next")
                    .font(Tokens.Typography.collapsed)
                    .foregroundStyle(Tokens.textSecondary)
            }
            Spacer(minLength: 0)
            Text(time)
                .font(Tokens.Typography.collapsed)
                .monospacedDigit()
                .foregroundStyle(isNext ? Tokens.accentPrayer : Tokens.textSecondary)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 28)
        .background(RoundedRectangle(cornerRadius: 8).fill(isNext ? Tokens.cardBg : Color.clear))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) \(time)")
        .accessibilityValue(isNext ? "next" : "")
    }

    /// "1:05:09" or "5:09" under an hour.
    static func countdownText(_ interval: TimeInterval) -> String {
        let total = Int(max(0, interval).rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

private struct AIPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("AI usage")
                .font(Tokens.Typography.title)
                .foregroundStyle(Tokens.textPrimary)
            Text("Connect in Phase 5")
                .font(Tokens.Typography.collapsed)
                .foregroundStyle(Tokens.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}
