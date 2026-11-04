import SwiftUI

@main
struct AffittoStanzeApp: App {
    @StateObject private var store = Store()
    var body: some Scene { WindowGroup { ContentView().environmentObject(store) } }
}

struct User: Codable, Identifiable { let id: String; let username: String; let role: String }
struct Room: Codable, Identifiable { let id: String; let name: String }
struct Booking: Codable, Identifiable {
    let id: String; let room_name: String; let username: String; let booking_date: String
    let start_hour: Double; let end_hour: Double; let cancellable: Bool
}
struct Slot: Codable { let start_hour: Double; let end_hour: Double }
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
    @Published var error: String?
    @Published var loading = false
    private let base = URL(string: "https://affitto-stanze.onrender.com/api/v1/")!
    private let session: URLSession
    private var generation = UUID()
    init(session: URLSession = .shared) { self.session = session }

    private func clearSession() {
        generation = UUID()
        user = nil; rooms = []; users = []; bookings = []; error = nil
    }
    private func clearCookies() {
        session.configuration.httpCookieStorage?.cookies(for: base)?.forEach {
            session.configuration.httpCookieStorage?.deleteCookie($0)
        }
    }
    func request<T: Decodable>(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> T {
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
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw MessageError(message: "Risposta del server non riconosciuta. Riprova tra poco.") }
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
            guard generation == expectedGeneration, !Task.isCancelled else { return }
            rooms = newRooms; bookings = newBookings; users = newUsers
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

struct ContentView: View {
    @EnvironmentObject var store: Store
    @State private var restoring = true
    var body: some View {
        Group { if restoring { ProgressView("Caricamento…") } else if store.user == nil { LoginView() } else { MainView() } }
            .tint(Color(red: 0.19, green: 0.32, blue: 0.30))
            .task { await store.restore(); restoring = false }
            .alert("Attenzione", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
    }
}
struct LoginView: View {
    @EnvironmentObject var store: Store
    @ScaledMetric(relativeTo: .largeTitle) private var headingSize = 34.0
    @State private var username = ""
    @State private var password = ""
    @FocusState private var focused: Field?
    private enum Field { case username, password }
    private let ink = Color(red: 0.10, green: 0.14, blue: 0.26)
    private let blue = Color(red: 0.29, green: 0.32, blue: 0.91)

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    LinearGradient(colors: [Color(red: 0.90, green: 0.92, blue: 1), Color(red: 0.94, green: 0.91, blue: 1), Color(red: 0.88, green: 0.95, blue: 1)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
                    Circle().fill(.white.opacity(0.32)).frame(width: 260).blur(radius: 2).offset(x: 155, y: -260)
                    Circle().fill(blue.opacity(0.08)).frame(width: 250).blur(radius: 12).offset(x: -175, y: 290)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 10) {
                                Image(systemName: "square.grid.2x2.fill").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white).frame(width: 42, height: 42).background(LinearGradient(colors: [blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 13))
                                Text("AFFITTO STANZE").font(.system(size: 12, weight: .bold, design: .rounded)).tracking(1.5).foregroundStyle(ink.opacity(0.75))
                                Spacer()
                            }.padding(.bottom, 42)
                            Text("Il tuo spazio,\nsempre con te.").font(.system(size: headingSize, weight: .bold, design: .rounded)).tracking(-1).foregroundStyle(ink).fixedSize(horizontal: false, vertical: true)
                            Text("Gestisci le tue prenotazioni in modo semplice, ovunque tu sia.").font(.subheadline).foregroundStyle(ink.opacity(0.65)).lineSpacing(4).padding(.top, 12).padding(.bottom, 28)
                            VStack(alignment: .leading, spacing: 18) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Bentornato").font(.title2.bold()).foregroundStyle(ink)
                                    Text("Accedi al tuo account per continuare.").font(.subheadline).foregroundStyle(.secondary)
                                }.padding(.bottom, 3)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Username").font(.subheadline.weight(.semibold)).foregroundStyle(ink)
                                    HStack(spacing: 12) { Image(systemName: "person").foregroundStyle(blue); TextField("Il tuo username", text: $username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused, equals: .username).submitLabel(.next).onSubmit { focused = .password } }.padding(15).background(Color(red: 0.96, green: 0.97, blue: 1), in: RoundedRectangle(cornerRadius: 14))
                                }
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Password").font(.subheadline.weight(.semibold)).foregroundStyle(ink)
                                    HStack(spacing: 12) { Image(systemName: "lock").foregroundStyle(blue); SecureField("La tua password", text: $password).textContentType(.password).focused($focused, equals: .password).submitLabel(.go).onSubmit { if !username.isEmpty && !password.isEmpty { Task { await store.login(username, password) } } } }.padding(15).background(Color(red: 0.96, green: 0.97, blue: 1), in: RoundedRectangle(cornerRadius: 14))
                                }
                                Button { focused = nil; Task { await store.login(username, password) } } label: {
                                    HStack { Spacer(); if store.loading { ProgressView().tint(.white) } else { Text("Accedi").fontWeight(.bold); Image(systemName: "arrow.right") }; Spacer() }.foregroundStyle(.white).padding(.vertical, 16).background(LinearGradient(colors: [blue, Color(red: 0.30, green: 0.69, blue: 0.97)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 14))
                                }.disabled(username.isEmpty || password.isEmpty || store.loading).opacity(username.isEmpty || password.isEmpty ? 0.65 : 1)
                            }.padding(24).background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 26)).overlay(RoundedRectangle(cornerRadius: 26).stroke(.white, lineWidth: 1)).shadow(color: blue.opacity(0.12), radius: 25, y: 12)
                            HStack(spacing: 6) { Image(systemName: "lock.shield"); Text("Area riservata utenti e amministratori") }.font(.caption).foregroundStyle(ink.opacity(0.58)).frame(maxWidth: .infinity).padding(.top, 25)
                        }.frame(maxWidth: 440).frame(minHeight: max(geometry.size.height - 48, 0), alignment: .center).padding(.horizontal, 25).padding(.vertical, 24).frame(maxWidth: .infinity)
                    }.scrollDismissesKeyboard(.interactively)
                }
            }
        }.preferredColorScheme(.light)
    }
}
struct MainView: View {
    @EnvironmentObject var store: Store
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        TabView {
            NavigationStack { BookingList() }.tabItem { Label("Prenotazioni", systemImage: "calendar") }
            NavigationStack { NewBooking() }.tabItem { Label("Prenota", systemImage: "plus.circle") }
            NavigationStack {
                Form { Section("Account") { LabeledContent("Username", value: store.user?.username ?? ""); LabeledContent("Ruolo", value: store.user?.role == "admin" ? "Amministratore" : "Utente"); NavigationLink("Cambia password") { PasswordView() } }; Button("Esci", role: .destructive) { Task { await store.logout() } } }.navigationTitle("Profilo")
            }.tabItem { Label("Profilo", systemImage: "person") }
        }.onChange(of: scenePhase) { _, phase in if phase == .active { Task { await store.refresh() } } }
    }
}
func timeLabel(_ value: Double) -> String { String(format: "%02d:%02d", Int(value), Int((value.truncatingRemainder(dividingBy: 1)) * 60)) }
struct BookingList: View {
    @EnvironmentObject var store: Store
    @State private var pending: Booking?
    @State private var history = false
    private var visibleBookings: [Booking] {
        store.bookings.filter { booking in
            let today = BookingClock.day(Date())
            let future = booking.booking_date > today || (booking.booking_date == today && booking.end_hour > Double(BookingClock.calendar.component(.hour, from: Date())) + Double(BookingClock.calendar.component(.minute, from: Date())) / 60)
            return history ? !future : future
        }.sorted { lhs, rhs in
            if lhs.booking_date == rhs.booking_date { return history ? lhs.start_hour > rhs.start_hour : lhs.start_hour < rhs.start_hour }
            return history ? lhs.booking_date > rhs.booking_date : lhs.booking_date < rhs.booking_date
        }
    }
    var body: some View {
        List {
            Picker("Periodo", selection: $history) { Text("Prossime").tag(false); Text("Storico").tag(true) }.pickerStyle(.segmented)
            if visibleBookings.isEmpty { ContentUnavailableView("Nessuna prenotazione", systemImage: "calendar", description: Text("Le prenotazioni compariranno qui.")) }
            ForEach(visibleBookings) { booking in
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Text(booking.room_name).font(.headline); Spacer(); Text(booking.booking_date).font(.subheadline).foregroundStyle(.secondary) }
                    Text("\(timeLabel(booking.start_hour)) – \(timeLabel(booking.end_hour))").font(.subheadline)
                    if store.user?.role == "admin" { Text(booking.username).font(.caption).foregroundStyle(.secondary) }
                    if booking.cancellable { Button("Cancella", role: .destructive) { pending = booking }.font(.caption) }
                }.padding(.vertical, 5)
            }
        }.navigationTitle("Prenotazioni").refreshable { await store.refresh() }
            .toolbar { Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") } }
            .confirmationDialog("Cancellare la prenotazione?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) { Button("Cancella prenotazione", role: .destructive) { if let booking = pending { Task { await store.delete(booking) } }; pending = nil } }
    }
}
enum BookingClock {
    static let timeZone = TimeZone(identifier: "Europe/Rome")!
    static var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = timeZone; return c }
    static func day(_ date: Date) -> String {
        let f = DateFormatter(); f.calendar = calendar; f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = timeZone; f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
    static func start(_ date: Date, hour: Double) -> Date {
        calendar.date(byAdding: .minute, value: Int(hour * 60), to: calendar.startOfDay(for: date))!
    }
}
struct NewBooking: View {
    @EnvironmentObject var store: Store
    @State private var room = ""; @State private var selectedUser = ""; @State private var date = Date()
    @State private var start = 8.0; @State private var end = 8.5; @State private var slots: [Slot] = []
    @State private var success = false; @State private var saving = false
    @State private var fetching = false; @State private var availabilityError: String?
    @State private var availabilityKey: String?; @State private var loadID = UUID()
    private var dateString: String { BookingClock.day(date) }
    private var selectionKey: String { "\(room)|\(dateString)" }
    private var starts: [Double] {
        (16..<41).map { Double($0)/2 }.filter { hour in
            BookingClock.start(date, hour: hour) > Date() && !slots.contains { hour < $0.end_hour && hour + 0.5 > $0.start_hour }
        }
    }
    private var ends: [Double] {
        guard starts.contains(start) else { return [] }
        return (17...41).map { Double($0)/2 }.filter { hour in
            hour > start && !slots.contains { start < $0.end_hour && hour > $0.start_hour }
        }
    }
    var body: some View {
        Form {
            Section("Prenotazione") {
                Picker("Stanza", selection: $room) { Text("Seleziona").tag(""); ForEach(store.rooms) { Text($0.name).tag($0.id) } }
                if store.user?.role == "admin" { Picker("Utente", selection: $selectedUser) { Text("Seleziona").tag(""); ForEach(store.users) { Text($0.username).tag($0.id) } } }
                DatePicker("Data", selection: $date, in: BookingClock.calendar.startOfDay(for: Date())..., displayedComponents: .date)
                    .environment(\.timeZone, BookingClock.timeZone).environment(\.calendar, BookingClock.calendar)
                Text("Date e orari di Roma").font(.caption).foregroundStyle(.secondary)
                if availabilityKey == selectionKey && !fetching && availabilityError == nil && !starts.isEmpty {
                    Picker("Dalle", selection: $start) { ForEach(starts, id: \.self) { Text(timeLabel($0)).tag($0) } }
                    Picker("Alle", selection: $end) { ForEach(ends, id: \.self) { Text(timeLabel($0)).tag($0) } }
                }
            }
            Section("Disponibilità") {
                if room.isEmpty { Text("Seleziona una stanza.").foregroundStyle(.secondary) }
                else if fetching || availabilityKey != selectionKey { ProgressView("Verifica disponibilità…") }
                else if let availabilityError {
                    Text(availabilityError).foregroundStyle(.red)
                    Button("Riprova") { Task { await loadSlots() } }
                } else {
                    if starts.isEmpty { Text("Nessuna fascia futura disponibile in questa data.").foregroundStyle(.secondary) }
                    else if slots.isEmpty { Text("Nessun orario occupato.").foregroundStyle(.secondary) }
                    ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in Text("Occupata: \(timeLabel(slot.start_hour)) – \(timeLabel(slot.end_hour))") }
                }
            }
            Button(saving ? "Prenotazione in corso…" : "Conferma prenotazione") { Task { await create() } }
                .disabled(room.isEmpty || fetching || availabilityKey != selectionKey || availabilityError != nil || !starts.contains(start) || !ends.contains(end) || saving || (store.user?.role == "admin" && selectedUser.isEmpty))
        }.navigationTitle("Prenota")
            .task(id: selectionKey) { await loadSlots() }
            .onChange(of: start) { _, _ in if !ends.contains(end) { end = ends.first ?? start + 0.5 } }
            .alert("Prenotazione inserita", isPresented: $success) { Button("OK", role: .cancel) {} }
    }
    func loadSlots() async {
        let id = UUID(); loadID = id
        let key = selectionKey
        slots = []; availabilityError = nil; availabilityKey = nil
        guard !room.isEmpty else { fetching = false; return }
        fetching = true
        var query = URLComponents(); query.queryItems = [URLQueryItem(name: "room_id", value: room), URLQueryItem(name: "booking_date", value: dateString)]
        do {
            let result: [Slot] = try await store.request("availability?" + (query.percentEncodedQuery ?? ""))
            try Task.checkCancellation()
            guard loadID == id && selectionKey == key else { return }
            slots = result; availabilityKey = key; fetching = false
            if !starts.contains(start) { start = starts.first ?? 8 }
            if !ends.contains(end) { end = ends.first ?? start + 0.5 }
        } catch {
            guard loadID == id && selectionKey == key else { return }
            fetching = false
            if error is CancellationError || Task.isCancelled { return }
            availabilityKey = key; availabilityError = "Impossibile verificare la disponibilità. Riprova."
        }
    }
    func create() async {
        guard !saving, starts.contains(start), ends.contains(end) else { return }
        saving = true; defer { saving = false }
        do {
            var body: [String: Any] = ["room_id": room, "booking_date": dateString, "start_hour": start, "end_hour": end]
            if store.user?.role == "admin" { body["user_id"] = selectedUser }
            let _: [String: String] = try await store.request("bookings", method: "POST", body: body)
            success = true; await store.refresh(); await loadSlots()
        } catch is CancellationError {}
        catch { store.error = error.localizedDescription; await loadSlots() }
    }
}

struct PasswordView: View {
    @EnvironmentObject var store: Store
    @State private var current = ""; @State private var newPassword = ""; @State private var confirmation = ""
    @State private var saving = false; @State private var success = false
    var body: some View {
        Form {
            SecureField("Password attuale", text: $current).textContentType(.password)
            SecureField("Nuova password", text: $newPassword).textContentType(.newPassword)
            SecureField("Conferma nuova password", text: $confirmation).textContentType(.newPassword)
            Button("Aggiorna password") { Task { await change() } }.disabled(current.isEmpty || newPassword.isEmpty || confirmation != newPassword || saving)
        }.navigationTitle("Cambia password")
            .alert("Password aggiornata", isPresented: $success) { Button("OK", role: .cancel) {} }
    }
    func change() async {
        saving = true; defer { saving = false }
        do { let _: [String: Bool] = try await store.request("change-password", method: "POST", body: ["current_password": current, "new_password": newPassword]); current = ""; newPassword = ""; confirmation = ""; success = true }
        catch { store.error = error.localizedDescription }
    }
}
