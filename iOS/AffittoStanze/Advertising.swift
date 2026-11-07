import SwiftUI
import AppTrackingTransparency
import GoogleMobileAds
import UserMessagingPlatform

// Consent coordinator: also compiled in isolation by test/check-advertising.py.
enum TrackingAuthorization { case notDetermined, restricted, denied, authorized }

@MainActor
protocol AdvertisingServices: AnyObject {
    var isActive: Bool { get }
    var authorization: TrackingAuthorization { get }
    var canRequestAds: Bool { get }
    var privacyOptionsRequired: Bool { get }
    func requestTrackingAuthorization() async
    func updateConsent() async throws
    func presentConsentIfRequired() async throws
    func presentPrivacyOptions() async throws
    func startSDK() async
}

/// ATT and UMP are independent gates. No booking/account data enters this class.
@MainActor
final class AdvertisingManager: ObservableObject {
    @Published private(set) var ready = false
    @Published private(set) var privacyOptionsRequired = false
    @Published private(set) var changingPrivacy = false
    @Published private(set) var requestingConsent = false
    @Published var privacyError: String?
    @Published private(set) var revision = UUID()
    private var consentUpdated = false
    private var sdkStarted = false
    private let services: any AdvertisingServices
    private let configuration: [String:Any]

    init(services: any AdvertisingServices, configuration: [String:Any]? = nil) {
        self.services = services
        if let configuration {self.configuration = configuration}
        else if let url = Bundle.main.url(forResource:"AdsConfiguration",withExtension:"plist"),
                let data = try? Data(contentsOf:url),
                let value = try? PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any] {
            self.configuration = value
        } else {self.configuration = [:]}
    }

    var preview: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--ui-preview") && !ProcessInfo.processInfo.arguments.contains("--ui-ad-consent")
        #else
        return false
        #endif
    }
    var enabled: Bool {configuration["ProductionEnabled"] as? Bool == true && !productionUnit.isEmpty}
    private var productionUnit: String {configuration["BannerAdUnitID"] as? String ?? ""}
    var unitID: String {
        #if DEBUG || targetEnvironment(simulator)
        return "ca-app-pub-3940256099942544/2435281174"
        #else
        // TestFlight uses sandbox receipts: testers must never generate real ad traffic.
        if Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" {
            return "ca-app-pub-3940256099942544/2435281174"
        }
        return productionUnit
        #endif
    }
    private var authorizedAndActive: Bool {services.isActive && services.authorization == .authorized}
    var mayLoadBanner: Bool {enabled && ready && authorizedAndActive && consentUpdated && services.canRequestAds && !changingPrivacy}

    func suspendAdvertising() {
        ready = false
        // Destroys the current banner and stops its automatic refresh when leaving the app.
        revision = UUID()
    }

    func synchronize() async {
        guard !preview, enabled, services.isActive else {suspendAdvertising();return}
        guard !requestingConsent, !changingPrivacy else {return}
        requestingConsent = true
        defer {requestingConsent = false}
        if services.authorization == .notDetermined {
            await services.requestTrackingAuthorization()
        }
        // A denial/restriction never falls back to cached GDPR consent or non-personalized ads.
        guard authorizedAndActive else {suspendAdvertising();return}
        if !consentUpdated {
            do {
                try await services.updateConsent()
                privacyOptionsRequired = services.privacyOptionsRequired
                guard authorizedAndActive else {suspendAdvertising();return}
                try await services.presentConsentIfRequired()
                consentUpdated = true
            } catch {
                // Do not reuse a previous consent after a failed refresh/form presentation.
                suspendAdvertising();return
            }
        }
        await updatePermission()
    }

    func showPrivacyOptions() async {
        guard privacyOptionsRequired, services.isActive, !requestingConsent, !changingPrivacy else {return}
        changingPrivacy = true
        suspendAdvertising()
        do {
            try await services.presentPrivacyOptions()
            changingPrivacy = false
            await updatePermission()
        } catch {
            changingPrivacy = false
            consentUpdated = false
            privacyError = "Non è stato possibile aprire le scelte pubblicitarie. Riprova più tardi."
        }
    }

    private func updatePermission() async {
        privacyOptionsRequired = services.privacyOptionsRequired
        guard authorizedAndActive, consentUpdated, services.canRequestAds else {suspendAdvertising();return}
        if !sdkStarted {
            sdkStarted = true
            await services.startSDK()
        }
        // Permission or application state may change while SDK initialization is suspended.
        ready = authorizedAndActive && consentUpdated && services.canRequestAds
        revision = UUID()
    }
}

