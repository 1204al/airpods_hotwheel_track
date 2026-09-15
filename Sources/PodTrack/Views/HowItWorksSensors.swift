import SwiftUI

enum GuideSensorMotion: String, CaseIterable, Identifiable {
    case still, steady, accelerating
    var id: String { rawValue }
    func label(_ l: GuideLanguage) -> String {
        switch self {
        case .still: return l.text("At rest", "Спокій")
        case .steady: return l.text("Steady speed", "Стала швидкість")
        case .accelerating: return l.text("Speeding up", "Розгін")
        }
    }
    func explanation(_ l: GuideLanguage) -> String {
        switch self {
        case .still:
            return l.text("On a table, the total signal is about 1 g. After gravity is removed, motion acceleration is about zero.",
                          "На столі загальний сигнал — близько 1 g. Після вилучення гравітації прискорення руху — близько нуля.")
        case .steady:
            return l.text("Moving straight at a steady speed also gives about zero motion acceleration. The car can still be moving.",
                          "За сталої швидкості по прямій прискорення руху теж близьке до нуля. Машинка при цьому може їхати.")
        case .accelerating:
            return l.text("During a straight-line speed-up, motion acceleration is nonzero. Here, 0.20 g is about 1.96 m/s².",
                          "Під час розгону по прямій прискорення руху ненульове. У цьому прикладі 0,20 g — приблизно 1,96 м/с².")
        }
    }
    var accelerationMagnitude: String { self == .accelerating ? "≈ 0.20 g" : "≈ 0 g" }
}

