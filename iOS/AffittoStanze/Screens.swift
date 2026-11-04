import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: Store
    @State private var restoring = true
    @EnvironmentObject var notifications:NotificationManager
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        VStack(spacing:0) {
            AdvertisingHeader()
            Group { if restoring { ProgressView("Caricamento…") } else if store.user == nil { LoginView() } else { AppRoot() } }
                .frame(maxWidth:.infinity,maxHeight:.infinity)
        }
            .tint(brand).task { notifications.attach(store);await store.restore(); restoring = false;await notifications.synchronize() }
            .onChange(of:store.user?.id) {_,_ in Task {await notifications.synchronize()}}
            .onChange(of:scenePhase) {_,phase in if phase == .active {Task {await notifications.synchronize()}}}
            .alert("Attenzione", isPresented: Binding(get:{store.error != nil},set:{if !$0 {store.error=nil}})) { Button("OK") {store.error=nil} } message: {Text(store.error ?? "")}
    }
}
struct AppRoot:View {
    var body:some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-preview"), let arg=ProcessInfo.processInfo.arguments.first(where:{$0.hasPrefix("--ui-route=")}) {
            NavigationStack {
                switch String(arg.dropFirst("--ui-route=".count)) {
                case "users":UsersScreen()
                case "new-user":CreateUser()
                case "rooms":RoomsScreen()
                case "new-room":CreateRoom()
                case "reports":ReportsScreen()
                case "profile":ProfileScreen()
                case "password":PasswordView()
                case "booking":NewBooking()
                case "bookings":BookingList()
                default:ManagementScreen()
                }
            }
        } else {MainView()}
        #else
        MainView()
        #endif
    }
}
struct LoginView: View {
    @EnvironmentObject var store: Store
    @State private var username = ""; @State private var password = ""; @State private var passwordStep = false
    @FocusState private var focus: Int?
    var body: some View {
        GeometryReader { geo in
            let short = geo.size.height < 450
            let tiny = geo.size.height < 330
            let compact = geo.size.height < 620
            VStack(alignment: .leading, spacing: compact ? 12 : 24) {
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    Image(systemName: "square.grid.2x2.fill").foregroundStyle(.white).padding(10).background(primaryGradient,in:RoundedRectangle(cornerRadius:12))
                    Text("AFFITTO STANZE").font(.caption.bold()).tracking(1.4).foregroundStyle(brand)
                }
                if !short {
                    Text("Il tuo spazio,\nsempre con te.").font(.system(size:compact ? 27 : 34,weight:.bold,design:.rounded)).fixedSize(horizontal:false,vertical:true).foregroundStyle(Color(red:0.11,green:0.15,blue:0.28))
                    Text("Prenotazioni e gestione, in un unico posto.").font(compact ? .caption : .subheadline).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 12) {
                    if !tiny { Text("Bentornato").font(.title2.bold()) }
                    if !tiny || !passwordStep {
                        TextField("Username",text:$username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled().focused($focus,equals:0).submitLabel(.next).onSubmit {passwordStep=true;focus=1}
                            .padding(13).background(Color.indigo.opacity(0.06),in:RoundedRectangle(cornerRadius:12)).accessibilityIdentifier("login.username")
                    }
                    if !tiny || passwordStep {
                        SecureField("Password",text:$password).textContentType(.password).focused($focus,equals:1).submitLabel(.go).onSubmit {signIn()}
                            .padding(13).background(Color.indigo.opacity(0.06),in:RoundedRectangle(cornerRadius:12)).accessibilityIdentifier("login.password")
                    }
                    if tiny && !passwordStep { MainButton(title:"Continua",disabled:username.isEmpty) {passwordStep=true;focus=1} }
                    else { MainButton(title:"Accedi",busy:store.loading,disabled:username.isEmpty || password.isEmpty) {signIn()} }
                    if tiny && passwordStep {Button("Modifica username") {passwordStep=false;focus=0}.font(.caption)}
                }.padding(compact ? 16 : 22).background(.white,in:RoundedRectangle(cornerRadius:24)).shadow(color:brand.opacity(0.12),radius:20,y:10)
                if !short {HStack {Link("Privacy",destination:URL(string:"https://affitto-stanze.onrender.com/privacy.html")!);Text("·").foregroundStyle(.secondary);Link("Assistenza",destination:URL(string:"https://affitto-stanze.onrender.com/support.html")!)}.font(.caption).frame(maxWidth:.infinity)}
                Spacer(minLength: 0)
            }.padding(.horizontal,24).padding(.vertical,short ? 8 : (compact ? 14 : 20)).frame(maxWidth:460).frame(maxWidth:.infinity,maxHeight:.infinity)
                .background(LinearGradient(colors:[Color(red:0.88,green:0.90,blue:1),Color(red:0.99,green:0.92,blue:0.92),Color(red:0.86,green:0.96,blue:0.96)],startPoint:.topLeading,endPoint:.bottomTrailing).ignoresSafeArea())
        }.preferredColorScheme(.light)
    }
    func signIn() {guard !username.isEmpty && !password.isEmpty else{return};focus=nil;Task {await store.login(username,password)}}
}
struct MainView: View {
    @EnvironmentObject var notifications:NotificationManager
    @State private var selectedTab=0
    @State private var notificationMessage:String?
    @State private var notificationBooking:Booking?
    @EnvironmentObject var store: Store
    @Environment(\.scenePhase) private var phase
    var body: some View {
        TabView(selection:$selectedTab) {
            NavigationStack { DashboardScreen() }.tabItem {Label("Home",systemImage:"house")}.tag(0)
            NavigationStack { NewBooking() }.tabItem {Label("Prenota",systemImage:"plus.circle")}.tag(1)
            NavigationStack { BookingList() }.tabItem {Label("Prenotazioni",systemImage:"calendar")}.tag(2)
            if store.user?.role == "admin" { NavigationStack { ManagementScreen() }.tabItem {Label("Gestione",systemImage:"square.grid.2x2")}.tag(3) }
            else { NavigationStack { ProfileScreen() }.tabItem {Label("Profilo",systemImage:"person")}.tag(3) }
        }.onChange(of:phase) {_,p in if p == .active {Task {await store.refresh()}}}
        .onChange(of:notifications.openedEvent) {_,_ in openNotification()}
        .onAppear {openNotification()}
        .task {
            #if DEBUG
            if let arg=ProcessInfo.processInfo.arguments.first(where:{$0.hasPrefix("--ui-notification=")}),ProcessInfo.processInfo.arguments.contains("--ui-preview") {
                let type=String(arg.dropFirst("--ui-notification=".count))
                notifications.receive(["recipient_id":type=="other-user" ? "another-account" : "preview","booking_id":"booking-1","event_type":type,"event_id":UUID().uuidString],opened:true)
            }
            #endif
        }
        .sheet(item:$notificationBooking) {booking in
            NavigationStack {BookingDetail(booking:booking).toolbar {ToolbarItem(placement:.topBarTrailing) {Button("Fine") {notificationBooking=nil}}}}
        }
        .alert("Prenotazione cancellata",isPresented:Binding(get:{notificationMessage != nil},set:{if !$0 {notificationMessage=nil}})) {Button("OK") {notificationMessage=nil}} message:{Text(notificationMessage ?? "")}
    }
    func openNotification() {
        guard notifications.openedEvent != nil,notifications.openedRecipient==store.user?.id else{return}
        selectedTab=2
        let bookingID=notifications.openedBookingID,type=notifications.openedType,recipient=notifications.openedRecipient
        notifications.clearOpenedEvent()
        Task {
            await store.refresh()
            guard store.user?.id==recipient else{return}
            if type=="deleted" {notificationMessage="La prenotazione è stata cancellata. L’elenco è stato aggiornato."}
            else if let booking=store.bookings.first(where:{$0.id==bookingID}) {notificationBooking=booking}
        }
    }
}
struct DashboardScreen: View {
    @EnvironmentObject var store: Store
    var admin: Bool {store.user?.role == "admin"}
    var shown: [Booking] {
        if admin {return store.bookings.filter{$0.booking_date == BookingClock.day(Date()) && ($0.status ?? "active") == "active"}.sorted{$0.start_hour < $1.start_hour}}
        return store.bookings.sorted{$0.booking_date == $1.booking_date ? $0.start_hour > $1.start_hour : $0.booking_date > $1.booking_date}
    }
    var body: some View {
        VStack(spacing:6) {
            if admin {
                HStack(spacing:8) {
                    metric("Utenti",store.adminUsers.filter{$0.role == "user" && $0.isActive}.count)
                    metric("Stanze",store.adminRooms.filter{$0.isActive}.count)
                    metric("Oggi",shown.count)
                }.padding(.horizontal,12).accessibilityIdentifier("dashboard.metrics")
            }
            BookingScrollList(bookings:shown,admin:admin,today:admin,empty:admin ? "Nessuna prenotazione oggi" : "Nessuna prenotazione")
        }.padding(.top,6).background(AppBackdrop())
        .navigationTitle(admin ? "Prenotazioni di oggi" : "Ultime prenotazioni").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement:.topBarLeading) {Button {Task {await store.refresh()}} label:{Image(systemName:"arrow.clockwise")}.accessibilityLabel("Aggiorna")}
            ToolbarItemGroup(placement:.topBarTrailing) {
                NavigationLink {NewBooking()} label:{Image(systemName:"plus.circle")}.accessibilityLabel("Prenota una stanza")
                NavigationLink {ProfileScreen()} label:{Image(systemName:"person.crop.circle")}.accessibilityLabel("Profilo")
            }
        }
    }
    func metric(_ title:String,_ value:Int)->some View {
        let color=title == "Utenti" ? coral : title == "Stanze" ? sea : brand
        return HStack(spacing:4) {Text("\(value)").bold();Text(title)}
            .font(.caption2).foregroundStyle(color).frame(maxWidth:.infinity).padding(.vertical,4)
            .background(color.opacity(0.10),in:Capsule())
    }
}

