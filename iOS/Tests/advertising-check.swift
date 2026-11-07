
@MainActor
private final class FakeAdvertisingServices: AdvertisingServices {
    var isActive = true
    var authorization = TrackingAuthorization.notDetermined
    var trackingReply = TrackingAuthorization.authorized
    var canRequestAds = true
    var privacyOptionsRequired = true
    var failUpdate = false
    var failForm = false
    var failPrivacy = false
    var calls: [String] = []
    var onUpdate: (() -> Void)?
    var onForm: (() -> Void)?
    var onStart: (() -> Void)?
    var onPrivacy: (() -> Void)?
    func requestTrackingAuthorization() async {calls.append("ATT");authorization = trackingReply}
    func updateConsent() async throws {
        calls.append("UMP update");onUpdate?()
        if failUpdate {throw Failure.expected}
    }
    func presentConsentIfRequired() async throws {
        calls.append("UMP form");onForm?()
        if failForm {throw Failure.expected}
    }
    func presentPrivacyOptions() async throws {
        calls.append("UMP privacy");onPrivacy?()
        if failPrivacy {throw Failure.expected}
    }
    func startSDK() async {calls.append("SDK start");onStart?()}
    enum Failure: Error {case expected}
}

@main
struct AdvertisingChecks {
    @MainActor
    static func main() async {
        let configuration: [String:Any] = ["ProductionEnabled":true,"BannerAdUnitID":"test"]
        func make(_ service: FakeAdvertisingServices) -> AdvertisingManager {
            AdvertisingManager(services:service,configuration:configuration)
        }
        // An existing GDPR grant cannot bypass denied, restricted or unresolved ATT.
        for status in [TrackingAuthorization.denied, .restricted, .notDetermined] {
            let service = FakeAdvertisingServices()
            service.authorization = status;service.trackingReply = status
            let manager = make(service)
            await manager.synchronize()
            precondition(service.calls == (status == .notDetermined ? ["ATT"] : []))
            precondition(!manager.ready && !manager.mayLoadBanner && !manager.requestingConsent)
        }
        // First launch: the system choice must precede consent networking, forms and SDK init.
        let service = FakeAdvertisingServices(), manager = make(service)
        await manager.synchronize()
        precondition(service.calls == ["ATT","UMP update","UMP form","SDK start"])
        precondition(manager.ready && manager.mayLoadBanner && manager.privacyOptionsRequired)
        await manager.synchronize()
        precondition(service.calls.count == 4, "No duplicate startup on foreground/login")
        manager.suspendAdvertising();service.isActive = false
        precondition(!manager.ready && !manager.mayLoadBanner)
        await manager.synchronize()
        precondition(service.calls.count == 4)
        service.isActive = true;service.authorization = .denied
        await manager.synchronize()
        precondition(!manager.mayLoadBanner && service.calls.count == 4)
        service.authorization = .authorized
        await manager.synchronize()
        precondition(manager.mayLoadBanner && service.calls.count == 4)
        service.onPrivacy = {
            precondition(!manager.ready && !manager.mayLoadBanner, "Destroy banner before changing consent")
            service.canRequestAds = false
        }
        await manager.showPrivacyOptions()
        precondition(!manager.ready && !manager.mayLoadBanner && manager.privacyOptionsRequired)
        service.failPrivacy = true
        await manager.showPrivacyOptions()
        precondition(manager.privacyError != nil && !manager.ready)
        // Failed updates/forms must not start ads, even when a cached canRequestAds is true.
        for failUpdate in [true,false] {
            let s = FakeAdvertisingServices();s.authorization = .authorized
            s.failUpdate = failUpdate;s.failForm = !failUpdate
            let m = make(s);await m.synchronize()
            precondition(!m.ready && !s.calls.contains("SDK start"))
            s.failUpdate = false;s.failForm = false
            await m.synchronize()
            precondition(m.ready && s.calls.filter{$0 == "SDK start"}.count == 1)
        }
        let noConsent = FakeAdvertisingServices();noConsent.canRequestAds = false
        let deniedGDPR = make(noConsent);await deniedGDPR.synchronize()
        precondition(!deniedGDPR.ready && !noConsent.calls.contains("SDK start"))
        let inactive = FakeAdvertisingServices();inactive.isActive = false
        let waiting = make(inactive);await waiting.synchronize()
        precondition(inactive.calls.isEmpty && !waiting.ready)
        // Revocation/backgrounding can happen at any await, including SDK initialization.
        for stage in ["update", "form", "start"] {
            let s = FakeAdvertisingServices();s.authorization = .authorized
            let m = make(s)
            let revoke = {s.authorization = TrackingAuthorization.denied}
            if stage == "update" {s.onUpdate = revoke}
            if stage == "form" {s.onForm = revoke}
            if stage == "start" {s.onStart = revoke}
            await m.synchronize()
            precondition(!m.ready && !m.mayLoadBanner)
            if stage != "start" {precondition(!s.calls.contains("SDK start"))}
        }
        let background = FakeAdvertisingServices()
        background.onStart = {background.isActive = false}
        let backgroundManager = make(background);await backgroundManager.synchronize()
        precondition(!backgroundManager.mayLoadBanner)
        let disabled = FakeAdvertisingServices()
        let disabledManager = AdvertisingManager(services:disabled,configuration:[:])
        await disabledManager.synchronize()
        precondition(disabled.calls.isEmpty)
        // Two foreground tasks cannot overlap ATT or start two SDK instances.
        let concurrent = FakeAdvertisingServices(), concurrentManager = make(concurrent)
        let first = Task {await concurrentManager.synchronize()}
        let second = Task {await concurrentManager.synchronize()}
        await first.value;await second.value
        precondition(concurrent.calls == ["ATT","UMP update","UMP form","SDK start"])
        print("Advertising checks passed: ATT states/order, UMP failures/retry, revocation, lifecycle, privacy options, duplicate startup, disabled ads")
    }
}