/// Illustrates the Core Motion data contract. The values are explanatory
/// magnitudes, not simulated signed samples or live headphone measurements.
struct GuideSensorsDiagram: View {
    let language: GuideLanguage
    @Binding var motion: GuideSensorMotion
    private let muted = Color(red:0.60,green:0.67,blue:0.72)
    private func t(_ en: String, _ uk: String) -> String { language.text(en,uk) }

    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            VStack(spacing:0) {
                HStack(alignment:.top,spacing:12) {
                    sensor(t("Accelerometer", "Акселерометр"),icon:"arrow.up.and.down.and.arrow.left.and.right",
                           detail:t("Acceleration on X/Y/Z.\nIncludes gravity.", "Прискорення за X/Y/Z.\nІз внеском гравітації."))
                    sensor(t("Gyroscope", "Гіроскоп"),icon:"arrow.triangle.2.circlepath",
                           detail:t("Rotation about X/Y/Z.\nHow fast the car turns.", "Обертання навколо X/Y/Z.\nЯк швидко повертається."))
                }
                connector(merging:true)
                VStack(spacing:5) {
                    Text("Core Motion").font(.system(size:15,weight:.semibold,design:.rounded)).foregroundStyle(.white)
                    Text(t("Combines the signals. Separates gravity.",
                           "Поєднує сигнали. Відокремлює гравітацію."))
                        .font(.system(size:11)).foregroundStyle(muted)
                        .multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
                }
                .padding(.horizontal,12).padding(.vertical,11).frame(maxWidth:.infinity)
                .background(PodTheme.teal.opacity(0.09),in:RoundedRectangle(cornerRadius:10))
                .overlay(RoundedRectangle(cornerRadius:10).strokeBorder(PodTheme.teal.opacity(0.35)))
                connector(merging:false)
                HStack(spacing:12) {
                    output(t("Gravity", "Гравітація"),field:"gravity",value:"≈ 1 g",color:.cyan)
                    output(t("Motion acceleration", "Прискорення руху"),field:"userAcceleration",
                           value:motion.accelerationMagnitude,color:PodTheme.teal)
                }
                Text(t("Illustrative magnitudes · orientation and rotation are also delivered.",
                       "Умовні величини · також отримуємо орієнтацію й обертання."))
                    .font(.system(size:10)).foregroundStyle(muted).multilineTextAlignment(.center)
                    .fixedSize(horizontal:false,vertical:true).padding(.top,12)
            }
            .padding(16).background(Color(red:0.045,green:0.075,blue:0.10),in:RoundedRectangle(cornerRadius:14))
            VStack(alignment:.leading,spacing:8) {
                Text(t("Compare three states", "Порівняйте три стани")).font(.caption).foregroundStyle(.secondary)
                Picker(t("Example motion", "Рух у прикладі"),selection:$motion) {
                    ForEach(GuideSensorMotion.allCases) { state in Text(state.label(language)).tag(state) }
                }
                .pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("guide-sensor-motion")
                Text(motion.explanation(language)).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal:false,vertical:true).lineSpacing(2)
                    .accessibilityIdentifier("guide-sensor-explanation")
            }
        }
    }
    private func sensor(_ title: String, icon: String, detail: String) -> some View {
        VStack(alignment:.leading,spacing:8) {
            Image(systemName:icon).font(.system(size:21,weight:.medium)).foregroundStyle(PodTheme.teal).accessibilityHidden(true)
            Text(title).font(.system(size:14,weight:.semibold)).foregroundStyle(.white)
            Text(detail).font(.system(size:11)).lineSpacing(2).foregroundStyle(muted)
                .fixedSize(horizontal:false,vertical:true)
        }
        .padding(12).frame(maxWidth:.infinity,alignment:.leading)
        .background(.white.opacity(0.035),in:RoundedRectangle(cornerRadius:10))
        .overlay(RoundedRectangle(cornerRadius:10).strokeBorder(.white.opacity(0.12)))
        .accessibilityElement(children:.combine)
    }
    private func output(_ title: String, field: String, value: String, color: Color) -> some View {
        VStack(alignment:.leading,spacing:5) {
            Text(title).font(.system(size:11,weight:.medium)).foregroundStyle(.white)
                .fixedSize(horizontal:false,vertical:true)
            Text(field).font(.system(size:9,design:.monospaced)).foregroundStyle(muted)
            Text(value).font(.system(size:22,weight:.medium,design:.monospaced)).foregroundStyle(color)
                .padding(.top,3).monospacedDigit()
        }
        .frame(maxWidth:.infinity,alignment:.leading).padding(12)
        .background(color.opacity(0.07),in:RoundedRectangle(cornerRadius:10))
        .overlay(RoundedRectangle(cornerRadius:10).strokeBorder(color.opacity(0.25)))
        .accessibilityElement(children:.combine)
    }
    private func connector(merging: Bool) -> some View {
        Canvas { context,size in
            let middle = size.width/2, branch = size.height/2
            var path = Path()
            if merging {
                for x in [size.width*0.25,size.width*0.75] {
                    path.move(to:.init(x:x,y:0)); path.addLine(to:.init(x:x,y:branch))
                    path.addLine(to:.init(x:middle,y:branch))
                }
                path.move(to:.init(x:middle,y:branch)); path.addLine(to:.init(x:middle,y:size.height-3))
            } else {
                path.move(to:.init(x:middle,y:0)); path.addLine(to:.init(x:middle,y:branch))
                for x in [size.width*0.25,size.width*0.75] {
                    path.move(to:.init(x:middle,y:branch)); path.addLine(to:.init(x:x,y:branch))
                    path.addLine(to:.init(x:x,y:size.height-3))
                }
            }
            for x in merging ? [middle] : [size.width*0.25,size.width*0.75] {
                path.move(to:.init(x:x-3,y:size.height-7)); path.addLine(to:.init(x:x,y:size.height-3))
                path.addLine(to:.init(x:x+3,y:size.height-7))
            }
            context.stroke(path,with:.color(PodTheme.teal.opacity(0.55)),style:.init(lineWidth:1.2,lineCap:.round,lineJoin:.round))
        }.frame(height:24).accessibilityHidden(true)
    }
}
