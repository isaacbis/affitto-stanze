import SwiftUI
import GoogleMobileAds
import UserMessagingPlatform

/// All Google ad requests are gated by UMP. Booking/account data never enters this class.
@MainActor
final class AdvertisingManager: ObservableObject {
    @Published private(set) var ready = false
    @Published private(set) var privacyOptionsRequired = false
    @Published private(set) var changingPrivacy = false
    @Published var privacyError: String?
    @Published private(set) var revision = UUID()
    private var started = false
    private var sdkStarted = false

    var preview: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--ui-preview")
        #else
        return false
        #endif
    }
    private var configuration: [String:Any] {
        guard let url = Bundle.main.url(forResource:"AdsConfiguration",withExtension:"plist"),
              let data = try? Data(contentsOf:url),
              let value = try? PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any] else {return [:]}
        return value
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

    func start() {
        guard !started, !preview, enabled else {return}
        started = true
        ConsentInformation.shared.requestConsentInfoUpdate(with:RequestParameters()) { [weak self] error in
            Task { @MainActor in
                guard let self else {return}
                if error == nil {try? await ConsentForm.loadAndPresentIfRequired(from:nil)}
                await self.updatePermission()
            }
        }
    }

    func showPrivacyOptions() async {
        guard privacyOptionsRequired, !changingPrivacy else {return}
        changingPrivacy = true
        // Remove any existing banner, including its automatic refresh, before changing consent.
        ready = false
        revision = UUID()
        do {try await ConsentForm.presentPrivacyOptionsForm(from:nil)}
        catch {privacyError = "Non è stato possibile aprire le scelte pubblicitarie. Riprova più tardi."}
        await updatePermission()
        changingPrivacy = false
    }

    private func updatePermission() async {
        privacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
        guard ConsentInformation.shared.canRequestAds else {ready = false;return}
        if !sdkStarted {
            sdkStarted = true
            let config = MobileAds.shared.requestConfiguration
            config.maxAdContentRating = .general
            config.coarseLocationCollectionEnabled = false
            config.setPublisherFirstPartyIDEnabled(false)
            config.publisherPrivacyPersonalizationState = .disabled
            await MobileAds.shared.start()
        }
        // Permission may change while SDK initialization is suspended.
        ready = ConsentInformation.shared.canRequestAds
        revision = UUID()
    }
}

struct AdvertisingHeader: View {
    @EnvironmentObject private var ads: AdvertisingManager
    @State private var keyboardVisible = false
    var body: some View {
        VStack(spacing:0) {
            if !keyboardVisible && (ads.preview || ads.ready || ads.privacyOptionsRequired) {
                HStack(spacing:8) {
                    VStack(spacing:3) {
                        Text("Pubblicità").font(.system(size:10)).foregroundStyle(.secondary)
                        if ads.preview {
                            Text("Spazio pubblicitario · Anteprima").font(.caption).foregroundStyle(.secondary)
                                .frame(width:320,height:50).background(Color(uiColor:.secondarySystemBackground))
                                .accessibilityIdentifier("advertising.preview")
                        } else if ads.ready {
                            GoogleBanner(unitID:ads.unitID).id(ads.revision).frame(width:320,height:50)
                        }
                    }
                    if ads.privacyOptionsRequired {
                        Button {Task {await ads.showPrivacyOptions()}} label: {
                            Image(systemName:"hand.raised").font(.caption).frame(width:44,height:50)
                        }.disabled(ads.changingPrivacy).accessibilityLabel("Scelte privacy pubblicitarie")
                    }
                }.frame(maxWidth:.infinity).padding(.vertical,6)
                    .background(Color(uiColor:.systemBackground))
                Divider()
            }
        }
        .task {ads.start()}
        .onReceive(NotificationCenter.default.publisher(for:UIResponder.keyboardWillShowNotification)) {_ in keyboardVisible = true}
        .onReceive(NotificationCenter.default.publisher(for:UIResponder.keyboardWillHideNotification)) {_ in keyboardVisible = false}
        .alert("Scelte pubblicitarie",isPresented:Binding(get:{ads.privacyError != nil},set:{if !$0 {ads.privacyError = nil}})) {
            Button("OK",role:.cancel) {ads.privacyError = nil}
        } message: {Text(ads.privacyError ?? "")}
    }
}

private struct GoogleBanner: UIViewControllerRepresentable {
    let unitID:String
    func makeUIViewController(context:Context)->BannerController {BannerController(unitID:unitID)}
    func updateUIViewController(_ controller:BannerController,context:Context) {}
    static func dismantleUIViewController(_ controller:BannerController,coordinator:()) {controller.removeBanner()}
}

private final class BannerController:UIViewController {
    private var banner:BannerView?
    private let unitID:String
    init(unitID:String) {self.unitID = unitID;super.init(nibName:nil,bundle:nil)}
    required init?(coder:NSCoder) {fatalError("init(coder:) has not been implemented")}
    override func viewDidAppear(_ animated:Bool) {
        super.viewDidAppear(animated)
        guard banner == nil, ConsentInformation.shared.canRequestAds else {return}
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
