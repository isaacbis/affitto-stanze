import SwiftUI

@main
struct AffittoStanzeApp: App {
    @StateObject private var store = Store()
    var body: some Scene { WindowGroup { ContentView().environmentObject(store) } }
}

struct User: Codable, Identifiable {
    let id: String; let username: String; let role: String
    var active: Bool? = nil
    var isActive: Bool { active ?? true }
}
struct Room: Codable, Identifiable {
    let id: String; let name: String
    var description: String? = nil; var active: Bool? = nil
    var isActive: Bool { active ?? true }
}
struct Booking: Codable, Identifiable {
    let id: String; let room_name: String; let username: String; let booking_date: String
    let start_hour: Double; let end_hour: Double; let cancellable: Bool
    var status: String? = nil
    var room_id: String? = nil; var user_id: String? = nil
    var admin_note: String? = nil; var created_by_admin_username: String? = nil
    var isFuture: Bool {
        booking_date > BookingClock.day(Date()) || (booking_date == BookingClock.day(Date()) && end_hour * 60 > BookingClock.minutesNow)
    }
}
struct Slot: Codable { let start_hour: Double; let end_hour: Double }
struct MutationReply: Decodable { var ok: Bool?; var id: String? }
struct ReportRow: Decodable, Identifiable {
    let user_id: String; let username: String; let total_hours: Double; let total_bookings: Int
    var id: String { user_id }
}
struct Report: Decodable {
    let reportRows: [ReportRow]; let startDate: String; let endDate: String
    let selectedUserLabel: String; let totalHours: Double; let totalBookings: Int
}
struct APIError: Decodable { let error: String }
struct MessageError: LocalizedError { let message: String; var errorDescription: String? { message } }

struct SessionExpiredError: LocalizedError {
    var errorDescription: String? { "La sessione è scaduta. Accedi di nuovo." }
}

@MainActor final class Store: ObservableObject {
    @Published var user: User?
    @Published var rooms: [Room] = []
    @Published var users: [User] = []
    @Published var bookings: [Booking] = []
    @Published var adminUsers: [User] = []
    @Published var adminRooms: [Room] = []
    @Published var error: String?
    @Published var loading = false
    private let base = URL(string: "https://affitto-stanze.onrender.com/api/v1/")!
    private let session: URLSession
    private var generation = UUID()
    init(session: URLSession = .shared) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-preview") {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [PreviewProtocol.self]
            self.session = URLSession(configuration: config)
        } else { self.session = session }
        #else
        self.session = session
        #endif
    }

    private func clearSession() {
        generation = UUID()
        user = nil; rooms = []; users = []; bookings = []; adminUsers = []; adminRooms = []; error = nil
    }
    private func clearCookies() {
        session.configuration.httpCookieStorage?.cookies(for: base)?.forEach {
            session.configuration.httpCookieStorage?.deleteCookie($0)
        }
    }
    private func responseData(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
        let expectedGeneration = generation
        guard let url = URL(string: path, relativeTo: base) else { throw MessageError(message: "Indirizzo non valido") }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        req.httpMethod = method
        req.setValue("ios", forHTTPHeaderField: "X-Affitto-Client")
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body); req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let data: Data; let response: URLResponse
        do { (data, response) = try await session.data(for: req) }
        catch {
            guard generation == expectedGeneration, !Task.isCancelled else { throw CancellationError() }
            throw error
        }
        try Task.checkCancellation()
        guard generation == expectedGeneration else { throw CancellationError() }
        guard let http = response as? HTTPURLResponse else { throw MessageError(message: "Risposta non valida") }
        if http.statusCode == 401 && path != "login" {
            clearSession(); clearCookies(); throw SessionExpiredError()
        }
        if http.statusCode == 404 && path == "login" { throw MessageError(message: "Il servizio per iPhone non è ancora attivo. Riprova dopo l’aggiornamento del server.") }
        guard (200..<300).contains(http.statusCode) else {
            throw MessageError(message: (try? JSONDecoder().decode(APIError.self, from: data).error) ?? "Servizio non disponibile (\(http.statusCode))")
        }
        return data
    }
    func request<T: Decodable>(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> T {
        let data = try await responseData(path, method: method, body: body)
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw MessageError(message: "Risposta del server non riconosciuta. Riprova tra poco.") }
    }
    func downloadReport(_ query: String) async throws -> URL {
        let data = try await responseData("admin/reports/pdf?" + query)
        guard data.starts(with: Data("%PDF".utf8)) else { throw MessageError(message: "Il server non ha restituito un PDF valido.") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Report-\(UUID().uuidString).pdf")
        try data.write(to: url, options: .atomic)
        return url
    }
    func perform(_ path: String, method: String = "POST", body: [String: Any]? = nil) async -> Bool {
        do { let _: MutationReply = try await request(path, method: method, body: body); await refresh(); return true }
        catch is CancellationError { return false }
        catch { self.error = error.localizedDescription; return false }
    }
    func restore() async {
        do { user = try await request("me"); await refresh() }
        catch is SessionExpiredError { /* Nessuna sessione salvata è una condizione normale. */ }
        catch is CancellationError {}
        catch { self.error = "Connessione non riuscita. Controlla la rete e riprova. " + error.localizedDescription }
    }
    func login(_ username: String, _ password: String) async {
        guard !loading else { return }
        loading = true; defer { loading = false }
        clearSession(); clearCookies()
        do { user = try await request("login", method: "POST", body: ["username": username, "password": password]); await refresh() }
        catch is CancellationError {}
        catch { self.error = error.localizedDescription }
    }
    func refresh() async {
        guard let current = user else { return }
        let expectedGeneration = generation
        do {
            let newRooms: [Room] = try await request("rooms")
            let newBookings: [Booking] = try await request("bookings")
            let newUsers: [User] = current.role == "admin" ? try await request("users") : []
            let newAdminUsers: [User] = current.role == "admin" ? try await request("admin/users") : []
            let newAdminRooms: [Room] = current.role == "admin" ? try await request("admin/rooms") : []
            guard generation == expectedGeneration, !Task.isCancelled else { return }
            rooms = newRooms; bookings = newBookings; users = newUsers
            adminUsers = newAdminUsers; adminRooms = newAdminRooms
        } catch is CancellationError {}
        catch { self.error = error.localizedDescription }
    }
    func logout() async {
        guard !loading else { return }
        loading = true; defer { loading = false }
        clearSession()
        do { let _: [String: Bool] = try await request("logout", method: "POST") }
        catch is CancellationError {}
        catch { self.error = "Disconnesso da questo dispositivo. Il server non ha confermato l’uscita: " + error.localizedDescription }
        clearCookies()
    }
    func delete(_ booking: Booking) async {
        do { let _: [String: Bool] = try await request("bookings/\(booking.id)", method: "DELETE"); await refresh() }
        catch is CancellationError {}
        catch { self.error = error.localizedDescription }
    }
}

