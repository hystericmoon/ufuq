import Foundation

/// Pure decisions for the updater, kept free of Sparkle so they can be unit tested.
enum UpdatePolicy {
    /// The updater runs only when a real Sparkle public key is baked into the build.
    /// Dev and CI builds have an empty `SPARKLE_PUBLIC_KEY`, so Info.plist holds "" (or, if the
    /// setting is missing, the unexpanded "$(SPARKLE_PUBLIC_KEY)").
    static func isEnabled(publicKey: String?) -> Bool {
        guard let key = publicKey?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return !key.isEmpty && !key.hasPrefix("$(")
    }

    static let disabledMessage = "Updates are off in development builds"

    /// "0.1.0 (12)"; just the version when the build number is missing or equal to it.
    static func versionString(short: String?, build: String?) -> String {
        let version = (short?.isEmpty == false) ? short! : "0"
        guard let build, !build.isEmpty, build != version else { return version }
        return "\(version) (\(build))"
    }
}