/// Only the booking list scrolls; its available height fits five complete rows.
struct BookingScrollList:View {
    let bookings:[Booking]; let admin:Bool
    var today=false;var empty="Nessuna prenotazione"
    private let visibleRows=5
    private let rowSpacing:CGFloat=6
    var body:some View {
        GeometryReader { geo in
            let height=max(44,(geo.size.height-6-rowSpacing*CGFloat(visibleRows-1))/CGFloat(visibleRows))
            if bookings.isEmpty {
                ContentUnavailableView(empty,systemImage:"calendar").frame(maxWidth:.infinity,maxHeight:.infinity)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing:rowSpacing) {
                        ForEach(bookings) {booking in
                            CompactBookingRow(booking:booking,admin:admin,today:today)
                                .frame(height:height)
                        }
                    }
                }
                .accessibilityIdentifier("bookings.list")
                // A changed filter/search starts at the first result; unchanged refreshes preserve position.
                .id(bookings.map(\.id))
                .padding(.horizontal,12).padding(.bottom,6)
            }
        }
    }
}

private struct CompactBookingRow:View {
    let booking:Booking;let admin:Bool;let today:Bool
    var body:some View {
        NavigationLink {BookingDetail(booking:booking)} label: {
            HStack(spacing:8) {
                RoundedRectangle(cornerRadius:2).fill(roomColor(booking.room_name)).frame(width:3)
                VStack(alignment:.leading,spacing:2) {
                    HStack(spacing:6) {
                        Text(booking.room_name).font(.system(size:13,weight:.semibold)).lineLimit(1)
                        Spacer(minLength:2)
                        Text("\(timeLabel(booking.start_hour))–\(timeLabel(booking.end_hour))").font(.system(size:12,weight:.medium)).monospacedDigit().fixedSize()
                    }
                    HStack(spacing:6) {
                        if admin {Text(booking.username).foregroundStyle(brand).lineLimit(1)}
                        if !today {Spacer(minLength:2);Text(BookingClock.label(booking.booking_date)).foregroundStyle(.secondary).lineLimit(1)}
                    }.font(.system(size:11))
                }
                Image(systemName:"chevron.right").font(.system(size:10,weight:.semibold)).foregroundStyle(.tertiary)
            }.padding(.horizontal,10).padding(.vertical,5).frame(maxWidth:.infinity,maxHeight:.infinity)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
        .background(Color(uiColor:.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:10))
        .overlay(RoundedRectangle(cornerRadius:10).stroke(brand.opacity(0.08),lineWidth:1))
        .accessibilityElement(children:.combine)
        .accessibilityLabel("\(booking.room_name), \(admin ? booking.username + ", " : "")\(BookingClock.label(booking.booking_date)), \(timeLabel(booking.start_hour))–\(timeLabel(booking.end_hour))")
        .accessibilityIdentifier("booking.row.\(booking.id)")
    }
}

struct BookingRow: View {
    let booking:Booking; let admin:Bool
    var body: some View {
        NavigationLink {BookingDetail(booking:booking)} label: {
            HStack(spacing:10) {
                Image(systemName:"calendar").font(.headline).foregroundStyle(roomColor(booking.room_name)).frame(width:36,height:40).background(roomColor(booking.room_name).opacity(0.12),in:RoundedRectangle(cornerRadius:11))
                VStack(alignment:.leading,spacing:4) {
                    Text(booking.room_name).font(.subheadline.bold()).lineLimit(1)
                    Text("\(BookingClock.label(booking.booking_date)) · \(timeLabel(booking.start_hour))–\(timeLabel(booking.end_hour))").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if admin {Text(booking.username).font(.caption).foregroundStyle(brand).lineLimit(1)}
                };Spacer(minLength:4);Image(systemName:"chevron.right").font(.caption).foregroundStyle(.secondary)
            }.padding(12)
        }.foregroundStyle(.primary)
    }
}
struct BookingList: View {
    @EnvironmentObject var store:Store
    @State private var filter=0; @State private var search=""
    var shown:[Booking] {store.bookings.filter {b in
        (filter == 2 || (filter == 0 ? b.isFuture : !b.isFuture)) && (search.isEmpty || "\(b.room_name) \(b.username) \(b.booking_date)".localizedCaseInsensitiveContains(search))
    }.sorted {a,b in a.booking_date == b.booking_date ? a.start_hour < b.start_hour : (filter == 0 ? a.booking_date < b.booking_date : a.booking_date > b.booking_date)}}
    @State private var searching=false
    var body:some View {
        BookingScrollList(bookings:shown,admin:store.user?.role == "admin")
            .padding(.top,6).background(AppBackdrop()).navigationTitle("Prenotazioni").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.principal) {
                    Picker("Periodo",selection:$filter) {Text("Prossime").tag(0);Text("Storico").tag(1);Text("Tutte").tag(2)}
                        .pickerStyle(.segmented).frame(maxWidth:260)
                }
                ToolbarItem(placement:.topBarTrailing) {
                    Button {searching=true} label:{Image(systemName:search.isEmpty ? "magnifyingglass" : "line.3.horizontal.decrease.circle.fill")}.accessibilityLabel("Cerca prenotazioni")
                }
            }
            .sheet(isPresented:$searching) {
                NavigationStack {
                    Canvas {
                        Input(title:"Cerca stanza, data o utente",text:$search)
                        Text("\(shown.count) prenotazioni trovate").font(.subheadline).foregroundStyle(.secondary)
                        if !search.isEmpty {Button("Cancella ricerca") {search=""}}
                        Spacer(minLength:0)
                        MainButton(title:"Mostra risultati") {searching=false}
                    }.navigationTitle("Cerca prenotazioni")
                        .toolbar {ToolbarItem(placement:.topBarTrailing) {Button("Fine") {searching=false}}}
                }.presentationDetents([.large])
            }
    }
}

