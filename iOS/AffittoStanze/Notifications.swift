import SwiftUI
import UserNotifications
import Security

@MainActor final class NotificationManager:ObservableObject {
    static let shared=NotificationManager()
    @Published private(set) var status="Da attivare"
    @Published private(set) var enabled=UserDefaults.standard.object(forKey:"booking.notifications.enabled") as? Bool ?? true
    @Published private(set) var openedEvent:String?
    @Published private(set) var openedBookingID:String?
    @Published private(set) var openedType:String?
    @Published private(set) var openedRecipient:String?
    private var token:String?
    private var revision=UUID()
    private var store:Store?
    private var syncing=false
    private var retryTask:Task<Void,Never>?
    private var registeredUser:String?
    private var identity:[String:String]?
    private var preview:Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--ui-preview")
        #else
        return false
        #endif
    }
    private init() {}
    func attach(_ store:Store) {self.store=store}
    private func nextSequence()->Int64 {
        let next=max(Int64(UserDefaults.standard.double(forKey:"booking.notifications.sequence"))+1,Int64(Date().timeIntervalSince1970*1000))
        UserDefaults.standard.set(Double(next),forKey:"booking.notifications.sequence");return next
    }
    private func installation() throws -> [String:String] {
        if let identity {return identity}
        let query:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"com.isaacmorganti.affittostanze.push",kSecAttrAccount as String:"installation"]
        var item:CFTypeRef?
        let result=SecItemCopyMatching((query.merging([kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]){_,new in new}) as CFDictionary,&item)
        if result==errSecSuccess, let data=item as? Data, let saved=try? JSONDecoder().decode([String:String].self,from:data), saved["installation_id"] != nil, saved["installation_secret"] != nil {
            identity=saved;return saved
        }
        guard result==errSecItemNotFound else {throw MessageError(message:"Sblocca iPhone per attivare le notifiche.")}
        var bytes=[UInt8](repeating:0,count:32)
        guard SecRandomCopyBytes(kSecRandomDefault,bytes.count,&bytes)==errSecSuccess else {throw MessageError(message:"Impossibile attivare le notifiche.")}
        let saved=["installation_id":UUID().uuidString.lowercased(),"installation_secret":bytes.map{String(format:"%02x",$0)}.joined()]
        let data=try JSONEncoder().encode(saved)
        let added=SecItemAdd(query.merging([kSecValueData as String:data,kSecAttrAccessible as String:kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]){_,new in new} as CFDictionary,nil)
        guard added==errSecSuccess else {throw MessageError(message:"Impossibile salvare le preferenze notifiche.")}
        identity=saved;return saved
    }
    func synchronize() async {
        guard !preview, let store else {if preview {status="Anteprima"};return}
        let currentUser=store.user?.id
        if currentUser != registeredUser {revision=UUID();registeredUser=currentUser}
        guard !syncing else {return}
        syncing=true;let expected=revision
        defer {syncing=false}
        do {
            if currentUser == nil || !enabled {
                UIApplication.shared.unregisterForRemoteNotifications()
                UNUserNotificationCenter.current().removeAllDeliveredNotifications()
                try await removeDevice()
                status=enabled ? "Accedi per riceverle" : "Disattivate"
                return
            }
            let center=UNUserNotificationCenter.current()
            var settings=await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try await center.requestAuthorization(options:[.alert,.sound,.badge])
                settings=await center.notificationSettings()
            }
            guard revision==expected,store.user?.id==currentUser else {scheduleRetry();return}
            guard [.authorized,.provisional,.ephemeral].contains(settings.authorizationStatus) else {
                try await removeDevice();status="Disattivate in iOS";return
            }
            UIApplication.shared.registerForRemoteNotifications()
            guard let token else {status="Attivazione…";return}
            var body:[String:Any]=try installation();body["token"]=token;body["sequence"]=nextSequence()
            #if DEBUG
            body["environment"]="development"
            #else
            body["environment"]="production"
            #endif
            let _:MutationReply=try await store.request("push/device",method:"POST",body:body)
            guard revision==expected,store.user?.id==currentUser else {scheduleRetry();return}
            status="Attive"
        } catch is CancellationError {scheduleRetry()}
        catch {status="Da sincronizzare";scheduleRetry()}
    }
    private func scheduleRetry() {
        retryTask?.cancel()
        retryTask=Task {try? await Task.sleep(for:.seconds(20));guard !Task.isCancelled else{return};await synchronize()}
    }
    private func removeDevice() async throws {
        // Uses the installation secret, so removal can be retried even after logout.
        var identity:[String:Any]=try installation();identity["sequence"]=nextSequence()
        var request=URLRequest(url:URL(string:"https://affitto-stanze.onrender.com/api/v1/push/device")!,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:15)
        request.httpMethod="DELETE";request.setValue("ios",forHTTPHeaderField:"X-Affitto-Client")
        request.setValue("application/json",forHTTPHeaderField:"Content-Type");request.httpBody=try JSONSerialization.data(withJSONObject:identity)
        let (_,response)=try await URLSession.shared.data(for:request)
        guard let response=response as? HTTPURLResponse,(200..<300).contains(response.statusCode) else {throw MessageError(message:"Riprova tra poco.")}
    }
    func prepareLogout() async {
        guard !preview else{return}
        revision=UUID();registeredUser=nil;clearOpenedEvent()
        UIApplication.shared.unregisterForRemoteNotifications()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        do {try await removeDevice()}catch {scheduleRetry()}
    }
    func setEnabled(_ value:Bool) async {
        enabled=value;UserDefaults.standard.set(value,forKey:"booking.notifications.enabled");revision=UUID()
        await synchronize()
    }
    func receivedToken(_ data:Data) {
        token=data.map{String(format:"%02x",$0)}.joined()
        // APNs may return a token while registration is still awaiting its callback.
        Task {await synchronize()}
    }
    func registrationFailed() {status="Da sincronizzare";scheduleRetry()}
    func receive(_ info:[AnyHashable:Any],opened:Bool) {
        guard let recipient=info["recipient_id"] as? String else{return}
        if opened {
            openedRecipient=recipient;openedBookingID=info["booking_id"] as? String
            openedType=info["event_type"] as? String;openedEvent=info["event_id"] as? String ?? UUID().uuidString
        }
        if store?.user?.id==recipient {Task {await store?.refresh()}}
    }
    func canPresent(_ info:[AnyHashable:Any])->Bool {info["recipient_id"] as? String == store?.user?.id && store?.user != nil}
    func clearOpenedEvent() {openedEvent=nil;openedBookingID=nil;openedType=nil;openedRecipient=nil}
    func openSettings() {if let url=URL(string:UIApplication.openSettingsURLString){UIApplication.shared.open(url)}}
}

