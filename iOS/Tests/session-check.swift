final class ReviewProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.lastPathComponent
        let code = path == "login" || path == "logout" ? 200 : path == "me" ? 401 : 500
        let body = path == "login" ? #"{"id":"regular","username":"regular","role":"user"}"# : path == "logout" ? #"{"ok":true}"# : #"{"error":"test error"}"#
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body.data(using: .utf8)!)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main struct SessionCheck {
    @MainActor static func main() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ReviewProtocol.self]
        let store = Store(session: URLSession(configuration: config))
        store.user = User(id:"admin", username:"admin", role:"admin")
        store.bookings = [Booking(id:"admin-only", room_name:"Test", username:"Other user", booking_date:"2026-12-01", start_hour:8, end_hour:9, cancellable:true)]
        store.users = [store.user!]; store.rooms = [Room(id:"room",name:"Test")]
        let _: User? = try? await store.request("me")
        precondition(store.user == nil && store.bookings.isEmpty && store.users.isEmpty && store.rooms.isEmpty, "401 must clear every account's data")
        await store.login("regular", "test")
        precondition(store.user?.role == "user" && store.bookings.isEmpty && store.users.isEmpty, "Refresh failure must never expose previous data")
        await store.logout()
        precondition(store.user == nil && store.bookings.isEmpty)
        let date=BookingClock.calendar.date(from: DateComponents(year:2026,month:11,day:5))!
        precondition(BookingClock.day(date)=="2026-11-05", "Date selection and API must use same timezone")
        precondition(BookingClock.calendar.component(.hour, from: BookingClock.start(date,hour:8.5)) == 8)
        print("PASS: expired session, account change with failed refresh, logout, Rome date conversion")
    }
}
