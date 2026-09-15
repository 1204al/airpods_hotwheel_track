import SwiftUI
import PodTrackCore

struct HowItWorksView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("howItWorksLanguage") private var language = GuideLanguage.ukrainian
    var body: some View {
        HowItWorksPage(language:$language) { model.area = .record }
    }
}

struct HowItWorksPage: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var language: GuideLanguage
    @State private var step: GuideStep
    @State private var tilt = 28.0
    @State private var heading = 32.0
    @State private var slope = -18.0
    @State private var time = 3.0
    @State private var height = 58.0
    @State private var showMath = false
    @State private var showLimits = false
    @State private var sensorMotion: GuideSensorMotion
    var onRecord: () -> Void

    init(language: Binding<GuideLanguage>, initialStep: GuideStep = .sensors,
         initialHeight: Double = 58, initialSensorMotion: GuideSensorMotion = .still,
         onRecord: @escaping () -> Void = {}) {
        _language = language; _step = State(initialValue:initialStep)
        _height = State(initialValue:initialHeight); self.onRecord = onRecord
        _sensorMotion = State(initialValue:initialSensorMotion)
    }
    private func t(_ en: String, _ uk: String) -> String { language.text(en,uk) }
    private var accent: Color {
        colorScheme == .dark ? PodTheme.teal : Color(red:0.02,green:0.43,blue:0.37)
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment:.leading,spacing:24) {
                    header
                    steps
                    lesson(compact:geometry.size.width < 760)
                    accuracy
                    recording
                }
                .padding(28)
                .frame(maxWidth:1180)
                .frame(maxWidth:.infinity,alignment:.top)
            }
        }
        .tint(accent)
        .environment(\.locale,Locale(identifier:language.rawValue))
    }

    private var header: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Text(t("HOW PODTRACK WORKS", "ЯК ПРАЦЮЄ PODTRACK"))
                    .font(.system(size:10,weight:.bold,design:.monospaced)).tracking(2).foregroundStyle(accent)
                Spacer()
                Picker(t("Page language", "Мова сторінки"),selection:$language) {
                    ForEach(GuideLanguage.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width:210)
                .accessibilityIdentifier("guide-language")
            }
            Text(t("From motion to a track.", "Від руху до траєкторії."))
                .font(.system(size:34,weight:.semibold,design:.rounded))
                .fixedSize(horizontal:false,vertical:true)
            Text(t("One AirPod. An estimated 3D path. Add a measurement to set scale.",
                   "Один AirPod. Оцінена 3D-траєкторія. Додайте вимір для масштабу."))
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var steps: some View {
        HStack(spacing:8) {
            ForEach(GuideStep.allCases) { item in
                Button { step = item; showMath = false } label: {
                    VStack(alignment:.leading,spacing:10) {
                        HStack {
                            Text(item.number).font(.system(size:11,weight:.medium,design:.monospaced))
                            Spacer(minLength:2)
                            Image(systemName:item.icon).font(.system(size:15,weight:.medium))
                        }.foregroundStyle(step == item ? accent : .secondary)
                        Text(item.label(language)).font(.system(size:13,weight:step == item ? .semibold : .medium))
                            .foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.85)
                    }
                    .padding(13).frame(maxWidth:.infinity,alignment:.leading)
                    .background(step == item ? PodTheme.teal.opacity(0.10) : Color.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:12))
                    .overlay(RoundedRectangle(cornerRadius:12).strokeBorder(step == item ? PodTheme.teal.opacity(0.65) : Color.primary.opacity(0.07)))
                    .contentShape(RoundedRectangle(cornerRadius:12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.rawValue+1). \(item.label(language))")
                .accessibilityAddTraits(step == item ? .isSelected : [])
                .accessibilityIdentifier("guide-step-\(item.rawValue)")
            }
        }
    }

    private func lesson(compact: Bool) -> some View {
        VStack(alignment:.leading,spacing:0) {
            HStack {
                Label(t("INTERACTIVE EXAMPLE", "ІНТЕРАКТИВНИЙ ПРИКЛАД"),systemImage:"hand.draw")
                    .font(.system(size:10,weight:.semibold,design:.monospaced)).tracking(1)
                Spacer()
                Text(t("Illustrations & synthetic motion", "Схеми та синтетичний рух")).font(.caption)
            }.foregroundStyle(.secondary).padding(.horizontal,22).padding(.vertical,16)
            Divider().opacity(0.5)
            let layout = compact ? AnyLayout(VStackLayout(alignment:.leading,spacing:24)) : AnyLayout(HStackLayout(alignment:.top,spacing:28))
            layout {
                demonstration.frame(maxWidth:.infinity)
                explanation.frame(width:compact ? nil : 260,alignment:.leading)
            }.padding(22)
            Divider().opacity(0.5)
            HStack(alignment:.center,spacing:12) {
                VStack(alignment:.leading,spacing:4) {
                    Text(step.input(language)).foregroundStyle(.secondary)
                    Label(step.output(language),systemImage:"arrow.turn.down.right").foregroundStyle(accent)
                }.font(.caption.weight(.medium))
                Spacer(minLength:8)
                Button {
                    if let previous = GuideStep(rawValue:step.rawValue-1) { step = previous; showMath = false }
                } label: { Image(systemName:"arrow.left").frame(width:20,height:22) }
                    .disabled(step == .sensors)
                    .accessibilityLabel(t("Previous step", "Попередній крок"))
                Button {
                    step = GuideStep(rawValue:step.rawValue+1) ?? .sensors
                    showMath = false
                } label: {
                    Label(step == .scale ? t("Start again", "До початку") : t("Next step", "Далі"),
                          systemImage:step == .scale ? "arrow.counterclockwise" : "arrow.right")
                        .font(.callout.weight(.medium)).padding(.horizontal,14).padding(.vertical,9)
                        .foregroundStyle(Color.black.opacity(0.85))
                        .background(PodTheme.teal,in:RoundedRectangle(cornerRadius:8))
                }.buttonStyle(.plain)
            }.padding(.horizontal,22).padding(.vertical,16)
        }
        .background(PodTheme.panel,in:RoundedRectangle(cornerRadius:20))
        .overlay(RoundedRectangle(cornerRadius:20).strokeBorder(.primary.opacity(0.08)))
    }

    private var explanation: some View {
        VStack(alignment:.leading,spacing:16) {
            Text("\(step.number) / \(String(format:"%02d",GuideStep.allCases.count))")
                .font(.system(size:11,weight:.medium,design:.monospaced)).foregroundStyle(accent)
            Text(step.title(language)).font(.system(size:25,weight:.semibold,design:.rounded))
                .fixedSize(horizontal:false,vertical:true)
            Text(step.explanation(language)).font(.system(size:14)).lineSpacing(4)
                .foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            Rectangle().fill(PodTheme.teal.opacity(0.4)).frame(width:34,height:2)
            Text(step.takeaway(language)).font(.system(size:13,weight:.medium)).lineSpacing(3)
                .fixedSize(horizontal:false,vertical:true)
            DisclosureGroup(step == .sensors ? t("The data, briefly", "Коротко про дані") : t("The maths, briefly", "Коротко про математику"),isExpanded:$showMath) {
                VStack(alignment:.leading,spacing:10) {
                    Text(step.formula(language)).font(.system(size:11,design:.monospaced))
                        .textSelection(.enabled).padding(10).frame(maxWidth:.infinity,alignment:.leading)
                        .background(.primary.opacity(0.04),in:RoundedRectangle(cornerRadius:8))
                    Text(step.detail(language)).font(.caption).lineSpacing(3).foregroundStyle(.secondary)
                        .fixedSize(horizontal:false,vertical:true)
                    if step == .sensors {
                        Link(t("Apple: headphone motion", "Apple: дані руху навушників"),
                             destination:URL(string:"https://developer.apple.com/videos/play/wwdc2023/10179/")!)
                            .font(.caption)
                    }
                }.padding(.top,8)
            }.font(.caption.weight(.medium))
        }
    }

    @ViewBuilder private var demonstration: some View {
        switch step {
        case .sensors:
            GuideSensorsDiagram(language:language,motion:$sensorMotion)
        case .mount:
            VStack(spacing:18) {
                GuideMountDiagram(language:language,tilt:tilt).frame(height:245)
                guideSlider(t("Lift the nose", "Підніміть ніс"),value:$tilt,range:15...45,unit:"°",digits:0)
                Text(t("Hold each pose still for 1 second. Capture in Record Run.",
                       "Тримайте кожну позу 1 секунду. Збережіть її на сторінці запису."))
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading)
            }
        case .direction:
            VStack(spacing:18) {
                GuideDirectionDiagram(language:language,heading:heading,slope:slope).frame(height:230)
                guideSlider(t("Turn", "Поворот"),value:$heading,range:-75...75,unit:"°",digits:0)
                guideSlider(t("Slope", "Нахил"),value:$slope,range:-35...35,unit:"°",digits:0)
            }
        case .speed:
            if let result = GuideExample.result {
                VStack(spacing:18) {
                    GuideSpeedDiagram(language:language,result:result,time:time).frame(height:248)
                    timeSlider(result)
                    HStack {
                        guideValue(t("Estimated speed", "Оцінена швидкість"),value:"\(formatted(point(result).speed)) m/s",color:.orange)
                        Spacer()
                        guideValue(t("At both ends", "На обох кінцях"),value:"0 m/s",color:PodTheme.teal)
                    }
                }
            } else { unavailable }
        case .path:
            if let result = GuideExample.result {
                VStack(spacing:18) {
                    GuidePathDiagram(language:language,result:result,time:time,heightCentimetres:58,showScale:false).frame(height:270)
                    timeSlider(result)
                    HStack {
                        guideValue(t("Distance travelled", "Пройдений шлях"),value:"\(formatted(point(result).distance)) m",color:.orange)
                        Spacer()
                        guideValue(t("Height above ground", "Висота над низом траси"),value:"\(formatted(point(result).position.z*100,0)) cm",color:PodTheme.teal)
                    }
                }
            } else { unavailable }
        case .scale:
            if let result = GuideExample.result {
                VStack(spacing:18) {
                    GuidePathDiagram(language:language,result:result,time:time,heightCentimetres:height,showScale:true).frame(height:270)
                    guideSlider(t("Try a height H", "Змініть висоту H"),value:$height,range:29...87,unit:" cm",digits:0)
                    HStack(alignment:.top) {
                        guideValue(t("Scale vs 58 cm", "Масштаб до 58 см"),value:"\(formatted(height/58))×",color:PodTheme.teal)
                        Spacer(minLength:8)
                        guideValue(t("Path length", "Довжина шляху"),value:"\(formatted(result.metrics.estimatedPathLength*height/58)) m",color:.orange)
                        Spacer(minLength:8)
                        guideValue(t("Peak speed", "Макс. швидкість"),value:"\(formatted(result.metrics.estimatedMaximumSpeed*height/58)) m/s",color:.orange)
                    }
                    Text(t("This slider changes the example only.", "Повзунок змінює лише навчальний приклад."))
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading)
                }
            } else { unavailable }
        }
    }

    private var unavailable: some View {
        ContentUnavailableView(t("Example unavailable", "Приклад недоступний"),systemImage:"waveform",
                               description:Text(t("The educational simulation could not be reconstructed.", "Не вдалося відновити траєкторію навчальної симуляції.")))
    }
    private func point(_ result: AnalysisResult) -> TrackPoint {
        result.points.min(by:{ abs($0.time-time) < abs($1.time-time) }) ?? .init(time:0,position:.zero,speed:0,distance:0)
    }
    private func timeSlider(_ result: AnalysisResult) -> some View {
        guideSlider(t("Move through the run", "Перегляньте рух у часі"),value:$time,
                    range:0...max(0.01,result.metrics.recordingDuration),unit:" s",digits:2)
    }
    private func guideSlider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String, digits: Int) -> some View {
        VStack(spacing:5) {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(formatted(value.wrappedValue,digits)+unit).font(.system(.callout,design:.monospaced)).monospacedDigit()
            }
            Slider(value:value,in:range,step:digits == 0 ? 1 : 0.01).accessibilityLabel(label)
                .accessibilityValue(formatted(value.wrappedValue,digits)+unit)
        }
    }
    private func guideValue(_ title: String, value: String, color: Color) -> some View {
        VStack(alignment:.leading,spacing:5) {
            Text(title).font(.system(size:10)).foregroundStyle(.secondary)
            Text(value).font(.system(size:17,weight:.medium,design:.monospaced))
                .foregroundStyle(colorScheme == .dark ? color : (color == .orange ? Color(red:0.70,green:0.29,blue:0.02) : accent))
        }
    }

    private var accuracy: some View {
        VStack(alignment:.leading,spacing:15) {
            HStack(alignment:.top,spacing:18) {
                GuideAmbiguityDiagram().frame(width:115,height:58).accessibilityHidden(true)
                VStack(alignment:.leading,spacing:6) {
                    Text(t("Same height. Different possible paths.", "Одна висота. Різні можливі траєкторії."))
                        .font(.system(size:17,weight:.semibold,design:.rounded))
                    Text(t("AirPods do not supply position or speed. H sets one constraint; real-track accuracy has not yet been measured.",
                           "AirPods не передають положення чи швидкість. H задає одну умову; точність на реальній трасі ще не виміряна."))
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                }
            }
            DisclosureGroup(t("Where errors come from", "Звідки береться похибка"),isExpanded:$showLimits) {
                VStack(alignment:.leading,spacing:13) {
                    limit("location.north.line",t("Pointing ≠ travelling", "Напрямок носа ≠ напрямок руху"),
                          t("Sideways sliding, airborne rotation or a loose mount can bend the reconstructed path.",
                            "Бічне ковзання, обертання в польоті чи рух навушника в кріпленні спотворюють траєкторію."))
                    limit("waveform.path",t("Errors accumulate", "Похибки накопичуються"),
                          t("Sensor bias and heading drift build up with time. Endpoint corrections reduce them, but cannot recover the true motion.",
                            "Зміщення сенсора й дрейф курсу накопичуються в часі. Поправки на зупинки зменшують їх, але не відновлюють істинний рух."))
                    limit("ruler",t("Scale is not validation", "Масштаб не підтверджує точність"),
                          t("A matching H or track length does not verify the shape. Jumps and landings are candidates; road width and rails are illustrative.",
                            "Збіг H чи довжини не перевіряє форму. Стрибки й приземлення — припущення; ширина дороги й бортики — ілюстрація."))
                }.padding(.top,12)
            }.font(.caption.weight(.medium))
        }
        .padding(20).frame(maxWidth:.infinity,alignment:.leading)
        .background(PodTheme.amber.opacity(0.06),in:RoundedRectangle(cornerRadius:16))
        .overlay(RoundedRectangle(cornerRadius:16).strokeBorder(PodTheme.amber.opacity(0.18)))
    }
    private func limit(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment:.top,spacing:12) {
            Image(systemName:icon).frame(width:20).foregroundStyle(PodTheme.amber)
            VStack(alignment:.leading,spacing:4) {
                Text(title).font(.callout.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
        }
    }
    private var recording: some View {
        HStack(alignment:.center,spacing:18) {
            VStack(alignment:.leading,spacing:6) {
                Text(t("For a useful recording", "Для якісного запису")).font(.callout.weight(.semibold))
                Text(t("Rigid mount · visit both height extremes · 1 s still before and after the run.",
                       "Жорстке кріплення · проїзд через обидві крайні висоти · 1 с спокою до й після руху."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
            Spacer(minLength:0)
            Button(action:onRecord) {
                Label(t("Set up a run", "До запису"),systemImage:"record.circle")
            }.controlSize(.large)
        }.padding(.horizontal,2)
    }
}
