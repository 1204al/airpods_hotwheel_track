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
        case .speed: return l.text("Add up the acceleration.", "Накопичуємо прискорення.")
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
            return l.text("Core Motion supplies orientation, rotation and acceleration. We use orientation to find the turn, and gravity to find the slope. Together they give a direction in 3D.",
                          "Core Motion передає орієнтацію, обертання й прискорення. З орієнтації визначаємо поворот, із гравітації — нахил. Разом вони задають напрямок у 3D.")
        case .speed:
            return l.text("We take the AirPod’s acceleration along the car’s forward axis and add its effect on speed over time. Assuming the car starts and ends at rest helps us reduce accumulated error.",
                          "Беремо прискорення AirPod уздовж машинки й накопичуємо його вплив на швидкість у часі. Припущення про спокій на початку та наприкінці допомагає зменшити накопичену похибку.")
        case .path:
            return l.text("For each time step, move along the estimated direction by speed × time. Joining these movements builds the centerline shown as a 3D track.",
                          "За кожен крок часу рухаємось у визначеному напрямку на відстань «швидкість × час». Сума цих переміщень утворює центральну лінію 3D-траси.")
        case .scale:
            return l.text("Measure H between the lowest and highest track points to set scale. Choose Unknown to see an approximate shape in relative units. Add H later to estimate metres and m/s.",
                          "Виміряйте H між найнижчою та найвищою точками для масштабу. Оберіть Unknown, щоб побачити приблизну форму в умовних одиницях. Додайте H пізніше для оцінок у метрах і м/с.")
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
        case .speed: return l.text("Acceleration + time", "Прискорення + час")
        case .path: return l.text("Direction + speed + time", "Напрямок + швидкість + час")
        case .scale: return l.text("Measured height H", "Виміряна висота H")
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
        case .speed: return "vᵢ = vᵢ₋₁ + ½(aᵢ₋₁ + aᵢ) Δt"
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
            return l.text("θ is slope; ψ is horizontal heading. Heading comes from the orientation quaternion, checked against gravity and rotation. X follows the initial heading, Y points left, Z points up. There is no north or Mac-relative position.",
                          "θ — нахил; ψ — горизонтальний курс. Курс отримуємо з кватерніона орієнтації, перевіреного за гравітацією й обертанням. X — початковий напрямок, Y — ліворуч, Z — вгору. Прив’язки до півночі чи Mac немає.")
        case .speed:
            return l.text("We remove the resting offset and infer acceleration sign from the early descent. A slope-and-rolling-resistance model contributes up to 20% by default, less when it disagrees with the sensor and zero in possible free fall. With end-rest enabled, a constant acceleration correction makes the integrated end speed zero; speed is then clipped nonnegative and smoothed. Initial speed is assumed zero even with end-rest off.",
                          "Віднімаємо зміщення у спокої та визначаємо знак прискорення за початковим спуском. Модель схилу й опору коченню має до 20% ваги за замовчуванням; менше за розбіжностей із сенсором і нуль у можливому вільному падінні. За умови зупинки наприкінці стала поправка прискорення зводить кінцеву інтегровану швидкість до нуля. Далі прибираємо від’ємні значення й згладжуємо. Початкова швидкість завжди приймається за нуль.")
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
        return try? AnalysisPipeline.analyze(run)
    }()
}
