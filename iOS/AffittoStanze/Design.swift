import SwiftUI
import UIKit

let brand = Color(red: 0.30, green: 0.32, blue: 0.88)

struct Canvas<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(.horizontal, 18).padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
    }
}
struct Card<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10, content: content).padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}
struct MainButton: View {
    let title: String; var busy = false; var disabled = false; let action: () -> Void
    var body: some View {
        Button(action: action) { HStack { Spacer(); if busy { ProgressView().tint(.white) } else { Text(title).fontWeight(.semibold) }; Spacer() }.padding(.vertical, 14) }
            .foregroundStyle(.white).background(brand.opacity(disabled ? 0.4 : 1), in: RoundedRectangle(cornerRadius: 15))
            .disabled(disabled || busy)
    }
}
struct Input: View {
    let title: String; @Binding var text: String; var secure = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Group { if secure { SecureField(title, text: $text).textContentType(.newPassword) } else { TextField(title, text: $text).textInputAutocapitalization(.never).autocorrectionDisabled() } }
                .padding(12).background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier(title)
        }
    }
}
struct Pager: View {
    @Binding var page: Int; let pages: Int
    var body: some View {
        HStack {
            Button { page = max(0, page - 1) } label: { Image(systemName: "chevron.left").frame(width: 48, height: 44) }.disabled(page <= 0).accessibilityLabel("Pagina precedente")
            Spacer(); Text("\(min(page + 1, max(pages, 1))) / \(max(pages, 1))").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary); Spacer()
            Button { page = min(pages - 1, page + 1) } label: { Image(systemName: "chevron.right").frame(width: 48, height: 44) }.disabled(page >= pages - 1).accessibilityLabel("Pagina successiva")
        }
    }
}
struct PagedRows<Item: Identifiable, Row: View>: View {
    let items: [Item]; var empty = "Nessun risultato"; var rowHeight: CGFloat = 86
    @ViewBuilder let row: (Item) -> Row
    @State private var page = 0
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        GeometryReader { geo in
            let height = typeSize.isAccessibilitySize ? rowHeight * 1.5 : rowHeight
            let capacity = max(1, Int((geo.size.height - 54) / (height + 8)))
            let pages = max(1, Int(ceil(Double(items.count) / Double(capacity))))
            let current = min(page, pages - 1)
            VStack(spacing: 8) {
                if items.isEmpty { VStack(spacing: 10) { Image(systemName: "tray").font(.title); Text(empty).font(.subheadline) }.foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) }
                else {
                    ForEach(Array(items.dropFirst(current * capacity).prefix(capacity))) { item in
                        row(item).frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .leading)
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 17))
                    }
                    Spacer(minLength: 0)
                }
                Pager(page: Binding(get: {current}, set: {page = $0}), pages: pages)
            }.onChange(of: items.count) { _, _ in page = 0 }
        }
    }
}
struct Choice: Identifiable { let id: String; let title: String; var subtitle: String = "" }
struct ChoiceScreen: View {
    let title: String; let choices: [Choice]; @Binding var selection: String
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Canvas {
            Input(title: "Cerca", text: $search)
            PagedRows(items: choices.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }) { item in
                Button { selection = item.id; dismiss() } label: {
                    HStack { VStack(alignment: .leading, spacing: 4) { Text(item.title).fontWeight(.semibold).lineLimit(1); if !item.subtitle.isEmpty { Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) } }; Spacer(); if selection == item.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(brand) } }.padding(14)
                }.foregroundStyle(.primary)
            }
        }.navigationTitle(title)
    }
}
struct DetailLink: View {
    let label: String; let value: String
    var body: some View { HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).lineLimit(1); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }.font(.subheadline).padding(.vertical, 6) }
}
struct TextPages: View {
    let title: String; let text: String
    @State private var page = 0
    @ScaledMetric private var textSize: CGFloat = 17
    var body: some View {
        Canvas {
            GeometryReader { geo in
                let chunks = textChunks(text.isEmpty ? "Nessun testo" : text,width:geo.size.width,height:max(40,geo.size.height-58),size:textSize)
                let current = min(page,chunks.count-1)
                VStack { Text(chunks[current]).font(.system(size:textSize)).lineSpacing(4).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading);Pager(page:Binding(get:{current},set:{page=$0}),pages:chunks.count) }

            }
        }.navigationTitle(title)
    }
}

private func textChunks(_ text:String,width:CGFloat,height:CGFloat,size:CGFloat)->[String] {
    let chars=Array(text);var result:[String]=[];var offset=0
    let paragraph=NSMutableParagraphStyle();paragraph.lineSpacing=4
    let attributes:[NSAttributedString.Key:Any]=[.font:UIFont.systemFont(ofSize:size),.paragraphStyle:paragraph]
    while offset<chars.count {
        var low=1;var high=chars.count-offset;var best=1
        while low<=high {
            let count=(low+high)/2
            let segment=String(chars[offset..<(offset+count)])
            let rect=(segment as NSString).boundingRect(with:CGSize(width:max(10,width-2),height:.greatestFiniteMagnitude),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:attributes,context:nil)
            if ceil(rect.height)<=height-4 {best=count;low=count+1} else {high=count-1}
        }
        result.append(String(chars[offset..<(offset+best)]));offset+=best
    }
    return result.isEmpty ? [""] : result
}
