import SwiftUI

struct GuideOverview: View {
    let language: GuideLanguage
    let compact: Bool
    let accent: Color
    var onRecordingGuide: () -> Void
    var onMotion: () -> Void
    private func t(_ en: String, _ uk: String) -> String { language.text(en,uk) }

    var body: some View {
        VStack(alignment:.leading,spacing:24) {
            VStack(alignment:.leading,spacing:10) {
                Label(t("A motion lab for your Hot Wheels car.", "Лабораторія руху для вашої машинки Hot Wheels."),systemImage:"car.side")
                    .font(.system(size:24,weight:.semibold,design:.rounded))
                Text(t("Fix one AirPod to the car, record a run, then explore the motion and an estimated 3D track on your Mac.",
                       "Закріпіть один AirPod на машинці, запишіть заїзд і дослідіть рух та оцінену 3D-трасу на Mac."))
                    .font(.callout).foregroundStyle(.secondary).lineSpacing(3)
                    .fixedSize(horizontal:false,vertical:true)
            }
            let layout = compact ? AnyLayout(VStackLayout(alignment:.leading,spacing:12)) : AnyLayout(HStackLayout(alignment:.top,spacing:12))
            layout {
                journey("01",icon:"airpodspro",title:t("Record motion", "Запишіть рух"),
                        detail:t("Connect one AirPod and calibrate its position on the car.",
                                 "Під’єднайте один AirPod і відкалібруйте його кріплення на машинці."))
                journey("02",icon:"point.3.connected.trianglepath.dotted",title:t("Estimate the track", "Відновіть трасу"),
                        detail:t("PodTrack combines direction and estimated speed into a 3D path.",
                                 "PodTrack поєднує напрямок та оцінену швидкість у 3D-траєкторію."))
                journey("03",icon:"chart.xyaxis.line",title:t("Explore the run", "Дослідіть заїзд"),
                        detail:t("Replay, inspect graphs, compare saved runs and export the data.",
                                 "Відтворюйте рух, переглядайте графіки, порівнюйте заїзди й експортуйте дані."))
            }.fixedSize(horizontal:false,vertical:true)
            let evidenceLayout = compact ? AnyLayout(VStackLayout(alignment:.leading,spacing:12)) : AnyLayout(HStackLayout(alignment:.top,spacing:16))
            evidenceLayout {
                evidence(icon:"waveform.path",title:t("Recorded from AirPods", "Записано з AirPods"),
                         detail:t("Acceleration, rotation, orientation and timestamps. These are already processed by Apple’s Core Motion.",
                                  "Прискорення, обертання, орієнтація та час. Ці дані вже оброблені Core Motion від Apple."),color:accent)
                evidence(icon:"cube.transparent",title:t("Estimated by PodTrack", "Оцінено PodTrack"),
                         detail:t("Track shape, speed and distance. AirPods do not report position or speed, and reconstruction can drift.",
                                  "Форма траси, швидкість та відстань. AirPods не передають положення чи швидкість, а похибка відновлення може накопичуватися."),color:accent)
            }
            HStack(alignment:.top,spacing:14) {
                Image(systemName:"ruler").font(.title2).foregroundStyle(accent).accessibilityHidden(true)
                VStack(alignment:.leading,spacing:6) {
                    Text(t("A measurement gives the track its scale.", "Вимір задає масштаб траси."))
                        .font(.callout.weight(.semibold))
                    Text(t("Enter a measured height or track length for metres and m/s. Leave both unknown to explore the shape in relative units; you can add a measurement later. Scale does not verify the shape.",
                           "Вкажіть виміряну висоту або довжину траси для метрів і м/с. Без обох вимірів форма відображається в умовних одиницях; вимір можна додати пізніше. Масштаб не підтверджує точність форми."))
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                }
            }.padding(18).frame(maxWidth:.infinity,alignment:.leading)
                .background(accent.opacity(0.07),in:RoundedRectangle(cornerRadius:14))
            HStack(spacing:12) {
                Button(action:onRecordingGuide) {
                    Label(t("Prepare your first run", "Підготуйте перший заїзд"),systemImage:"arrow.right")
                }.buttonStyle(.borderedProminent).controlSize(.large)
                    .accessibilityIdentifier("guide-prepare-run")
                Button(t("Explore the motion", "Дослідіть рух"),action:onMotion)
                    .controlSize(.large).accessibilityIdentifier("guide-explore-motion")
            }
            Label(t("Recordings and analysis stay on this Mac. No account or cloud service needed.",
                    "Записи й аналіз залишаються на цьому Mac. Обліковий запис і хмарний сервіс не потрібні."),systemImage:"internaldrive")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }
    }

