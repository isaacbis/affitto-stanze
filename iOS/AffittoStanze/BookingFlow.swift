import SwiftUI

struct TimeGrid:View {
    let values:[Double];let enabled:[Double];@Binding var selected:Double
    @State private var page=0
    var body:some View {
        let pages=max(1,Int(ceil(Double(values.count)/10)))
        let current=min(page,pages-1)
        VStack(spacing:10) {
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:6),count:5),spacing:8) {
                ForEach(Array(values.dropFirst(current*10).prefix(10)),id:\.self) {hour in
                    Button {selected=hour} label:{Text(timeLabel(hour)).font(.caption.weight(.semibold)).monospacedDigit().frame(maxWidth:.infinity).frame(height:40)
                        .foregroundStyle(selected == hour && enabled.contains(hour) ? .white : (enabled.contains(hour) ? Color.primary : Color.secondary))
                        .background(selected == hour && enabled.contains(hour) ? brand : (enabled.contains(hour) ? Color.green.opacity(0.14) : Color.gray.opacity(0.12)),in:RoundedRectangle(cornerRadius:10))}
                        .disabled(!enabled.contains(hour)).accessibilityLabel("\(timeLabel(hour)), \(enabled.contains(hour) ? "disponibile" : "non disponibile")")
                }
            }
            Pager(page:Binding(get:{current},set:{page=$0}),pages:pages)
        }
    }
}
struct NewBooking:View {
    @EnvironmentObject var store:Store
    @State private var room="";@State private var selectedUser="";@State private var date=Date()
    @State private var start=8.0;@State private var end=8.5;@State private var note=""
    @State private var slots:[Slot]=[];@State private var stage=0
    @State private var fetching=false;@State private var error:String?;@State private var loadedKey:String?;@State private var loadID=UUID()
    @State private var saving=false;@State private var success=false
    var admin:Bool {store.user?.role == "admin"}
    var titles:[String] {admin ? ["Stanza e data","Ora d’inizio","Ora di fine","Nota privata","Riepilogo"] : ["Stanza e data","Ora d’inizio","Ora di fine","Riepilogo"]}
    var selectionKey:String {room+"|"+BookingClock.day(date)}
    var starts:[Double] {(16..<41).map{Double($0)/2}.filter{h in BookingClock.start(date,hour:h)>Date() && !slots.contains{h<$0.end_hour && h+0.5>$0.start_hour}}}
    var ends:[Double] {guard starts.contains(start) else{return []};return (17...41).map{Double($0)/2}.filter{h in h>start && !slots.contains{start<$0.end_hour && h>$0.start_hour}}}
    var ready:Bool {!room.isEmpty && (!admin || !selectedUser.isEmpty) && !fetching && error == nil && loadedKey == selectionKey}
    var canContinue:Bool {switch stage {case 0:return ready && !starts.isEmpty;case 1:return ready && starts.contains(start);case 2:return ready && ends.contains(end);default:return ready && starts.contains(start) && ends.contains(end)}}
    var body:some View {
        Canvas {
            HStack {Text(titles[min(stage,titles.count-1)]).font(.headline);Spacer();Text("\(stage+1) / \(titles.count)").font(.caption).foregroundStyle(.secondary)}
            ProgressView(value:Double(stage+1),total:Double(titles.count)).tint(brand)
            if stage == 0 {
                Card {
                    NavigationLink {ChoiceScreen(title:"Scegli stanza",choices:store.rooms.map{Choice(id:$0.id,title:$0.name)},selection:$room)} label:{DetailLink(label:"Stanza",value:store.rooms.first{$0.id == room}?.name ?? "Seleziona")}.accessibilityIdentifier("booking.room")
                    if admin {NavigationLink {ChoiceScreen(title:"Scegli utente",choices:store.users.map{Choice(id:$0.id,title:$0.username)},selection:$selectedUser)} label:{DetailLink(label:"Utente",value:store.users.first{$0.id == selectedUser}?.username ?? "Seleziona")}.accessibilityIdentifier("booking.user")}
                    DatePicker("Data",selection:$date,in:BookingClock.calendar.startOfDay(for:Date())...,displayedComponents:.date).datePickerStyle(.compact).environment(\.timeZone,BookingClock.timeZone).environment(\.calendar,BookingClock.calendar)
                }
                Text("Date e orari di Roma").font(.caption).foregroundStyle(.secondary)
                if fetching {ProgressView("Verifica disponibilità…")}
                else if let error {Text(error).font(.caption).foregroundStyle(.red);Button("Riprova") {Task {await loadSlots()}}}
                else if ready {Text(starts.isEmpty ? "Nessuna fascia futura disponibile. Scegli un’altra data." : "\(starts.count) fasce di mezz’ora disponibili.").font(.subheadline).foregroundStyle(.secondary)}
            } else if stage == 1 {
                Text("\(store.rooms.first{$0.id == room}?.name ?? "") · \(BookingClock.label(BookingClock.day(date)))").font(.subheadline).lineLimit(2)
                TimeGrid(values:(16..<41).map{Double($0)/2},enabled:starts,selected:$start)
                Text("Verde: disponibile · Grigio: occupato o passato").font(.caption).foregroundStyle(.secondary)
            } else if stage == 2 {
                Text("Inizio alle \(timeLabel(start)). Scegli quando terminare.").font(.subheadline)
                TimeGrid(values:(17...41).map{Double($0)/2}.filter{$0>start},enabled:ends,selected:$end)
                Text("Durata: \((end-start).formatted()) ore").font(.subheadline).foregroundStyle(.secondary)
            } else if admin && stage == 3 {
                Text("Questa nota sarà visibile solo agli amministratori.").font(.subheadline).foregroundStyle(.secondary)
                Input(title:"Nota privata (facoltativa)",text:$note).onChange(of:note) {_,v in if v.count>1000 {note=String(v.prefix(1000))}}
                Text("\(note.count) / 1000 caratteri").font(.caption).foregroundStyle(.secondary)
            } else {
                Card {
                    Text(store.rooms.first{$0.id == room}?.name ?? "Stanza").font(.title3.bold()).lineLimit(2)
                    Text(BookingClock.label(BookingClock.day(date)))
                    Label("\(timeLabel(start)) – \(timeLabel(end))",systemImage:"clock")
                    if admin {LabeledContent("Utente",value:store.users.first{$0.id == selectedUser}?.username ?? "")}
                    if !note.isEmpty {Text("Nota privata aggiunta").font(.caption).foregroundStyle(.secondary)}
                }
                Text("La disponibilità viene ricontrollata alla conferma.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength:0)
            MainButton(title:stage == titles.count-1 ? "Conferma prenotazione" : "Continua",busy:saving,disabled:!canContinue) {
                if stage == titles.count-1 {Task {await create()}}
                else {if stage == 0 && !starts.contains(start) {start=starts.first ?? 8};if stage == 1 && !ends.contains(end) {end=ends.first ?? start+0.5};stage+=1}
            }
            if stage>0 {Button("Indietro") {stage-=1}.frame(maxWidth:.infinity).disabled(saving)}
        }.navigationTitle("Prenota stanza").task(id:selectionKey) {await loadSlots()}
            .alert("Prenotazione inserita",isPresented:$success) {Button("OK",role:.cancel){}}
    }
    func loadSlots() async {
        let id=UUID();loadID=id;let key=selectionKey
        slots=[];error=nil;loadedKey=nil
        guard !room.isEmpty else{fetching=false;return}
        fetching=true
        do {
            let response:[Slot]=try await store.request("availability?"+BookingClock.query([("room_id",room),("booking_date",BookingClock.day(date))]))
            try Task.checkCancellation();guard loadID == id && selectionKey == key else{return}
            slots=response;fetching=false;loadedKey=key
            if !starts.contains(start){start=starts.first ?? 8};if !ends.contains(end){end=ends.first ?? start+0.5}
        } catch {
            guard loadID == id && selectionKey == key else{return};fetching=false
            if error is CancellationError || Task.isCancelled {return}
            self.error="Disponibilità non verificata. Riprova."
        }
    }
    func create() async {
        guard !saving && canContinue else{return};saving=true;defer{saving=false}
        var body:[String:Any]=["room_id":room,"booking_date":BookingClock.day(date),"start_hour":start,"end_hour":end]
        if admin {body["user_id"]=selectedUser;body["admin_note"]=note}
        if await store.perform("bookings",body:body) {note="";stage=0;success=true}
        await loadSlots()
    }
}