final class AppDelegate:NSObject,UIApplicationDelegate,UNUserNotificationCenterDelegate {
    func application(_ application:UIApplication,didFinishLaunchingWithOptions launchOptions:[UIApplication.LaunchOptionsKey:Any]?=nil)->Bool {
        UNUserNotificationCenter.current().delegate=self;return true
    }
    func application(_ application:UIApplication,didRegisterForRemoteNotificationsWithDeviceToken deviceToken:Data) {
        Task {@MainActor in NotificationManager.shared.receivedToken(deviceToken)}
    }
    func application(_ application:UIApplication,didFailToRegisterForRemoteNotificationsWithError error:Error) {
        Task {@MainActor in NotificationManager.shared.registrationFailed()}
    }
    func userNotificationCenter(_ center:UNUserNotificationCenter,willPresent notification:UNNotification,withCompletionHandler completionHandler:@escaping(UNNotificationPresentationOptions)->Void) {
        Task {@MainActor in
            let info=notification.request.content.userInfo
            NotificationManager.shared.receive(info,opened:false)
            // A generic alert remains useful when the app is in the foreground.
            completionHandler(NotificationManager.shared.canPresent(info) ? [.banner,.sound,.list] : [])
        }
    }
    func userNotificationCenter(_ center:UNUserNotificationCenter,didReceive response:UNNotificationResponse,withCompletionHandler completionHandler:@escaping()->Void) {
        Task {@MainActor in NotificationManager.shared.receive(response.notification.request.content.userInfo,opened:true);completionHandler()}
    }
}

struct NotificationSettingsRow:View {
    @EnvironmentObject var notifications:NotificationManager
    var body:some View {
        HStack(spacing:8) {
            Image(systemName:"bell.badge.fill").foregroundStyle(brand)
            VStack(alignment:.leading,spacing:2) {
                Text("Notifiche prenotazioni").font(.subheadline.weight(.semibold))
                Text(notifications.status).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("notifications.status")
            }
            Spacer(minLength:0)
            Button {
                if notifications.status=="Disattivate in iOS" {notifications.openSettings()}
                else {Task {await notifications.setEnabled(!notifications.enabled)}}
            } label:{Text(notifications.status=="Disattivate in iOS" ? "Impostazioni" : notifications.enabled ? "Disattiva" : "Attiva").font(.caption.weight(.medium)).frame(minHeight:44)}
                .accessibilityIdentifier("notifications.toggle")
        }
    }
}