    private func journey(_ number: String, icon: String, title: String, detail: String) -> some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Image(systemName:icon).font(.title2)
                Spacer()
                Text(number).font(.system(.caption,design:.monospaced))
            }.foregroundStyle(accent).accessibilityHidden(true)
            Text(title).font(.headline)
            Text(detail).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal:false,vertical:true)
        }.padding(18).frame(maxWidth:.infinity,maxHeight:compact ? nil : .infinity,alignment:.topLeading)
            .background(PodTheme.panel,in:RoundedRectangle(cornerRadius:14))
            .overlay(RoundedRectangle(cornerRadius:14).strokeBorder(.primary.opacity(0.08)))
            .accessibilityElement(children:.combine)
    }

    private func evidence(icon: String, title: String, detail: String, color: Color) -> some View {
        VStack(alignment:.leading,spacing:9) {
            Label(title,systemImage:icon).font(.callout.weight(.semibold)).foregroundStyle(color)
            Text(detail).font(.callout).foregroundStyle(.secondary).lineSpacing(2)
                .fixedSize(horizontal:false,vertical:true)
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}

struct GuideRecordingWalkthrough: View {
    let language: GuideLanguage
    let accent: Color
    var onRecord: () -> Void
    var onDiagnostics: () -> Void
    private func t(_ en: String, _ uk: String) -> String { language.text(en,uk) }

    var body: some View {
        VStack(alignment:.leading,spacing:22) {
            VStack(alignment:.leading,spacing:8) {
                Text(t("Your first run, step by step.", "Перший заїзд, крок за кроком."))
                    .font(.system(size:24,weight:.semibold,design:.rounded))
                Text(t("You need a Mac, compatible AirPods and a rigid mount for one toy car. A ruler or tape measure is optional.",
                       "Потрібні Mac, сумісні AirPods та жорстке кріплення для однієї машинки. Лінійка або рулетка — за бажанням."))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
            VStack(alignment:.leading,spacing:20) {
                instruction(1,title:t("Connect and check the selected AirPod", "Під’єднайте й перевірте обраний AirPod"),
                            detail:t("Open Record and choose Right or Left. Move that AirPod and wait for fresh motion from the same side. macOS chooses which bud streams; the side selector tells PodTrack which one to accept.",
                                     "Відкрийте Record та оберіть Right або Left. Порухайте цим навушником і дочекайтеся свіжих даних саме від нього. macOS обирає джерело потоку; перемикач указує PodTrack, дані якого боку приймати."))
                Divider()
                instruction(2,title:t("Fix the mount and capture two poses", "Закріпіть навушник і збережіть дві пози"),
                            detail:t("Keep the AirPod fixed to the car. Capture the car level, then with its nose raised 15–45° and no sideways tilt. Hold still after each click until the pose is accepted. Recalibrate whenever the mount moves.",
                                     "AirPod має бути нерухомим відносно машинки. Збережіть рівну позу, потім підніміть ніс на 15–45° без бічного нахилу. Після кожного натискання тримайте позу до підтвердження. Якщо кріплення змістилося, повторіть калібрування."))
                Divider()
                instruction(3,title:t("Add a measurement, if you have one", "Додайте вимір, якщо він відомий"),
                            detail:t("H is the vertical distance between the lowest and highest track points visited by the car. Track length is measured along the route and can be entered in Notes & advanced settings. Leave Unknown selected when you have no measurement.",
                                     "H — вертикальна відстань між найнижчою та найвищою точками траси, які відвідує машинка. Довжину вимірюють уздовж маршруту та вводять у Notes & advanced settings. Якщо виміру немає, залиште Unknown."))
                Divider()
                instruction(4,title:t("Record from rest, then stop and save", "Запишіть рух зі спокою та збережіть"),
                            detail:t("Start recording, hold still for 1 second, then release the car. Keep recording for 1 second after it stops and choose Stop & save. Open the run in Runs for 3D Track, Analysis, replay and export. Record cars one at a time to compare them later.",
                                     "Почніть запис, потримайте машинку нерухомо 1 секунду та відпустіть. Після зупинки зачекайте ще 1 секунду й натисніть Stop & save. Відкрийте заїзд у Runs для 3D Track, Analysis, відтворення й експорту. Записуйте машинки по черзі, щоб потім порівняти їх."))
            }.padding(22).background(PodTheme.panel,in:RoundedRectangle(cornerRadius:16))
                .overlay(RoundedRectangle(cornerRadius:16).strokeBorder(.primary.opacity(0.08)))
            HStack(spacing:12) {
                Button(action:onRecord) {
                    Label(t("Open recording", "Відкрити запис"),systemImage:"record.circle")
                }.buttonStyle(.borderedProminent).controlSize(.large)
                    .accessibilityIdentifier("guide-open-recording")
                Text(t("Your setup continues in Record.", "Налаштування продовжується в Record."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment:.leading,spacing:14) {
                Text(t("Need a hand?", "Потрібна допомога?"))
                    .font(.system(size:18,weight:.semibold,design:.rounded))
                DisclosureGroup(t("No motion is arriving", "Дані руху не надходять")) {
                    VStack(alignment:.leading,spacing:10) {
                        Text(t("Check the selected side and the reported stream in Device. If ear detection is stopping motion, follow the connection screen’s setup guide, then retry. An active connection alone does not mean motion samples are arriving.",
                               "Перевірте обраний бік і фактичний потік у Device. Якщо виявлення вуха зупиняє потік, скористайтеся інструкцією на екрані підключення та повторіть спробу. Активне підключення ще не означає, що дані руху надходять."))
                        Button(t("Open device diagnostics", "Відкрити діагностику"),action:onDiagnostics)
                            .accessibilityIdentifier("guide-open-diagnostics")
                    }.padding(.top,8)
                }
                DisclosureGroup(t("A saved run has no 3D track", "Збережений заїзд не має 3D-траси")) {
                    Text(t("Raw only · no 3D saves sensor data without mounting calibration. For a new 3D run, turn it off and calibrate before recording. Other runs may lack usable motion; check the explanation shown for that run. An unknown height alone does not prevent reconstruction.",
                           "Raw only · no 3D зберігає дані без калібрування кріплення. Для нового 3D-заїзду вимкніть цей режим і виконайте калібрування перед записом. Інші записи можуть не мати придатних даних руху — перевірте пояснення в заїзді. Сама по собі невідома висота не заважає відновленню."))
                        .padding(.top,8)
                }
                DisclosureGroup(t("Try the app without AirPods", "Спробуйте без AirPods")) {
                    Text(t("Choose Simulation in the sidebar, then open Record and click Simulate & record. This saves a synthetic example in Runs. Switch back to AirPods when you want to record real motion.",
                           "Оберіть Simulation на бічній панелі, відкрийте Record та натисніть Simulate & record. Синтетичний приклад збережеться в Runs. Поверніться до AirPods для запису справжнього руху."))
                        .padding(.top,8)
                }
            }.font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal:false,vertical:true)
        }
    }

    private func instruction(_ number: Int, title: String, detail: String) -> some View {
        HStack(alignment:.top,spacing:16) {
            Text("\(number)").font(.system(.callout,design:.monospaced).weight(.semibold))
                .foregroundStyle(accent).frame(width:30,height:30)
                .background(accent.opacity(0.1),in:Circle())
            VStack(alignment:.leading,spacing:7) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).lineSpacing(3)
                    .fixedSize(horizontal:false,vertical:true)
            }
        }.frame(maxWidth:.infinity,alignment:.leading).accessibilityElement(children:.combine)
    }
}
