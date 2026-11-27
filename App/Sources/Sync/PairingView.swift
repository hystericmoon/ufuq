import AppKit
import SwiftUI
import UfuqCore

struct PairingView: View {
    @ObservedObject var service: SyncService = .shared
    @AppStorage(AppSettings.syncKey) private var shareEnabled = false

    var body: some View {
        VStack(spacing: 16) {
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
            }
            Divider()
            Button("Forget phone", role: .destructive) { service.forgetPhone() }
                .help("Deletes the key. Phones paired before stop receiving updates.")
        }
        .padding(24)
        .frame(width: 340)
        .id(service.pairingRevision)
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
