import AppKit
import SwiftUI
import UfuqCore

struct PairingView: View {
    @ObservedObject var service: SyncService = .shared
    @AppStorage(AppSettings.syncKey) private var shareEnabled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmingForget = false

    static let forgottenMessage = "Phone forgotten. Scan the new code to pair again."

    /// Cross-fade only, so it suits Reduce Motion too; shorter when it is on.
    private var fade: Animation {
        reduceMotion ? .linear(duration: 0.15) : .easeInOut(duration: 0.35)
    }

    var body: some View {
        VStack(spacing: 16) {
            PhoneStatusRow(service: service)
            if service.phoneWasForgotten {
                Text(Self.forgottenMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
            Divider()
            if !shareEnabled {
                Text("Sharing with your phone is off.")
                Button("Turn on sharing") {
                    shareEnabled = true
                    service.apply()
                }
            } else if let payload = service.pairingPayload(), let text = try? payload.link() {
                Text("Scan with your phone's camera")
                    .font(.headline)
                Text("Ufuq opens and asks you to confirm. Or in Ufuq: Settings → Pair with your Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if let qr = QRCode.image(for: text) {
                    qr.resizable()
                        .frame(width: 240, height: 240)
                        .padding(12)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        // A new key is a new view, so the new code cross-fades in.
                        .id(service.pairingRevision)
                        .transition(.opacity)
                        .accessibilityLabel("Pairing code")
                        .accessibilityHint("Scan it with the phone's camera, or use Copy pairing code and paste it in Ufuq on the phone.")
                }
                Text("Both devices must be on the same Wi-Fi network.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Copy pairing code") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            } else {
                ProgressView("Starting…")
                    .transition(.opacity)
            }
            Divider()
            Button("Forget phone…", role: .destructive) { confirmingForget = true }
                .help("Deletes the key. Phones paired before stop receiving updates.")
                .confirmationDialog(
                    "Forget this phone? It will stop receiving updates until you pair again.",
                    isPresented: $confirmingForget,
                    titleVisibility: .visible
                ) {
                    Button("Forget phone", role: .destructive) { forget() }
                    Button("Cancel", role: .cancel) {}
                }
        }
        .controlSize(.large)
        .padding(24)
        .frame(width: 340)
        .animation(fade, value: service.pairingRevision)
        .animation(fade, value: service.isRunning)
        .animation(fade, value: service.phoneWasForgotten)
    }

    private func forget() {
        withAnimation(fade) { service.forgetPhone() }
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: Self.forgottenMessage,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ])
    }
}

/// "Paired with Samsung SM-S928B · seen 2 minutes ago", or "No phone paired yet".
/// One accessibility element; refreshes every 30 s.
struct PhoneStatusRow: View {
    @ObservedObject var service: SyncService

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let text = Self.text(phone: service.connectedPhone, lastSeen: service.lastSeen, now: context.date)
            Label(text, systemImage: "smartphone")
                .font(.callout)
                .foregroundStyle(service.hasPairedPhone ? HierarchicalShapeStyle.primary : HierarchicalShapeStyle.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(text)
        }
    }

    static func text(phone: String?, lastSeen: Date?, now: Date) -> String {
        guard let lastSeen else { return "No phone paired yet" }
        return "Paired with \(phone ?? "a phone") · seen \(seenText(lastSeen, now: now))"
    }

    static func seenText(_ date: Date, now: Date) -> String {
        if now.timeIntervalSince(date) < 60 { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

/// The "Pair phone…" menu item. Opens the pairing window and brings the menu-bar app forward.
struct PairPhoneButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Pair phone…") {
            openWindow(id: "pair-phone")
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
