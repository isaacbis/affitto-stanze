import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: Store
    @State private var restoring = true
    var body: some View {
        VStack(spacing:0) {
            AdvertisingHeader()
            Group { if restoring { ProgressView("Caricamento…") } else if store.user == nil { LoginView() } else { AppRoot() } }
                .frame(maxWidth:.infinity,maxHeight:.infinity)
        }
            .tint(brand).task { await store.restore(); restoring = false }
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
    @EnvironmentObject var store: Store
    @Environment(\.scenePhase) private var phase
    var body: some View {
        TabView {
            NavigationStack { DashboardScreen() }.tabItem {Label("Home",systemImage:"house")}
            NavigationStack { NewBooking() }.tabItem {Label("Prenota",systemImage:"plus.circle")}
            NavigationStack { BookingList() }.tabItem {Label("Prenotazioni",systemImage:"calendar")}
            if store.user?.role == "admin" { NavigationStack { ManagementScreen() }.tabItem {Label("Gestione",systemImage:"square.grid.2x2")} }
            else { NavigationStack { ProfileScreen() }.tabItem {Label("Profilo",systemImage:"person")} }
        }.onChange(of:phase) {_,p in if p == .active {Task {await store.refresh()}}}
    }
}
struct DashboardScreen: View {
    @EnvironmentObject var store: Store
    var admin: Bool {store.user?.role == "admin"}
    var shown: [Booking] {
        if admin {return store.bookings.filter{$0.booking_date == BookingClock.day(Date()) && ($0.status ?? "active") == "active"}.sorted{$0.start_hour < $1.start_hour}}
        return Array(store.bookings.sorted{$0.booking_date == $1.booking_date ? $0.start_hour > $1.start_hour : $0.booking_date > $1.booking_date}.prefix(10))
    }
    var body: some View {
        Canvas {
            Text("Ciao, \(store.user?.username ?? "")").font(.title2.bold()).lineLimit(1)
            if admin {
                HStack(spacing:10) {
                    metric("Utenti",store.adminUsers.filter{$0.role == "user" && $0.isActive}.count)
                    metric("Stanze",store.adminRooms.filter{$0.isActive}.count)
                    metric("Oggi",shown.count)
                }
            }
            NavigationLink {NewBooking()} label: { HStack {Image(systemName:"plus.circle.fill"); Text("Prenota una stanza").fontWeight(.semibold);Spacer();Image(systemName:"arrow.right")}.padding(16).foregroundStyle(.white).background(primaryGradient,in:RoundedRectangle(cornerRadius:18)) }
            Text(admin ? "Prenotazioni di oggi" : "Ultime prenotazioni").font(.headline)
            PagedRows(items:shown,empty:admin ? "Nessuna prenotazione oggi" : "Nessuna prenotazione",rowHeight:78) { b in BookingRow(booking:b,admin:admin) }
        }.navigationTitle("Affitto stanze").toolbar {
            ToolbarItem(placement:.topBarLeading) {Button {Task {await store.refresh()}} label:{Image(systemName:"arrow.clockwise")}.accessibilityLabel("Aggiorna")}
            ToolbarItem(placement:.topBarTrailing) {NavigationLink {ProfileScreen()} label:{Image(systemName:"person.crop.circle")}.accessibilityLabel("Profilo")}
        }
    }
    func metric(_ title:String,_ value:Int)->some View {
        let color=title == "Utenti" ? coral : title == "Stanze" ? sea : brand
        return VStack(spacing:4) {Text("\(value)").font(.title2.bold());Text(title).font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.88))}
            .foregroundStyle(.white).frame(maxWidth:.infinity).padding(.vertical,12)
            .background(LinearGradient(colors:[color,color.opacity(0.78)],startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:16))
            .shadow(color:color.opacity(0.16),radius:7,y:3)
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
    var body:some View {
        Canvas {
            Picker("Periodo",selection:$filter) {Text("Prossime").tag(0);Text("Storico").tag(1);Text("Tutte").tag(2)}.pickerStyle(.segmented)
            Input(title:"Cerca stanza, data o utente",text:$search)
            PagedRows(items:shown,empty:"Nessuna prenotazione") {b in BookingRow(booking:b,admin:store.user?.role == "admin")}
        }.navigationTitle("Prenotazioni").toolbar {Button {Task {await store.refresh()}} label:{Image(systemName:"arrow.clockwise")}.accessibilityLabel("Aggiorna")}
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
    @EnvironmentObject var store:Store
    var body:some View {
        Canvas {
            Card {Label(store.user?.username ?? "",systemImage:"person.crop.circle.fill").font(.title2.bold());Text(store.user?.role == "admin" ? "Amministratore" : "Utente").foregroundStyle(.secondary)}
            Card {
                NavigationLink {PasswordView()} label:{DetailLink(label:"Sicurezza",value:"Cambia password")}
                Link(destination:URL(string:"https://affitto-stanze.onrender.com/privacy.html")!) {DetailLink(label:"Dati personali",value:"Privacy")}
                Link(destination:URL(string:"https://affitto-stanze.onrender.com/support.html")!) {DetailLink(label:"Hai bisogno di aiuto?",value:"Assistenza")}
            }
            Spacer(minLength:0)
            Button("Esci dall’account",role:.destructive) {Task {await store.logout()}}.buttonStyle(.bordered).disabled(store.loading).frame(maxWidth:.infinity)
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
