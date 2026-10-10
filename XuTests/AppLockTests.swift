import Foundation
import Testing
@testable import Xu

private struct FakeAuthenticator: Authenticating {
    var available = true
    var succeeds = true
    var method: AuthMethod { .faceID }
    func isAvailable() -> Bool { available }
    func authenticate(reason: String) async -> Bool { succeeds }
}

@MainActor
struct AppLockTests {
    private func suite() -> UserDefaults {
        let name = "AppLockTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func startsUnlockedAndNeverCoversWhenDisabled() {
        let lock = AppLock(defaults: suite(), authenticator: FakeAuthenticator())
        #expect(!lock.isEnabled && !lock.isLocked && !lock.shouldCover)
        lock.scenePhaseChanged(.background)
        #expect(!lock.isLocked)
        lock.scenePhaseChanged(.inactive)
        #expect(!lock.shouldCover)
    }

    @Test func enablingRequiresSuccessfulAuthentication() async {
        let defaults = suite()
        let failing = AppLock(defaults: defaults, authenticator: FakeAuthenticator(succeeds: false))
        #expect(await failing.setEnabled(true) == false)
        #expect(!failing.isEnabled)

        let lock = AppLock(defaults: defaults, authenticator: FakeAuthenticator())
        #expect(await lock.setEnabled(true))
        #expect(lock.isEnabled && !lock.isLocked)       // vừa bật xong thì đang mở
        #expect(defaults.bool(forKey: SettingsKey.lockEnabled))
    }

    @Test func cannotEnableWithoutPasscodeOrBiometrics() async {
        let lock = AppLock(defaults: suite(), authenticator: FakeAuthenticator(available: false))
        #expect(!lock.canEnable)
        #expect(await lock.setEnabled(true) == false)
        #expect(!lock.isEnabled)
    }

    @Test func launchesLockedWhenEnabled() async {
        let defaults = suite()
        _ = await AppLock(defaults: defaults, authenticator: FakeAuthenticator()).setEnabled(true)
        let relaunched = AppLock(defaults: defaults, authenticator: FakeAuthenticator())
        #expect(relaunched.isLocked && relaunched.shouldCover)
        #expect(await relaunched.unlock())
        #expect(!relaunched.isLocked && !relaunched.shouldCover)
    }

    @Test func failedUnlockStaysLocked() async {
        let defaults = suite()
        _ = await AppLock(defaults: defaults, authenticator: FakeAuthenticator()).setEnabled(true)
        let relaunched = AppLock(defaults: defaults, authenticator: FakeAuthenticator(succeeds: false))
        #expect(await relaunched.unlock() == false)
        #expect(relaunched.isLocked)
    }

    @Test func backgroundLocksAgainAndCoverFollowsScenePhase() async {
        let lock = AppLock(defaults: suite(), authenticator: FakeAuthenticator())
        _ = await lock.setEnabled(true)
        #expect(!lock.shouldCover)
        lock.scenePhaseChanged(.inactive)
        #expect(lock.shouldCover && !lock.isLocked)      // che khi ra ngoài app nhưng chưa khóa
        lock.scenePhaseChanged(.active)
        #expect(!lock.shouldCover)
        lock.scenePhaseChanged(.background)
        #expect(lock.isLocked)
    }

    @Test func disablingRequiresAuthenticationToo() async {
        let defaults = suite()
        let lock = AppLock(defaults: defaults, authenticator: FakeAuthenticator())
        _ = await lock.setEnabled(true)
        let stolen = AppLock(defaults: defaults, authenticator: FakeAuthenticator(succeeds: false))
        #expect(await stolen.setEnabled(false) == false)
        #expect(stolen.isEnabled)
        #expect(await lock.setEnabled(false))
        #expect(!defaults.bool(forKey: SettingsKey.lockEnabled))
    }
}
