import SwiftUI

struct RunHeightSetupView: View {
    @EnvironmentObject var model: AppModel
    private var height: Double? {
        guard let cm = Double(model.dropCentimeters.replacingOccurrences(of:",",with:".")), cm.isFinite, cm>0, cm<=10000 else { return nil }
        return cm
    }
    var body: some View {
        Panel(title:"Track height H",subtitle:"Lowest → highest",spacing:8,padding:14) {
            HeightKnowledgePicker(isKnown:$model.heightIsKnown)
            if model.heightIsKnown {
            HStack(alignment:.center,spacing:18) {
                VStack(alignment:.leading,spacing:8) {
                    HStack(alignment:.center,spacing:8) {
                        TextField("58",text:$model.dropCentimeters)
                            .font(.system(size:28,weight:.semibold,design:.rounded)).monospacedDigit()
                            .textFieldStyle(.plain).frame(width:92,height:36)
                            .padding(.horizontal,8).padding(.vertical,2)
                            .background(Color.primary.opacity(0.04),in:RoundedRectangle(cornerRadius:8))
                            .overlay(RoundedRectangle(cornerRadius:8).strokeBorder(Color.primary.opacity(0.2)))
                            .accessibilityLabel("Track height H in centimetres")
                            .help("Enter the measured vertical distance from the lowest track point to the highest, or choose Unknown.")
                        HeightStepper(text:$model.dropCentimeters)
                        Text("cm").font(.title3).foregroundStyle(.secondary)
                    }
                }
                HeightGuide().frame(maxWidth:.infinity).frame(height:56)
            }
            HStack(spacing:14) {
                Text("Ground = 0 cm").foregroundStyle(PodTheme.teal)
                Text("Highest = \(height.map { formatted($0,1)+" cm" } ?? "H")").foregroundStyle(.orange)
            }.font(.caption)
            Text("Measure vertically, from the lowest point to the highest.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            if height == nil, !model.dropCentimeters.isEmpty {
                Text("Enter a height greater than 0 and no more than 10,000 cm.").font(.caption).foregroundStyle(.orange)
            }
            } else {
                Label("Approximate shape · scale unknown",systemImage:"point.topleft.down.curvedto.point.bottomright.up")
                    .font(.callout.weight(.medium)).foregroundStyle(PodTheme.teal)
                Text("The whole path = 1 relative unit (u). Add a measured height or track length later to get estimates in metres.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                if !model.knownLengthCentimeters.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
                    Text("A valid measured track length in advanced settings will set the scale instead.")
                        .font(.caption).foregroundStyle(PodTheme.amber).fixedSize(horizontal:false,vertical:true)
                }
            }
        }.disabled(model.recording)
    }
}

struct HeightKnowledgePicker: View {
    @Binding var isKnown: Bool
    var body: some View {
        Picker("Height H",selection:$isKnown) {
            Text("Measured").tag(true)
            Text("Unknown").tag(false)
        }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("Height H: measured or unknown")
    }
}

struct HeightStepper: View {
    @Binding var text: String
    private var current: Double? {
        guard let value = Double(text.replacingOccurrences(of:",",with:".")), value.isFinite, value>0, value<=10000 else { return nil }
        return value
    }
    var body: some View {
        Stepper("Height",onIncrement:action(1),onDecrement:action(-1))
            .labelsHidden().controlSize(.small).fixedSize()
            .help("Adjust height by 1 cm per click.")
            .accessibilityLabel("Adjust height by one centimetre")
            .accessibilityValue("\(text) centimetres")
    }
    private func action(_ delta: Double) -> (() -> Void)? {
        guard let value = current, value+delta>0, value+delta<=10000 else { return nil }
        return {
            guard let latest = current, latest+delta>0, latest+delta<=10000 else { return }
            let updated = latest+delta
            text = updated.rounded() == updated ? String(format:"%.0f",updated) : String(updated)
        }
    }
}

private struct HeightGuide: View {
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width, right = width-20.0
            let top = 4.0, bottom = geometry.size.height-4, middle = geometry.size.height/2
            Path { p in
                p.move(to:.init(x:0,y:top)); p.addLine(to:.init(x:right-16,y:top))
            }.stroke(.orange.opacity(0.7),style:.init(lineWidth:1.5,dash:[5,4]))
            Path { p in
                p.move(to:.init(x:0,y:bottom)); p.addLine(to:.init(x:right-16,y:bottom))
            }.stroke(PodTheme.teal.opacity(0.7),style:.init(lineWidth:1.5))
            Path { p in
                p.move(to:.init(x:right,y:top)); p.addLine(to:.init(x:right,y:bottom))
                p.move(to:.init(x:right-5,y:top+6)); p.addLine(to:.init(x:right,y:top)); p.addLine(to:.init(x:right+5,y:top+6))
                p.move(to:.init(x:right-5,y:bottom-6)); p.addLine(to:.init(x:right,y:bottom)); p.addLine(to:.init(x:right+5,y:bottom-6))
            }.stroke(.orange,style:.init(lineWidth:1.5,lineCap:.round,lineJoin:.round))
            Text("H").font(.caption.bold()).foregroundStyle(.orange).position(x:right+13,y:middle)
            Text("HIGHEST").font(.system(size:9,weight:.medium,design:.monospaced)).foregroundStyle(.orange).position(x:32,y:top+11)
            Text("GROUND").font(.system(size:9,weight:.medium,design:.monospaced)).foregroundStyle(PodTheme.teal).position(x:30,y:bottom-11)
        }.accessibilityHidden(true)
    }
}
