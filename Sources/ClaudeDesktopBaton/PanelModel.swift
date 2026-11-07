import AppKit
import BatonCore
import Observation
import ServiceManagement

/// Live state behind the menu bar panel.
@MainActor @Observable
final class PanelModel {
    let claude: ClaudePaths
    let store: AccountStore
    let switcher: Switcher
    let client: UsageClient
    let usageCache: UsageCache
    let controlSocket: URL

    private(set) var accounts: [SavedAccount] = []
    private(set) var current: Identity?
    private(set) var usage: [String: UsageEntry] = [:]
    private(set) var phase: Phase = .idle
    private(set) var step: SwitchStep?
    private(set) var launchAtLogin = false
    private(set) var commandLineInstalled = false
    private(set) var now = Date()
    private var addingSince: Date?
    /// Claude's log size when it reopened signed out; any account loading after it ends adding.
    @ObservationIgnored private var addingLogOffset: UInt64?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var fetching: Set<String> = []
    @ObservationIgnored private var control: ControlServer?

    var state: PanelState { PanelState.make(accounts: accounts, current: current, usage: usage, phase: phase, now: now) }
    var isBusy: Bool { state.busy }

    init(claude: ClaudePaths = .live, paths: AppPaths = .live) {
        self.claude = claude
        store = AccountStore(paths: paths)
        switcher = Switcher(claude: claude, paths: paths, store: store, app: LiveClaude())
        client = UsageClient(userAgent: ClaudeKeychain.userAgent(claudeApp: LiveClaude.appURL), key: { try ClaudeKeychain.cookieKey() })
        usageCache = UsageCache(file: paths.usageCache)
        controlSocket = paths.controlSocket
    }