struct BookingDetail: View {
    let booking:Booking
    @EnvironmentObject var store:Store
    @Environment(\.dismiss) private var dismiss
    @State private var confirm=false; @State private var busy=false
    var body:some View {
        Canvas {
            Card {
                Text(booking.room_name).font(.title2.bold()).lineLimit(2)
                Label(BookingClock.label(booking.booking_date),systemImage:"calendar").foregroundStyle(brand)
                Label("\(timeLabel(booking.start_hour)) – \(timeLabel(booking.end_hour))",systemImage:"clock").foregroundStyle(sea)
                Text("Durata: \((booking.end_hour-booking.start_hour).formatted()) ore").font(.subheadline).foregroundStyle(.secondary)
                if store.user?.role == "admin" {LabeledContent("Utente",value:booking.username)}
            }
            if store.user?.role == "admin" {
                Card {
                    NavigationLink {TextPages(title:"Nota privata",text:booking.admin_note ?? "")} label: {DetailLink(label:"Nota privata",value:(booking.admin_note?.isEmpty == false) ? "Leggi" : "Nessuna")}
                    if let author=booking.created_by_admin_username, !author.isEmpty {Text("Inserita da \(author)").font(.caption).foregroundStyle(.secondary).lineLimit(2)}
                }
            }
            Spacer(minLength:0)
            if booking.cancellable {Button("Cancella prenotazione",role:.destructive) {confirm=true}.buttonStyle(.bordered).frame(maxWidth:.infinity).disabled(busy)}
            else {Text("Cancellazione consentita solo oltre un’ora prima dell’inizio.").font(.caption).foregroundStyle(.secondary)}
        }.navigationTitle("Dettaglio").confirmationDialog("Cancellare questa prenotazione?",isPresented:$confirm,titleVisibility:.visible) {
            Button("Cancella prenotazione",role:.destructive) {Task {busy=true;defer{busy=false};if await store.perform("bookings/\(booking.id)",method:"DELETE") {dismiss()}}}
        }
    }
}
struct ProfileScreen:View {
    @EnvironmentObject var notifications:NotificationManager
    @EnvironmentObject var store:Store
    var body:some View {
        Canvas {
            Card {Label(store.user?.username ?? "",systemImage:"person.crop.circle.fill").font(.title2.bold());Text(store.user?.role == "admin" ? "Amministratore" : "Utente").foregroundStyle(.secondary)}
            Card {
                NavigationLink {PasswordView()} label:{DetailLink(label:"Sicurezza",value:"Cambia password")}
                Link(destination:URL(string:"https://affitto-stanze.onrender.com/privacy.html")!) {DetailLink(label:"Dati personali",value:"Privacy")}
                Link(destination:URL(string:"https://affitto-stanze.onrender.com/support.html")!) {DetailLink(label:"Hai bisogno di aiuto?",value:"Assistenza")}
            }
            Card {NotificationSettingsRow()}
            Spacer(minLength:0)
            Button("Esci dall’account",role:.destructive) {Task {await notifications.prepareLogout();await store.logout()}}.buttonStyle(.bordered).disabled(store.loading).frame(maxWidth:.infinity)
        }.navigationTitle("Profilo")
    }
}
struct PasswordView:View {
    @EnvironmentObject var store:Store
    @State private var current="";@State private var newPassword="";@State private var confirm=""
    @State private var step=0;@State private var busy=false;@State private var success=false
    var body:some View {
        Canvas {
            Text(step == 0 ? "Verifica la tua identità" : "Scegli la nuova password").font(.headline)
            if step == 0 {Input(title:"Password attuale",text:$current,secure:true)}
            else {Input(title:"Nuova password",text:$newPassword,secure:true);Input(title:"Conferma password",text:$confirm,secure:true)}
            Spacer(minLength:0)
            MainButton(title:step == 0 ? "Continua" : "Aggiorna password",busy:busy,disabled:step == 0 ? current.isEmpty : (newPassword.isEmpty || newPassword != confirm)) {
                if step == 0 {step=1} else {Task {busy=true;defer{busy=false};if await store.perform("change-password",body:["current_password":current,"new_password":newPassword]) {current="";newPassword="";confirm="";step=0;success=true}}}
            }
            if step == 1 {Button("Indietro") {step=0}.frame(maxWidth:.infinity)}
        }.navigationTitle("Cambia password").alert("Password aggiornata",isPresented:$success) {Button("OK",role:.cancel){}}
    }
}
