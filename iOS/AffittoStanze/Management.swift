import SwiftUI

struct ManagementScreen:View {
    var body:some View {
        Canvas {
            Text("Il tuo gestionale").font(.title2.bold())
            Text("Organizza utenti e stanze, consulta ore e report.").font(.subheadline).foregroundStyle(.secondary)
            menu("Utenti","person.2",destination:UsersScreen())
            menu("Stanze","door.left.hand.open",destination:RoomsScreen())
            menu("Report e PDF","chart.bar.doc.horizontal",destination:ReportsScreen())
            Spacer(minLength:0)
        }.navigationTitle("Gestione").toolbar {NavigationLink {ProfileScreen()} label:{Image(systemName:"person.crop.circle")}.accessibilityLabel("Profilo")}
    }
    func menu<D:View>(_ title:String,_ symbol:String,destination:D)->some View {
        let color=title == "Utenti" ? coral : title == "Stanze" ? sea : honey
        return NavigationLink {destination} label:{HStack(spacing:14) {
            Image(systemName:symbol).font(.title2).foregroundStyle(.white).frame(width:44,height:44).background(LinearGradient(colors:[color,color.opacity(0.75)],startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:13))
            Text(title).font(.headline);Spacer();Image(systemName:"chevron.right").font(.caption).foregroundStyle(color)
        }.padding(.horizontal,16).padding(.vertical,15).background(Color(uiColor:.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:20)).overlay(RoundedRectangle(cornerRadius:20).stroke(color.opacity(0.18),lineWidth:1))}.foregroundStyle(.primary)
    }

}
struct UsersScreen:View {
    @EnvironmentObject var store:Store
    @State private var search=""
    var body:some View {
        Canvas {
            Input(title:"Cerca utente",text:$search)
            PagedRows(items:store.adminUsers.filter{search.isEmpty || $0.username.localizedCaseInsensitiveContains(search)}) {user in
                NavigationLink {UserDetail(original:user)} label:{HStack {VStack(alignment:.leading,spacing:5) {Text(user.username).foregroundStyle(coral).font(.headline).lineLimit(1);Text("\(user.role == "admin" ? "Amministratore" : "Utente") · \(user.isActive ? "Attivo" : "Disattivato")").font(.caption).foregroundStyle(.secondary)};Spacer();Image(systemName:user.isActive ? "checkmark.circle.fill" : "pause.circle").foregroundStyle(user.isActive ? .green : .orange)}.padding(14)}.foregroundStyle(.primary)
            }
        }.navigationTitle("Utenti").toolbar {NavigationLink {CreateUser()} label:{Image(systemName:"plus")}.accessibilityLabel("Crea utente")}
    }
}
struct CreateUser:View {
    @EnvironmentObject var store:Store
    @Environment(\.dismiss) private var dismiss
    @State private var username="";@State private var password="";@State private var confirmation="";@State private var role="user"
    @State private var step=0;@State private var busy=false
    var body:some View {
        Canvas {
            Text(step == 0 ? "Nome e permessi" : "Credenziali iniziali").font(.headline)
            if step == 0 {Input(title:"Username",text:$username);Picker("Ruolo",selection:$role) {Text("Utente").tag("user");Text("Amministratore").tag("admin")}.pickerStyle(.segmented)}
            else {Input(title:"Password iniziale",text:$password,secure:true);Input(title:"Conferma password",text:$confirmation,secure:true)}
            Spacer(minLength:0)
            MainButton(title:step == 0 ? "Continua" : "Crea utente",busy:busy,disabled:step == 0 ? username.trimmingCharacters(in:.whitespaces).isEmpty : (password.isEmpty || password != confirmation)) {
                if step == 0 {step=1} else {Task {busy=true;defer{busy=false};if await store.perform("admin/users",body:["username":username,"password":password,"role":role]) {dismiss()}}}
            }
            if step == 1 {Button("Indietro") {step=0}.frame(maxWidth:.infinity)}
        }.navigationTitle("Nuovo utente")
    }
}
struct UserDetail:View {
    let original:User
    @EnvironmentObject var store:Store
    @State private var confirm=false;@State private var busy=false
    var user:User {store.adminUsers.first{$0.id == original.id} ?? original}
    var body:some View {
        Canvas {
            Card {Text(user.username).font(.title2.bold()).lineLimit(2);LabeledContent("Ruolo",value:user.role == "admin" ? "Amministratore" : "Utente");LabeledContent("Stato",value:user.isActive ? "Attivo" : "Disattivato")}
            if user.role == "user" {Card {NavigationLink {ResetPassword(user:user)} label:{DetailLink(label:"Password",value:"Reimposta")}}}
            Spacer(minLength:0)
            MainButton(title:user.isActive ? "Disattiva utente" : "Riattiva utente",busy:busy,disabled:user.id == store.user?.id) {confirm=true}
            if user.id == store.user?.id {Text("Il tuo account non può essere disattivato da questa sessione.").font(.caption).foregroundStyle(.secondary)}
        }.navigationTitle("Dettaglio utente").confirmationDialog(user.isActive ? "Disattivare questo utente?" : "Riattivare questo utente?",isPresented:$confirm,titleVisibility:.visible) {
            Button("Conferma") {Task {busy=true;defer{busy=false};_ = await store.perform("admin/users/\(user.id)/toggle")}}
        }
    }
}
struct ResetPassword:View {
    let user:User
    @EnvironmentObject var store:Store
    @Environment(\.dismiss) private var dismiss
    @State private var password="";@State private var confirmation="";@State private var busy=false;@State private var success=false
    var body:some View {
        Canvas {
            Text("Nuova password per \(user.username)").font(.headline).lineLimit(1)
            Input(title:"Nuova password",text:$password,secure:true);Input(title:"Conferma password",text:$confirmation,secure:true)
            Spacer(minLength:0)
            MainButton(title:"Reimposta password",busy:busy,disabled:password.isEmpty || password != confirmation) {Task {busy=true;defer{busy=false};if await store.perform("admin/users/\(user.id)/password",body:["new_password":password]) {password="";confirmation="";success=true}}}
        }.navigationTitle("Reimposta password").alert("Password aggiornata",isPresented:$success) {Button("OK") {dismiss()}}
    }
}
struct RoomsScreen:View {
    @EnvironmentObject var store:Store
    @State private var search=""
    var body:some View {
        Canvas {
            Input(title:"Cerca stanza",text:$search)
            PagedRows(items:store.adminRooms.filter{search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)}) {room in
                NavigationLink {RoomDetail(original:room)} label:{HStack {VStack(alignment:.leading,spacing:4) {Text(room.name).foregroundStyle(sea).font(.headline).lineLimit(1);Text(room.isActive ? "Attiva" : "Disattivata").font(.caption).foregroundStyle(.secondary)};Spacer();Image(systemName:room.isActive ? "checkmark.circle.fill" : "pause.circle").foregroundStyle(room.isActive ? .green : .orange)}.padding(14)}.foregroundStyle(.primary)
            }
        }.navigationTitle("Stanze").toolbar {NavigationLink {CreateRoom()} label:{Image(systemName:"plus")}.accessibilityLabel("Crea stanza")}
    }
}
struct CreateRoom:View {
    @EnvironmentObject var store:Store
    @Environment(\.dismiss) private var dismiss
    @State private var name="";@State private var description="";@State private var busy=false
    var body:some View {
        Canvas {
            Input(title:"Nome stanza",text:$name);Input(title:"Descrizione (facoltativa)",text:$description)
            Spacer(minLength:0)
            MainButton(title:"Crea stanza",busy:busy,disabled:name.trimmingCharacters(in:.whitespaces).isEmpty) {Task {busy=true;defer{busy=false};if await store.perform("admin/rooms",body:["name":name,"description":description]) {dismiss()}}}
        }.navigationTitle("Nuova stanza")
    }
}
struct RoomDetail:View {
    let original:Room
    @EnvironmentObject var store:Store
    @Environment(\.dismiss) private var dismiss
    @State private var action="";@State private var confirm=false;@State private var busy=false
    var room:Room {store.adminRooms.first{$0.id == original.id} ?? original}
    var body:some View {
        Canvas {
            Card {Text(room.name).font(.title2.bold()).lineLimit(2);LabeledContent("Stato",value:room.isActive ? "Attiva" : "Disattivata");NavigationLink {TextPages(title:"Descrizione",text:room.description ?? "")} label:{DetailLink(label:"Descrizione",value:"Leggi")}}
            Text("Una stanza con prenotazioni collegate può essere disattivata; la cancellazione è consentita solo se non ha prenotazioni.").font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength:0)
            MainButton(title:room.isActive ? "Disattiva stanza" : "Riattiva stanza",busy:busy) {action="toggle";confirm=true}
            Button("Elimina stanza",role:.destructive) {action="delete";confirm=true}.frame(maxWidth:.infinity).disabled(busy)
        }.navigationTitle("Dettaglio stanza").confirmationDialog(action == "delete" ? "Eliminare questa stanza?" : "Cambiare lo stato della stanza?",isPresented:$confirm,titleVisibility:.visible) {
            Button("Conferma",role:action == "delete" ? .destructive : nil) {let selected=action;Task {busy=true;defer{busy=false};let path="admin/rooms/\(room.id)"+(selected == "toggle" ? "/toggle" : "");if await store.perform(path,method:selected == "delete" ? "DELETE" : "POST"),selected == "delete" {dismiss()}}}
        }
    }
}
