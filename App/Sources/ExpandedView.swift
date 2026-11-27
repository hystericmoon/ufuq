import SwiftUI
import UfuqCore

/// How the open panel's body is drawn.
enum PanelSurface {
    /// Liquid Glass on macOS 26, a dark material on 14–15; both tinted for contrast.
    case glass
    /// Solid black: Reduce Transparency, Increase Contrast, and the snapshot tests.
    case solid
}

/// The open panel, design canvas option A: the collapsed wings stay in a black strip at the notch;
/// below it Prayer and AI are tall tiles and the small tiles stack in columns of two.
struct ExpandedView: View {
    let content: BentoContent
    let layout: WingLayout
    let centerGap: CGFloat
    let stripHeight: CGFloat
    @Binding var focusedTile: BentoTileID
    let focusToken: Int
    /// Nil follows the accessibility settings.
    var surface: PanelSurface?
    var onEscape: () -> Void = {}

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @FocusState private var keyFocus: BentoTileID?
    @AccessibilityFocusState private var voiceOverFocus: BentoTileID?

    private var resolvedSurface: PanelSurface {
        if let surface { return surface }
        return reduceTransparency || contrast == .increased ? .solid : .glass
    }

    var body: some View {
        VStack(spacing: 0) {
            strip
            tiles
                .padding(BentoLayout.padding)
                .background(PanelBody(surface: resolvedSurface, bordered: contrast == .increased))
        }
        .environment(\.colorScheme, .dark)
        .onAppear { requestFocus() }
        .onChange(of: focusToken) { _, _ in requestFocus() }
        .onChange(of: keyFocus) { _, tile in if let tile { focusedTile = tile } }
        .onExitCommand { onEscape() }
    }

    /// The collapsed wings, lined up with the tiles' text below them.
    private var strip: some View {
        CollapsedView(layout: layout, centerGap: centerGap)
            .padding(.horizontal, BentoLayout.padding)
            .frame(height: stripHeight)
            .frame(maxWidth: .infinity)
            .background(Tokens.notchBg)
    }

    private var tiles: some View {
        HStack(alignment: .top, spacing: BentoLayout.gap) {
            tile(.prayer, width: BentoLayout.prayerWidth, height: BentoLayout.bodyHeight) {
                PrayerTile(snapshot: content.snapshot, now: content.now)
            }
            tile(.ai, width: BentoLayout.aiWidth, height: BentoLayout.bodyHeight) {
                AITile(rows: content.ai)
            }
            ForEach(Array(smallColumns.enumerated()), id: \.offset) { _, column in
                VStack(spacing: BentoLayout.gap) {
                    ForEach(column) { id in
                        tile(id, width: BentoLayout.smallWidth,
                             height: column.count == 1 ? BentoLayout.bodyHeight : BentoLayout.rowHeight) {
                            smallTile(id)
                        }
                    }
                }
            }
        }
    }

    private var smallColumns: [[BentoTileID]] {
        let small = content.smallTiles
        return stride(from: 0, to: small.count, by: BentoLayout.smallTilesPerColumn).map {
            Array(small[$0..<min($0 + BentoLayout.smallTilesPerColumn, small.count)])
        }
    }

    @ViewBuilder
    private func smallTile(_ id: BentoTileID) -> some View {
        switch id {
        case .battery:
            if let battery = content.battery { BatteryTile(status: battery) }
        case .prayer, .ai:
            EmptyView()
        }
    }

    private func tile<Content: View>(
        _ id: BentoTileID, width: CGFloat, height: CGFloat, @ViewBuilder content: () -> Content
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: BentoLayout.tileRadius, style: .continuous)
        return content()
            .padding(BentoLayout.tilePadding)
            .frame(width: width, height: height, alignment: .topLeading)
            .background(shape.fill(resolvedSurface == .solid ? Tokens.cardBg : Tokens.Fill.tile))
            .overlay(shape.stroke(Tokens.textPrimary, lineWidth: 2).opacity(keyFocus == id ? 1 : 0))
            .contentShape(shape)
            .focusable()
            .focusEffectDisabled()
            .focused($keyFocus, equals: id)
            .accessibilityFocused($voiceOverFocus, equals: id)
            .onKeyPress(.rightArrow) { move(from: id, by: 1) }
            .onKeyPress(.leftArrow) { move(from: id, by: -1) }
    }

    private func requestFocus() {
        let tile = content.tileOrder.contains(focusedTile) ? focusedTile : .prayer
        keyFocus = tile
        voiceOverFocus = tile
    }

    private func move(from id: BentoTileID, by delta: Int) -> KeyPress.Result {
        let order = content.tileOrder
        guard let index = order.firstIndex(of: id) else { return .ignored }
        keyFocus = order[(index + delta + order.count) % order.count]
        return .handled
    }
}

/// The body under the strip: glass (or its fallback) with the panel's bottom radius.
private struct PanelBody: View {
    let surface: PanelSurface
    let bordered: Bool

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0, bottomLeadingRadius: Tokens.Radius.expanded,
            bottomTrailingRadius: Tokens.Radius.expanded, topTrailingRadius: 0, style: .continuous)
    }

    var body: some View {
        fill.overlay(shape.stroke(Tokens.textMuted, lineWidth: bordered ? 1 : 0))
    }

    @ViewBuilder
    private var fill: some View {
        switch surface {
        case .solid:
            shape.fill(Tokens.notchBg)
        case .glass:
            #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                Color.clear.glassEffect(.regular.tint(Tokens.Fill.glassTint), in: shape)
            } else {
                material
            }
            #else
            material
            #endif
        }
    }

    /// macOS 14–15: a dark material with the same tint.
    private var material: some View {
        shape.fill(.regularMaterial).overlay(shape.fill(Tokens.Fill.glassTint))
    }
}

