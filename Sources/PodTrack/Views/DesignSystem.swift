import SwiftUI
import PodTrackCore

extension RunMetadata {
    var heightLabel: String { verticalDrop.map { "\(formatted($0*100,1)) cm" } ?? "Unknown" }
}

enum PodTheme {
    static let teal = Color(red:0.23,green:0.82,blue:0.75)
    static let amber = Color(red:1,green:0.70,blue:0.32)
    static let panel = Color(nsColor:.controlBackgroundColor)
}

struct Panel<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var spacing: CGFloat = 14
    var padding: CGFloat = 18
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment:.leading,spacing:spacing) {
            HStack(alignment:.firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            content()
        }.padding(padding).frame(maxWidth:.infinity,alignment:.leading)
            .background(PodTheme.panel,in:RoundedRectangle(cornerRadius:12))
            .overlay(RoundedRectangle(cornerRadius:12).strokeBorder(.primary.opacity(0.07)))
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    var unit: String = ""
    var estimated = false
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment:.firstTextBaseline,spacing:5) {
                Text(value).font(.system(size:25,weight:.semibold,design:.rounded)).monospacedDigit()
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
            Text(estimated ? "ESTIMATED" : "OBSERVED").font(.system(size:9,weight:.semibold,design:.monospaced))
                .foregroundStyle(estimated ? PodTheme.amber : PodTheme.teal)
        }.frame(maxWidth:.infinity,alignment:.leading).padding(16)
            .background(PodTheme.panel,in:RoundedRectangle(cornerRadius:10))
    }
}

struct PageHeader: View {
    let eyebrow: String
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            Text(eyebrow.uppercased()).font(.system(size:10,weight:.bold,design:.monospaced)).tracking(2).foregroundStyle(PodTheme.teal)
            Text(title).font(.system(size:30,weight:.semibold,design:.rounded))
            Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}

struct Notice: View {
    let text: String
    var body: some View {
        Label(text,systemImage:"info.circle").font(.callout).foregroundStyle(PodTheme.amber)
            .padding(12).frame(maxWidth:.infinity,alignment:.leading)
            .background(PodTheme.amber.opacity(0.08),in:RoundedRectangle(cornerRadius:8))
    }
}

func formatted(_ value: Double, _ digits: Int = 2) -> String {
    value.isFinite ? String(format:"%.*f",digits,value) : "—"
}
