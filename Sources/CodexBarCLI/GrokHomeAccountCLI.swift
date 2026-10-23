import CodexBarCore
import Foundation

/// A Grok login home the CLI can fetch: the System `~/.grok` or a managed home added in Settings.
struct GrokHomeCLIAccount: Equatable, Sendable {
    static let systemID = "system"

    let id: String
    let email: String?
    let homePath: String
    let active: Bool

    var label: String {
        self.email ?? (self.id == Self.systemID ? "System" : self.id)
    }

    var cacheKey: String {
        "grok-home:\(self.id)"
    }

    var dashboardAccount: DashboardUsageAccount {
        DashboardUsageAccount(id: self.cacheKey, label: self.label, active: self.active)
    }
}

enum GrokHomeAccountCLIError: LocalizedError, Equatable {
    case accountNotFound(String)
    case unreadableAccountStore

    var errorDescription: String? {
        switch self {
        case let .accountNotFound(selector):
            "No Grok account matches '\(selector)'. Use an added account's email or id, or 'system'."
        case .unreadableAccountStore:
            "The managed Grok account list could not be read."
        }
    }
}

/// Mirrors the app's Grok account routing for `codexbar usage`: managed homes are only used when no pasted
/// SuperGrok token accounts are configured, and System is `~/.grok` regardless of an exported `GROK_HOME`,
/// matching the System row in Settings.
enum GrokHomeAccountCLI {
    /// The homes to fetch, or nil when the ordinary token-account/ambient path should handle the request.
    static func resolve(
        selection: TokenAccountCLISelection,
        config: CodexBarConfig,
        baseEnvironment: [String: String],
        store: any ManagedGrokAccountStoring = FileManagedGrokAccountStore(),
        liveEmail: ([String: String]) -> String? = Self.credentialsEmail) throws -> [GrokHomeCLIAccount]?
    {
        let providerConfig = config.providerConfig(for: UsageProvider.grok.instanceID)
        guard providerConfig?.tokenAccounts?.accounts.isEmpty ?? true else { return nil }
        guard selection.index == nil else { return nil }

        let managed: [ManagedGrokAccount]
        do {
            managed = try store.loadAccounts().accounts
        } catch {
            guard selection.allAccounts || selection.label != nil else { return nil }
            throw GrokHomeAccountCLIError.unreadableAccountStore
        }
        let persisted = providerConfig?.grokActiveSource ?? .liveSystem
        let accounts = Self.accounts(
            managed: managed,
            persisted: persisted,
            baseEnvironment: baseEnvironment,
            liveEmail: liveEmail)

        if selection.allAccounts {
            return managed.isEmpty ? nil : accounts
        }
        if let selector = selection.label?.trimmingCharacters(in: .whitespacesAndNewlines), !selector.isEmpty {
            guard !managed.isEmpty else { return nil }
            let normalized = selector.lowercased()
            if let match = accounts.first(where: {
                $0.id.lowercased() == normalized || $0.email.map(ManagedGrokAccount.normalizeEmail) == normalized
            }) {
                return [match]
            }
            throw GrokHomeAccountCLIError.accountNotFound(selector)
        }
        // No explicit selection: follow the account chosen in Settings, leaving System on the ambient path.
        guard case .managedAccount = persisted,
              let active = accounts.first(where: { $0.active && $0.id != GrokHomeCLIAccount.systemID })
        else { return nil }
        return [active]
    }

    static func accounts(
        managed: [ManagedGrokAccount],
        persisted: GrokActiveSource,
        baseEnvironment: [String: String],
        liveEmail: ([String: String]) -> String? = Self.credentialsEmail) -> [GrokHomeCLIAccount]
    {
        var liveEnvironment = baseEnvironment
        liveEnvironment.removeValue(forKey: "GROK_HOME")
        liveEnvironment.removeValue(forKey: GrokSettingsReader.oauthTokenEnvironmentKey)
        let activeManagedID: UUID? = if case let .managedAccount(id) = persisted,
                                        managed.contains(where: { $0.id == id })
        {
            id
        } else {
            nil
        }

        let system = GrokHomeCLIAccount(
            id: GrokHomeCLIAccount.systemID,
            email: liveEmail(liveEnvironment),
            homePath: GrokHomeScope.ambientHomeURL(env: liveEnvironment).path,
            active: activeManagedID == nil)
        let added = managed.compactMap { account -> GrokHomeCLIAccount? in
            guard let home = GrokHomeScope.normalizedHomePath(account.managedHomePath) else { return nil }
            return GrokHomeCLIAccount(
                id: account.id.uuidString.lowercased(),
                email: account.email,
                homePath: home,
                active: account.id == activeManagedID)
        }
        return [system] + added
    }

    static func credentialsEmail(env: [String: String]) -> String? {
        (try? GrokCredentialsStore.load(env: env))?.email
    }
}