/// Uppercase tile heading with an optional trailing value.
private struct TileLabel: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(title.uppercased())
                .font(Tokens.Typography.tileLabel)
                .tracking(0.4)
                .foregroundStyle(Tokens.textSecondary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 4)
            if let trailing {
                Text(trailing)
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(minHeight: 16)
    }
}

// MARK: - Prayer

struct PrayerTile: View {
    let snapshot: PrayerSnapshot?
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TileLabel(title: "Prayer", trailing: snapshot?.locationName)
            if let snapshot {
                countdown(snapshot)
                Spacer(minLength: 0)
                times(snapshot)
            } else {
                Spacer(minLength: 0)
                Text("Prayer times unavailable")
                    .font(Tokens.Typography.collapsed)
                    .foregroundStyle(Tokens.textSecondary)
                Spacer(minLength: 0)
            }
        }
    }

    private func countdown(_ snapshot: PrayerSnapshot) -> some View {
        let next = snapshot.next
        let remaining = next.remaining(from: now)
        return VStack(alignment: .leading, spacing: 0) {
            Text("\(next.displayName) in")
                .font(Tokens.Typography.collapsed)
                .foregroundStyle(Tokens.accentPrayer)
            Text(Self.countdownText(remaining))
                .font(Tokens.Typography.countdown)
                .monospacedDigit()
                .foregroundStyle(Tokens.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(next.displayName) in \(PrayerFormat.spoken(remaining)), \(snapshot.locationName)")
    }

    /// Two columns, three rows: Subuh Terbit / Dzuhur Ashar / Maghrib Isya.
    private func times(_ snapshot: PrayerSnapshot) -> some View {
        let pairs = stride(from: 0, to: snapshot.today.count, by: 2).map {
            Array(snapshot.today[$0..<min($0 + 2, snapshot.today.count)])
        }
        return Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                GridRow {
                    ForEach(pair, id: \.prayer) { slot in
                        timeCell(slot, snapshot: snapshot)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Today")
    }

    private func timeCell(_ slot: SlotTime, snapshot: PrayerSnapshot) -> some View {
        let isNext = snapshot.nextSlot == slot.prayer
        let name = slot.prayer == .dzuhur && snapshot.date.isFriday ? "Jumat" : slot.prayer.displayName
        let time = PrayerFormat.clock(slot.time, in: snapshot.timeZone)
        return HStack(spacing: 4) {
            Text(name)
                .font(Tokens.Typography.caption)
                .foregroundStyle(isNext ? Tokens.accentPrayer : Tokens.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(time)
                .font(Tokens.Typography.value)
                .monospacedDigit()
                .foregroundStyle(Tokens.textPrimary)
        }
        .padding(.horizontal, 4)
        .frame(height: 20)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isNext ? Tokens.accentPrayer.opacity(0.18) : Color.clear))
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

// MARK: - AI usage

struct AITile: View {
    let rows: [AIUsageRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TileLabel(title: "AI usage")
            if rows.isEmpty {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 4) {
                    Text("No usage yet")
                        .font(Tokens.Typography.collapsed)
                        .foregroundStyle(Tokens.textPrimary)
                    Text("Claude, Codex and Antigravity limits show here.")
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(Tokens.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(rows.prefix(4)) { row in
                        AIRowView(row: row)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct AIRowView: View {
    let row: AIUsageRow

    private var percent: Int { Int((min(max(row.fraction, 0), 1) * 100).rounded(.down)) }
    private var level: UsageLevel { UsageThresholds.default.level(for: row.fraction) }

    private var ringColor: Color {
        switch level {
        case .critical: return Tokens.stateCritical
        case .warning: return Tokens.stateWarning
        default:
            switch row.provider {
            case .claude: return Tokens.providerClaude
            case .codex: return Tokens.providerCodex
            case .antigravity: return Tokens.providerAntigravity
            }
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().stroke(Tokens.Fill.track, lineWidth: 3.5)
                Circle()
                    .trim(from: 0, to: min(max(row.fraction, 0), 1))
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(percent)")
                    .font(Tokens.Typography.ring)
                    .monospacedDigit()
                    .foregroundStyle(Tokens.textPrimary)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(row.name)
                        .font(Tokens.Typography.collapsed)
                        .foregroundStyle(Tokens.textPrimary)
                        .lineLimit(1)
                    if row.isBetaSource {
                        Text("Beta source")
                            .font(Tokens.Typography.caption)
                            .foregroundStyle(Tokens.textSecondary)
                            .padding(.horizontal, 4)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Tokens.textMuted, lineWidth: 1))
                            .fixedSize()
                    }
                }
                Text(row.detail)
                    .font(Tokens.Typography.caption)
                    .monospacedDigit()
                    .foregroundStyle(level >= .warning ? ringColor : Tokens.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 36)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.name + (row.isBetaSource ? ", beta source" : ""))
        .accessibilityValue("\(percent) percent of the 5-hour limit. \(row.detail)")
    }
}

// MARK: - Battery

struct BatteryTile: View {
    let status: BatteryStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TileLabel(title: "Battery")
            Spacer(minLength: 0)
            Text("\(status.percent)%")
                .font(Tokens.Typography.title)
                .monospacedDigit()
                .foregroundStyle(Tokens.textPrimary)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Tokens.Fill.track)
                    Capsule()
                        .fill(status.percent <= 10 && !status.isPluggedIn ? Tokens.stateCritical : Tokens.textPrimary)
                        .frame(width: proxy.size.width * CGFloat(status.percent) / 100)
                }
            }
            .frame(height: 4)
            Text(status.stateText)
                .font(Tokens.Typography.caption)
                .foregroundStyle(Tokens.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery")
        .accessibilityValue("\(status.percent) percent, \(status.stateText)")
    }
}