// iOS service adapter. The coordinator above never directly starts third-party work.
@MainActor
final class GoogleAdvertisingServices: AdvertisingServices {
    var isActive: Bool {UIApplication.shared.applicationState == .active}
    var authorization: TrackingAuthorization {
        switch ATTrackingManager.trackingAuthorizationStatus {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .restricted
        }
    }
    var canRequestAds: Bool {ConsentInformation.shared.canRequestAds}
    var privacyOptionsRequired: Bool {ConsentInformation.shared.privacyOptionsRequirementStatus == .required}
    func requestTrackingAuthorization() async {
        _ = await ATTrackingManager.requestTrackingAuthorization()
    }
    func updateConsent() async throws {
        try await ConsentInformation.shared.requestConsentInfoUpdate(with:RequestParameters())
    }
    func presentConsentIfRequired() async throws {
        try await ConsentForm.loadAndPresentIfRequired(from:nil)
    }
    func presentPrivacyOptions() async throws {
        try await ConsentForm.presentPrivacyOptionsForm(from:nil)
    }
    func startSDK() async {
        let config = MobileAds.shared.requestConfiguration
        config.maxAdContentRating = .general
        config.coarseLocationCollectionEnabled = false
        config.setPublisherFirstPartyIDEnabled(false)
        config.publisherPrivacyPersonalizationState = .disabled
        await MobileAds.shared.start()
    }
}

struct AdvertisingHeader: View {
    @EnvironmentObject private var ads: AdvertisingManager
    @State private var keyboardVisible = false
    var body: some View {
        VStack(spacing:0) {
            if !keyboardVisible && (ads.preview || ads.ready || ads.privacyOptionsRequired) {
                HStack(spacing:8) {
                    VStack(spacing:0) {
                        if ads.preview {
                            Text("Pubblicità · Anteprima").font(.caption).foregroundStyle(.secondary)
                                .frame(width:320,height:50).background(Color(uiColor:.secondarySystemBackground))
                                .accessibilityIdentifier("advertising.preview")
                        } else if ads.ready {
                            GoogleBanner(unitID:ads.unitID,ads:ads).id(ads.revision).frame(width:320,height:50)
                        }
                    }
                    if ads.privacyOptionsRequired {
                        Button {Task {await ads.showPrivacyOptions()}} label: {
                            Image(systemName:"hand.raised").font(.caption).frame(width:44,height:50)
                        }.disabled(ads.changingPrivacy).accessibilityLabel("Scelte privacy pubblicitarie")
                    }
                }.frame(maxWidth:.infinity).padding(.vertical,3)
                    .background(Color(uiColor:.systemBackground))
                Divider()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for:UIResponder.keyboardWillShowNotification)) {_ in keyboardVisible = true}
        .onReceive(NotificationCenter.default.publisher(for:UIResponder.keyboardWillHideNotification)) {_ in keyboardVisible = false}
        .alert("Scelte pubblicitarie",isPresented:Binding(get:{ads.privacyError != nil},set:{if !$0 {ads.privacyError = nil}})) {
            Button("OK",role:.cancel) {ads.privacyError = nil}
        } message: {Text(ads.privacyError ?? "")}
    }
}

private struct GoogleBanner: UIViewControllerRepresentable {
    let unitID:String
    let ads:AdvertisingManager
    func makeUIViewController(context:Context)->BannerController {BannerController(unitID:unitID,ads:ads)}
    func updateUIViewController(_ controller:BannerController,context:Context) {}
    static func dismantleUIViewController(_ controller:BannerController,coordinator:()) {controller.removeBanner()}
}

private final class BannerController:UIViewController {
    private var banner:BannerView?
    private let unitID:String
    private let ads:AdvertisingManager
    init(unitID:String,ads:AdvertisingManager) {self.unitID = unitID;self.ads = ads;super.init(nibName:nil,bundle:nil)}
    required init?(coder:NSCoder) {fatalError("init(coder:) has not been implemented")}
    override func viewDidAppear(_ animated:Bool) {
        super.viewDidAppear(animated)
        guard banner == nil, ads.mayLoadBanner else {return}
        let banner = BannerView(adSize:AdSizeBanner)
        self.banner = banner
        banner.adUnitID = unitID
        banner.rootViewController = self
        banner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(banner)
        NSLayoutConstraint.activate([banner.centerXAnchor.constraint(equalTo:view.centerXAnchor),banner.centerYAnchor.constraint(equalTo:view.centerYAnchor)])
        let request = Request()
        let extras = Extras()
        extras.additionalParameters = ["npa":"1"]
        request.register(extras)
        banner.load(request)
    }
    func removeBanner() {banner?.delegate = nil;banner?.removeFromSuperview();banner = nil}
}