enum BookingClock {
    static let timeZone = TimeZone(identifier: "Europe/Rome")!
    static var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = timeZone; return c }
    static var minutesNow: Double { Double(calendar.component(.hour, from: Date()) * 60 + calendar.component(.minute, from: Date())) }
    static func day(_ date: Date) -> String {
        let f = DateFormatter(); f.calendar = calendar; f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = timeZone; f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
    static func date(_ day: String) -> Date {
        let f = DateFormatter(); f.calendar = calendar; f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = timeZone; f.dateFormat = "yyyy-MM-dd"
        return f.date(from: day) ?? Date()
    }
    static func label(_ day: String) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "it_IT"); f.timeZone = timeZone; f.dateStyle = .medium
        return f.string(from: date(day))
    }
    static func start(_ date: Date, hour: Double) -> Date {
        calendar.date(byAdding: .minute, value: Int(hour * 60), to: calendar.startOfDay(for: date))!
    }
    static func query(_ values: [(String, String)]) -> String {
        var c = URLComponents(); c.queryItems = values.map { URLQueryItem(name: $0.0, value: $0.1) }; return c.percentEncodedQuery ?? ""
    }
}
func timeLabel(_ value: Double) -> String { String(format: "%02d:%02d", Int(value), Int((value.truncatingRemainder(dividingBy: 1)) * 60)) }

#if DEBUG
// Isolated visual QA data. This transport never contacts the real service.
final class PreviewProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let args = ProcessInfo.processInfo.arguments
        let role = args.contains("--ui-user") ? "user" : "admin"
        let user: [String: Any] = ["id":"preview", "username":"Isacco", "role":role, "active":true]
        let users: [[String: Any]] = [user] + (1...24).map { ["id":"user-\($0)", "username":"Utente \($0)", "role":"user", "active":$0 != 2] }
        let rooms: [[String: Any]] = (1...12).map { ["id":"room-\($0)", "name":"Sala \($0)", "active":$0 != 3, "description":String(repeating:"Una stanza luminosa e accogliente. ",count:12)] }
        let bookings: [[String: Any]] = (1...18).map { i -> [String: Any] in
            var row: [String: Any] = ["id":"booking-\(i)", "room_name":"Sala \((i % 3)+1)", "room_id":"room-1", "user_id":"user-1", "username":"Utente \(i)"]
            row["booking_date"] = BookingClock.day(Date())
            row["start_hour"] = Double(8 + i % 10); row["end_hour"] = Double(9 + i % 10)
            row["cancellable"] = true
            row["admin_note"] = "Nota privata per la prenotazione. " + String(repeating:"Dettagli riservati. ",count:20)
            row["created_by_admin_username"] = "Isacco"
            return row
        }
        let path = request.url!.path
        var code=200; var body: Any = ["ok":true]
        if path.hasSuffix("/me") || path.hasSuffix("/login") {
            if args.contains("--ui-login") && path.hasSuffix("/me") {code=401;body=["error":"Sessione scaduta"]} else {body=user}
        } else if path.hasSuffix("/availability") {body=[["start_hour":10.0,"end_hour":11.0],["start_hour":15.0,"end_hour":16.5]]}
        else if path.hasSuffix("/users") && request.httpMethod == "GET" {body=path.contains("/admin/") ? users : users.filter {($0["role"] as? String) == "user" && ($0["active"] as? Bool) == true}}
        else if path.hasSuffix("/rooms") && request.httpMethod == "GET" {body=path.contains("/admin/") ? rooms : rooms.filter {($0["active"] as? Bool) == true}}
        else if path.hasSuffix("/bookings") && request.httpMethod == "GET" {body=bookings}
        else if path.hasSuffix("/reports") {
            let rows:[[String:Any]]=(1...14).map{["user_id":"user-\($0)","username":"Utente \($0)","total_hours":Double($0),"total_bookings":$0]}
            body=["reportRows":rows,"startDate":"2026-11-01","endDate":"2026-11-30","selectedUserLabel":"Tutti","totalHours":105.0,"totalBookings":105]
        }
        guard let data=try? JSONSerialization.data(withJSONObject:body) else{return}
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:code,httpVersion:nil,headerFields:["Content-Type":"application/json"])!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:data);client?.urlProtocolDidFinishLoading(self)
    }
}
#endif
