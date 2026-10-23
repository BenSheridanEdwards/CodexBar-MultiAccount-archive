import CodexBarCore
import Foundation
import Testing
@testable import CodexBarCLI

struct GrokHomeAccountCLITests {
    private static let managedID = UUID()

    private static func managedStore(
        _ accounts: [ManagedGrokAccount]? = nil) -> StubManagedGrokAccountStore
    {
        StubManagedGrokAccountStore(result: .success(ManagedGrokAccountSet(
            version: 1,
            accounts: accounts ?? [
                ManagedGrokAccount(
                    id: self.managedID,
                    email: "Added@Example.com",
                    managedHomePath: "/tmp/codexbar-grok-added",
                    createdAt: 1,
                    updatedAt: 1,
                    lastAuthenticatedAt: 1),
            ])))
    }

    private static func config(
        activeSource: GrokActiveSource? = nil,
        tokenAccounts: ProviderTokenAccountData? = nil) -> CodexBarConfig
    {
        var grok = ProviderConfig(id: .grok, tokenAccounts: tokenAccounts)
        grok.grokActiveSource = activeSource
        return CodexBarConfig(providers: [grok])
    }

    private static func resolve(
        label: String? = nil,
        index: Int? = nil,
        allAccounts: Bool = false,
        config: CodexBarConfig = Self.config(),
        store: StubManagedGrokAccountStore = Self.managedStore()) throws -> [GrokHomeCLIAccount]?
    {
        try GrokHomeAccountCLI.resolve(
            selection: TokenAccountCLISelection(label: label, index: index, allAccounts: allAccounts),
            config: config,
            baseEnvironment: ["GROK_HOME": "/tmp/exported-grok-home", "HOME": "/tmp/codexbar-grok-user"],
            store: store,
            liveEmail: { env in env["GROK_HOME"] == nil ? "system@example.com" : nil })
    }

    @Test
    func `all accounts lists System then added homes with System ignoring exported GROK_HOME`() throws {
        let accounts = try #require(try Self.resolve(allAccounts: true))

        #expect(accounts.map(\.id) == ["system", Self.managedID.uuidString.lowercased()])
        #expect(accounts.map(\.label) == ["system@example.com", "added@example.com"])
        #expect(accounts[0].homePath != "/tmp/exported-grok-home")
        #expect(accounts[0].homePath.hasSuffix("/.grok"))
        #expect(accounts[1].homePath == "/tmp/codexbar-grok-added")
        #expect(accounts.map(\.active) == [true, false])
    }

    @Test
    func `account selector matches email case-insensitively, id, or system`() throws {
        #expect(try Self.resolve(label: "ADDED@example.com")?.map(\.id) == [Self.managedID.uuidString.lowercased()])
        #expect(try Self.resolve(label: Self.managedID.uuidString)?.map(\.id) == [Self.managedID.uuidString
                .lowercased()])
        #expect(try Self.resolve(label: "system")?.map(\.id) == ["system"])
        #expect(throws: GrokHomeAccountCLIError.accountNotFound("nobody@example.com")) {
            try Self.resolve(label: "nobody@example.com")
        }
    }

    @Test
    func `plain usage follows the managed account selected in Settings`() throws {
        let selected = try Self.resolve(config: Self.config(activeSource: .managedAccount(id: Self.managedID)))
        #expect(selected?.map(\.id) == [Self.managedID.uuidString.lowercased()])
        #expect(selected?.first?.active == true)
        #expect(try Self.resolve() == nil)
        #expect(try Self.resolve(config: Self.config(activeSource: .managedAccount(id: UUID()))) == nil)
    }

    @Test
    func `pasted token accounts and index selection keep the token-account path`() throws {
        let tokens = ProviderTokenAccountData(
            version: 1,
            accounts: [ProviderTokenAccount(id: UUID(), label: "Pasted", token: "t", addedAt: 0, lastUsed: nil)],
            activeIndex: 0)
        #expect(try Self.resolve(allAccounts: true, config: Self.config(tokenAccounts: tokens)) == nil)
        #expect(try Self.resolve(label: "added@example.com", config: Self.config(tokenAccounts: tokens)) == nil)
        #expect(try Self.resolve(index: 0) == nil)
    }

    @Test
    func `without added homes the ordinary path handles every selection`() throws {
        let empty = Self.managedStore([])
        #expect(try Self.resolve(allAccounts: true, store: empty) == nil)
        #expect(try Self.resolve(label: "system", store: empty) == nil)
    }

    @Test
    func `unreadable account store fails explicit selections only`() throws {
        let unreadable = StubManagedGrokAccountStore(result: .failure(CocoaError(.fileReadCorruptFile)))
        #expect(throws: GrokHomeAccountCLIError.unreadableAccountStore) {
            try Self.resolve(allAccounts: true, store: unreadable)
        }
        #expect(try Self.resolve(store: unreadable) == nil)
    }
}

private struct StubManagedGrokAccountStore: ManagedGrokAccountStoring {
    let result: Result<ManagedGrokAccountSet, CocoaError>

    func loadAccounts() throws -> ManagedGrokAccountSet {
        try self.result.get()
    }

    func storeAccounts(_: ManagedGrokAccountSet) throws {}
}
