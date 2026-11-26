import Foundation

/// Loads modules, catches their errors and reports their status.
///
/// A module that throws is marked `.unavailable` with the error text until its next successful
/// refresh; the other modules keep working. Use from one actor (the main actor in the app).
public final class ModuleRegistry {
    public enum RegistrationError: Error, Equatable {
        case duplicateID(String)
    }

    public private(set) var modules: [any UfuqModule] = []
    private var failures: [String: String] = [:]

    public init() {}

    public func register(_ module: any UfuqModule) throws {
        guard !modules.contains(where: { $0.id == module.id }) else {
            throw RegistrationError.duplicateID(module.id)
        }
        modules.append(module)
    }

    public func module(id: String) -> (any UfuqModule)? {
        modules.first { $0.id == id }
    }

    public var enabledModules: [any UfuqModule] {
        modules.filter(\.isEnabled)
    }

    /// The module's own status, overridden by `.unavailable` after a caught error.
    public func status(of id: String) -> ModuleStatus? {
        guard let module = module(id: id) else { return nil }
        if let reason = failures[id] { return .unavailable(reason: reason) }
        return module.status
    }

    /// Refreshes every enabled module. A throwing module is marked unavailable; the rest continue.
    public func refreshAll() async {
        for module in enabledModules {
            do {
                try await module.refresh()
                failures[module.id] = nil
            } catch {
                failures[module.id] = Self.describe(error)
            }
        }
    }

    /// Collapsed activities from enabled, available modules. Throwing modules are skipped and
    /// marked unavailable.
    public func activities(at now: Date) -> [LiveActivity] {
        var result: [LiveActivity] = []
        for module in enabledModules where failures[module.id] == nil && module.status.isAvailable {
            do {
                if let activity = try module.collapsedActivity(at: now) {
                    result.append(activity)
                }
            } catch {
                failures[module.id] = Self.describe(error)
            }
        }
        return result
    }

    private static func describe(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let text = localized.errorDescription {
            return text
        }
        return String(describing: error)
    }
}
