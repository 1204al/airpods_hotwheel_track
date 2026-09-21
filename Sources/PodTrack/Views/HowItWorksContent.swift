import Foundation
import PodTrackCore

enum GuideLanguage: String, CaseIterable, Identifiable {
    case english = "en", ukrainian = "uk"
    var id: String { rawValue }
    var label: String { self == .english ? "English" : "Українська" }
    func text(_ english: String, _ ukrainian: String) -> String {
        self == .english ? english : ukrainian
    }
}

enum GuideSection: String, CaseIterable, Identifiable {
    case overview, recording, motion
    var id: String { rawValue }
    func label(_ language: GuideLanguage) -> String {
        switch self {
        case .overview: return language.text("Overview", "Огляд")
        case .recording: return language.text("Record a run", "Запис заїзду")
        case .motion: return language.text("Motion explained", "Пояснення руху")
        }
    }
}

enum GuideStep: Int, CaseIterable, Identifiable {
    case sensors, mount, direction, speed, path, scale
    var id: Int { rawValue }
    var number: String { String(format: "%02d", rawValue + 1) }
    var icon: String {
        switch self {
        case .sensors: return "sensor"
        case .mount: return "airpodspro"
        case .direction: return "location.north.line"
        case .speed: return "waveform.path"
        case .path: return "point.topleft.down.curvedto.point.bottomright.up"
        case .scale: return "ruler"
        }
    }
    func label(_ l: GuideLanguage) -> String {
        switch self {
        case .sensors: return l.text("Sensors", "Датчики")
        case .mount: return l.text("Mount", "Кріплення")
        case .direction: return l.text("Direction", "Напрямок")
        case .speed: return l.text("Speed", "Швидкість")
        case .path: return l.text("Path", "Траєкторія")
        case .scale: return l.text("Scale", "Масштаб")
        }
    }
    func title(_ l: GuideLanguage) -> String {
        switch self {
        case .sensors: return l.text("The AirPod measures acceleration.", "Прискорення вимірює AirPod.")
        case .mount: return l.text("Teach us where forward is.", "Покажіть, де «вперед».")
        case .direction: return l.text("Follow the car’s nose.", "Стежимо за носом машинки.")
        case .speed: return l.text("Fit speed to the motion.", "Оцінюємо швидкість за рухом.")
        case .path: return l.text("Join the small movements.", "Складаємо малі переміщення.")
        case .scale: return l.text("Give the path its scale.", "Задаємо масштаб шляху.")
        }
    }
    func explanation(_ l: GuideLanguage) -> String {
        switch self {
        case .sensors:
            return l.text("The accelerometer senses acceleration along three axes; the gyroscope senses rotation. Apple’s Core Motion combines their signals and separates out gravity. PodTrack receives the processed motion data.",
                          "Акселерометр вимірює прискорення за трьома осями, гіроскоп — обертання. Core Motion від Apple поєднує їхні сигнали й відокремлює гравітацію. PodTrack отримує вже оброблені дані руху.")
        case .mount:
            return l.text("Fix one AirPod firmly to the car. Capture a level pose, then a nose-up pose. Gravity in those two poses reveals the car’s forward and up axes.",
                          "Жорстко закріпіть один AirPod на машинці. Збережіть рівне положення, потім — із піднятим носом. За напрямком тяжіння у двох позах визначаємо осі «вперед» і «вгору».")
        case .direction:
            return l.text("The saved mounting calibration turns the AirPod’s orientation into the car’s forward direction. PodTrack follows that direction in 3D, including slopes, turns and upside-down motion.",
                          "Збережене калібрування перетворює орієнтацію AirPod на напрямок машинки. PodTrack відстежує його у 3D: на схилах, у поворотах і навіть догори колесами.")
        case .speed:
            return l.text("The default Improved method combines forward acceleration with evidence from turns to estimate speed over time. Still periods at the recording’s edges can help correct drift when the rest setting is enabled.",
                          "Типовий метод Improved поєднує прискорення вперед із даними поворотів, щоб оцінити швидкість у часі. Нерухомі відрізки на початку й наприкінці запису допомагають зменшити дрейф, якщо ввімкнено умову спокою.")
        case .path:
            return l.text("For each time step, move along the estimated direction by speed × time. Joining these movements builds the centerline shown as a 3D track.",
                          "За кожен крок часу рухаємось у визначеному напрямку на відстань «швидкість × час». Сума цих переміщень утворює центральну лінію 3D-траси.")
        case .scale:
            return l.text("A measured height H or along-track length sets the physical scale. Without either measurement, the whole path is 1 relative unit. Add a measurement later to see estimates in metres and m/s.",
                          "Виміряна висота H або довжина вздовж траси задає фізичний масштаб. Без обох вимірів увесь шлях дорівнює 1 умовній одиниці. Додайте вимір пізніше, щоб отримати оцінки в метрах і м/с.")
        }
    }
    func takeaway(_ l: GuideLanguage) -> String {
        switch self {
        case .sensors: return l.text("Zero acceleration can mean a steady speed.", "Нульове прискорення можливе й під час руху.")
        case .mount: return l.text("Lift only the nose. Keep the same rigid mount.", "Піднімайте лише ніс. Не змінюйте кріплення.")
        case .direction: return l.text("We assume the car moves where its nose points.", "Припускаємо, що машинка їде туди, куди спрямований ніс.")
        case .speed: return l.text("Small acceleration errors grow into speed errors.", "Малі похибки прискорення накопичуються у швидкості.")
        case .path: return l.text("Position is estimated from motion, step by step.", "Положення оцінюємо з руху, крок за кроком.")
        case .scale: return l.text("H fixes scale. It does not prove the shape.", "H задає масштаб. Це не перевірка форми.")
        }
    }
    func input(_ l: GuideLanguage) -> String {
        switch self {
        case .sensors: return l.text("Accelerometer + gyroscope", "Акселерометр + гіроскоп")
        case .mount: return l.text("Two still poses", "Дві нерухомі пози")
        case .direction: return l.text("Orientation + gravity", "Орієнтація + гравітація")
        case .speed: return l.text("Acceleration + turning + time", "Прискорення + повороти + час")
        case .path: return l.text("Direction + speed + time", "Напрямок + швидкість + час")
        case .scale: return l.text("Measured height or length", "Виміряна висота або довжина")
        }
    }
    func output(_ l: GuideLanguage) -> String {
        switch self {
        case .sensors: return l.text("Acceleration, gravity, orientation", "Прискорення, гравітація, орієнтація")
        case .mount: return l.text("Car axes", "Осі машинки")
        case .direction: return l.text("3D direction", "Напрямок у 3D")
        case .speed: return l.text("Estimated speed", "Оцінена швидкість")
        case .path: return l.text("Estimated XYZ path", "Оцінена траєкторія XYZ")
        case .scale: return l.text("Path in metres", "Траєкторія в метрах")
        }
    }
    func formula(_ l: GuideLanguage) -> String {
        switch self {
        case .sensors: return "a_total = gravity + userAcceleration\n1 g ≈ 9.81 m/s²"
        case .mount: return "up = −g₀\nforward = −normalize(g₁ − (g₁ · g₀)g₀)"
        case .direction: return "d = (cos θ cos ψ, cos θ sin ψ, sin θ)"
        case .speed: return "Δv ≈ a_forward · Δt\na_normal ≈ v · (ω × forward)\nv ≥ 0"
        case .path: return "pᵢ = pᵢ₋₁ + ½(dᵢ₋₁vᵢ₋₁ + dᵢvᵢ) Δt"
        case .scale: return "k = H / (zₘₐₓ − zₘᵢₙ)\np′ = k · p     v′ = k · v"
        }
    }
    func detail(_ l: GuideLanguage) -> String {
        switch self {
        case .sensors:
            return l.text("CMHeadphoneMotionManager delivers motion from compatible headphones such as AirPods Pro. We read userAcceleration (X/Y/Z), gravity, rotationRate and attitude. Gravity and orientation are software estimates, not extra sensors. Acceleration arrives in g; we project it onto the calibrated forward axis and multiply by 9.80665 to obtain m/s². The speed estimator then resolves the sign and applies its corrections.",
                          "CMHeadphoneMotionManager передає рух сумісних навушників, зокрема AirPods Pro. Читаємо userAcceleration (X/Y/Z), gravity, rotationRate та attitude. Гравітація й орієнтація — програмні оцінки, а не окремі датчики. Прискорення надходить в одиницях g. Беремо його проєкцію на відкалібрований напрямок «вперед» і множимо на 9,80665 для переведення в м/с². Далі алгоритм швидкості визначає знак і застосовує поправки.")
        case .mount:
            return l.text("g₀ and g₁ are unit gravity vectors in the level and nose-up poses. Left and Right have separate saved calibrations. Recalibrate after moving the AirPod.",
                          "g₀ та g₁ — одиничні вектори гравітації у рівній позі та з піднятим носом. Лівий і правий AirPod мають окремі калібрування. Після зміни кріплення калібруйте знову.")
        case .direction:
            return l.text("θ is slope; ψ is horizontal heading. Improved smooths the full forward vector before deriving those angles, which avoids averaging headings across a vertical passage. Orientation is checked against gravity and rotation. X follows the initial heading, Y points left, Z points up; there is no north or Mac-relative position.",
                          "θ — нахил; ψ — горизонтальний курс. Improved згладжує повний вектор напрямку, а вже потім обчислює кути. Це усуває усереднення курсу під час проходження вертикалі. Орієнтація перевіряється за гравітацією й обертанням. X — початковий напрямок, Y — ліворуч, Z — вгору; прив’язки до півночі чи Mac немає.")
        case .speed:
            return l.text("Improved fits nonnegative speed to forward acceleration, turning acceleration and smoothness. Here ω is angular velocity and forward is the calibrated car axis. With the rest setting enabled, only supported still windows at the recording edges supply zero-speed constraints; quiet interior samples do not prove a stop. Matching repeated circuits can add return and shared-route constraints. These are experimental assumptions, not independent accuracy checks. Old remains available for comparison; it integrates acceleration and applies an endpoint correction.",
                          "Improved підбирає невід’ємну швидкість за прискоренням вперед, прискоренням у поворотах та умовою плавності. Тут ω — кутова швидкість, forward — відкалібрована вісь машинки. За ввімкненої умови спокою лише підтверджені нерухомі відрізки на краях запису задають нульову швидкість; тихі відрізки всередині не доводять зупинку. Схожі повторні кола можуть додати умови повернення та спільного маршруту. Це експериментальні припущення, а не незалежна перевірка точності. Old доступний для порівняння: він інтегрує прискорення й застосовує поправку на кінцеву швидкість.")
        case .path:
            return l.text("p is position, d is unit direction, v is speed, and Δt is elapsed time. We average the two neighbouring velocity vectors at each step. Track width, rails and supports are illustrative. A loose mount, sideways slide or airborne rotation breaks the direction assumption.",
                          "p — положення, d — одиничний напрямок, v — швидкість, Δt — проміжок часу. На кожному кроці усереднюємо два сусідні вектори швидкості. Ширина дороги, бортики й опори — ілюстрація. Рух кріплення, бічне ковзання та обертання в польоті порушують припущення про напрямок.")
        case .scale:
            return l.text("The lowest point is Z = 0. With measured H, the highest is Z = H; the finish can be elevated. With neither H nor length, total path length is normalized to 1 unit (u): distances use u and speeds u/s. A measured length alone sets uniform scale. With both measurements, length adjusts horizontal scale and slope. H alone cannot verify the shape; too little vertical motion prevents fitting H. Older runs can retain an endpoint-drop constraint.",
                          "Найнижча точка — Z = 0. За відомої H найвища — Z = H; фініш може бути вище нуля. Без H і довжини весь шлях дорівнює 1 умовній одиниці (u): відстані — в u, швидкості — в u/s. Відома довжина без H задає рівномірний масштаб. З обома вимірами довжина коригує горизонтальний масштаб і нахили. H не перевіряє форму; замалий вертикальний рух не дає підігнати H. Старі записи можуть зберігати умову перепаду між стартом і фінішем.")
        }
    }
}

/// Read-only educational fixture. Uses the production pipeline, never the run library.
enum GuideExample {
    static let height = 0.58
    static let result: AnalysisResult? = {
        let fixture = SimulatedTrack.generate(drop:height,includeJump:false,profile:.raisedFinish)
        let run = RunSession(source:.simulation,metadata:.init(trackName:"Learning example",verticalDrop:height),
                             calibration:fixture.calibration,samples:fixture.samples)
        return try? ReconstructionMethod.improved.analyze(run)
    }()
}
