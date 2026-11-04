import SwiftUI
import UIKit

struct PDFShare:Identifiable {let id=UUID();let url:URL}
struct ReportShareSheet:UIViewControllerRepresentable {
    let url:URL
    func makeUIViewController(context:Context)->UIActivityViewController {UIActivityViewController(activityItems:[url],applicationActivities:nil)}
    func updateUIViewController(_ controller:UIActivityViewController,context:Context) {}
}
struct ReportsScreen:View {
    @EnvironmentObject var store:Store
    @State private var type="monthly";@State private var date=Date();@State private var userID=""
    @State private var report:Report?;@State private var loading=false;@State private var exporting=false;@State private var error:String?;@State private var loadedQuery:String?
    @State private var share:PDFShare?;@State private var loadID=UUID()
    var query:String {BookingClock.query([("type",type),("month",String(BookingClock.day(date).prefix(7))),("weekStart",BookingClock.day(date)),("userId",userID)])}
    var body:some View {
        Canvas {
            Picker("Periodo",selection:$type) {Text("Mensile").tag("monthly");Text("Settimanale").tag("weekly")}.pickerStyle(.segmented)
            Card {
                DatePicker(type == "monthly" ? "Mese" : "Dal giorno",selection:$date,displayedComponents:.date).datePickerStyle(.compact).environment(\.timeZone,BookingClock.timeZone).environment(\.calendar,BookingClock.calendar)
                if type == "monthly" {Text("Il report comprende tutto il mese selezionato.").font(.caption).foregroundStyle(.secondary)}
                NavigationLink {ChoiceScreen(title:"Filtra utente",choices:[Choice(id:"",title:"Tutti")]+store.adminUsers.filter{$0.role == "user"}.map{Choice(id:$0.id,title:$0.username,subtitle:$0.isActive ? "" : "Disattivato")},selection:$userID)} label:{DetailLink(label:"Utente",value:store.adminUsers.first{$0.id == userID}?.username ?? "Tutti")}
            }
            if loading {ProgressView("Caricamento report…").frame(maxWidth:.infinity,maxHeight:.infinity)}
            else if let error {Text(error).font(.subheadline).foregroundStyle(.red);Button("Riprova") {Task {await load()}};Spacer(minLength:0)}
            else if let report {
                HStack {VStack(alignment:.leading) {Text("\(report.totalHours.formatted()) ore").font(.headline).foregroundStyle(honey);Text("\(report.totalBookings) prenotazioni").font(.caption).foregroundStyle(.secondary)};Spacer();Text("\(BookingClock.label(report.startDate))\n\(BookingClock.label(report.endDate))").font(.caption).multilineTextAlignment(.trailing)}
                PagedRows(items:report.reportRows,empty:"Nessun dato nel periodo",rowHeight:70) {row in
                    HStack {Text(row.username).font(.subheadline.bold()).lineLimit(1);Spacer();VStack(alignment:.trailing,spacing:4) {Text("\(row.total_hours.formatted()) h").font(.headline).foregroundStyle(sea);Text("\(row.total_bookings) prenotazioni").font(.caption).foregroundStyle(.secondary)}}.padding(12)
                }
            } else {Spacer(minLength:0)}
            MainButton(title:"Esporta e condividi PDF",busy:exporting,disabled:loading || report == nil || loadedQuery != query) {Task {await export()}}
        }.navigationTitle("Report").onChange(of:type) {_,value in
            if value == "weekly" {let weekday=BookingClock.calendar.component(.weekday,from:date);date=BookingClock.calendar.date(byAdding:.day,value:-((weekday+5)%7),to:date) ?? date}
        }.task(id:query) {await load()}
            .sheet(item:$share,onDismiss:cleanPDF) {item in ReportShareSheet(url:item.url)}
    }
    @State private var sharedURL:URL?
    func cleanPDF() {if let sharedURL {try? FileManager.default.removeItem(at:sharedURL)};sharedURL=nil}
    func load() async {
        let id=UUID();loadID=id;let key=query;report=nil;loadedQuery=nil;loading=true;error=nil
        do {let result:Report=try await store.request("admin/reports?"+key);try Task.checkCancellation();guard loadID == id && query == key else{return};report=result;loadedQuery=key;loading=false}
        catch {guard loadID == id && query == key else{return};loading=false;if error is CancellationError || Task.isCancelled {return};self.error=error.localizedDescription}
    }
    func export() async {
        guard !exporting else{return};exporting=true;defer{exporting=false};let key=query
        do {let url=try await store.downloadReport(key);guard key == query else{try? FileManager.default.removeItem(at:url);return};cleanPDF();sharedURL=url;share=PDFShare(url:url)}
        catch is CancellationError {} catch {store.error=error.localizedDescription}
    }
}