    func start() {
        store.importLegacy(from: AppPaths.legacyAccounts)
        setUpLaunchAtLogin()
        // Switches asked for on the command line are carried out here, like a click in the panel.
        control = try? ControlServer(socket: controlSocket) { [weak self] request, reply in
            Task { @MainActor in self?.handle(request, reply) }
        }
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    // MARK: refresh

    func tick() {
        now = Date()
        guard !isBusy || phase == .adding else { return }
        current = ClaudeLog.current(claude.log)
        switcher.saveCurrentIfNew()
        if phase == .adding, let offset = addingLogOffset, ClaudeLog.identity(in: claude.log, after: offset) != nil {
            phase = .idle; addingSince = nil; addingLogOffset = nil
        }
        if let since = addingSince, now.timeIntervalSince(since) > 15 * 60 { phase = .idle; addingSince = nil; addingLogOffset = nil }
        accounts = store.all()
        usage = usage.filter { id, _ in accounts.contains { $0.accountId == id } }
        refreshUsage(panelOpening: false)
    }

    func panelOpened() {
        now = Date()
        launchAtLogin = SMAppService.mainApp.status == .enabled
        commandLineInstalled = CommandLineTool.state == .installed
        refreshUsage(panelOpening: true)
    }

    private func refreshUsage(panelOpening: Bool) {
        for account in accounts where !fetching.contains(account.accountId) {
            let entry = usage[account.accountId] ?? UsageEntry()
            guard UsageSchedule.isDue(lastAttempt: entry.lastAttempt, now: now, panelOpening: panelOpening) else { continue }
            fetching.insert(account.accountId)
            usage[account.accountId, default: UsageEntry()].lastAttempt = now
            // The signed-in account uses Claude's live cookies; the others their saved copies.
            let signIn = account.accountId == current?.account ? ((try? SignInStore.read(claude)) ?? account.signIn) : account.signIn
            let id = account.accountId, org = account.orgId
            Task {
                let result = await client.usage(orgId: org, signIn: signIn)
                var entry = usage[id] ?? UsageEntry()
                switch result {
                case .success(let value):
                    entry.usage = value; entry.failure = nil; entry.checked = Date()
                    usageCache.store(id, UsageSnapshot(usage: value, fetchedAt: Date()))
                case .failure(let failure): entry.failure = failure
                }
                usage[id] = entry
                fetching.remove(id)
                if case .success = result { await fillNames(id: id, org: org, signIn: signIn) }
            }
        }
    }

    private func fillNames(id: String, org: String, signIn: SignIn) async {
        guard let saved = store.load(id), saved.email == nil || saved.orgName == nil else { return }
        let info = await client.accountInfo(orgId: org, signIn: signIn)
        guard var latest = store.load(id), info.email != nil || info.orgName != nil else { return }
        latest.email = latest.email ?? info.email
        latest.orgName = latest.orgName ?? info.orgName
        try? store.save(latest)
        accounts = store.all()
    }

    // MARK: actions

    func select(_ id: String) {
        guard !isBusy else { return }
        let decision = SwitchDecision.onSelect(id, current: current, working: switcher.workingSessions())
        guard decision != .none else { return }
        closePanel()
        if case .confirm(let working) = decision {
            guard show(Alerts.confirmSwitch(to: name(id), working: working)) == 0 else { return }
        }
        startSwitch(to: id)
    }

    /// A switch asked for on the command line: refused where the panel would ask, otherwise run as a click.
    /// The outcome goes back to the command before any alert is shown.
    private func handle(_ request: ControlRequest, _ reply: ControlReply) {
        current = ClaudeLog.current(claude.log)
        if let refusal = SwitchGate.refusal(for: request, busy: isBusy, current: current?.account,
                                            working: switcher.workingSessions(), isSaved: store.load(request.accountId) != nil) {
            reply.send(.refused(refusal))
            return
        }
        reply.send(.accepted)
        closePanel()
        startSwitch(to: request.accountId) { result in reply.send(.done(error: result.error?.message)) }
    }

    private func startSwitch(to id: String, onFinish: ((SwitchResult) -> Void)? = nil) {
        guard let target = store.load(id) else { return }
        phase = .switching(accountId: id)
        step = .quitting
        Task {
            let result = await switcher.switchTo(target) { step in
                Task { @MainActor in self.step = step }
            }
            step = nil
            phase = .idle
            usage[id]?.lastAttempt = nil
            tick()
            onFinish?(result)
            if let error = result.error {
                let previous = result.previous?.account
                let putBack = result.signInChanged ? previous.flatMap { $0 != id && store.load($0) != nil ? name($0) : nil } : nil
                if show(Alerts.switchFailed(to: name(id), message: error.message, putBack: putBack)) == 0,
                   putBack != nil, let previous {
                    startSwitch(to: previous)
                }
            } else if let aborted = result.sync?.aborted {
                show(Alerts.syncSkipped(to: name(id), reason: aborted))
            }
        }
    }

    func addAccount() {
        guard !isBusy else { return }
        closePanel()
        phase = .adding
        step = .quitting
        addingLogOffset = ClaudeLog.size(claude.log)
        Task {
            let result = await switcher.addAccount { step in
                Task { @MainActor in self.step = step }
            }
            step = nil
            if let error = result.error {
                phase = .idle
                show(AlertContent(title: "Couldn't sign Claude out", message: error.message, buttons: ["OK"]))
            } else {
                addingSince = Date()
                show(Alerts.addAccountReady)
            }
            tick()
        }
    }

    func installCommandLine() {
        closePanel()
        do {
            try CommandLineTool.install()
            commandLineInstalled = true
            show(Alerts.commandLineInstalled(onPath: CommandLineTool.isOnPath()))
        } catch {
            show(Alerts.commandLineFailed((error as? BatonError)?.message ?? error.localizedDescription))
        }
    }

    func requestRemove(_ id: String) {
        guard !isBusy else { return }
        closePanel()
        guard show(Alerts.confirmRemove(name(id))) == 0 else { return }
        try? store.remove(id)
        usage[id] = nil
        tick()
    }

    private func name(_ id: String) -> String {
        displayNames(accounts)[id] ?? "Account \(id.prefix(8))"
    }

    /// Shows an alert and returns the index of the button chosen.
    @discardableResult
    private func show(_ content: AlertContent) -> Int {
        let alert = NSAlert()
        alert.icon = AppIcon.image(size: 128)
        alert.messageText = content.title
        alert.informativeText = content.message
        content.buttons.forEach { alert.addButton(withTitle: $0) }
        NSApp.activate()
        return alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
    }

    /// Closes the menu bar panel so an alert or a restart of Claude is not hidden behind it.
    private func closePanel() {
        NSApp.windows.filter { $0.isVisible && $0.className.contains("MenuBarExtra") }.forEach { $0.orderOut(nil) }
    }

    // MARK: app

    private func setUpLaunchAtLogin() {
        let key = "didSetUpLaunchAtLogin"
        if !UserDefaults.standard.bool(forKey: key) {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: key)
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ on: Bool) {
        if on { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: "Unofficial. Not affiliated with or endorsed by Anthropic.\nSwitches Claude Desktop between saved accounts and hands Code sessions over at each switch."),
        ])
    }

    func quit() { NSApp.terminate(nil) }
}
