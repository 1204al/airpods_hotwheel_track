import SwiftUI
import Charts
import PodTrackCore

private enum GuideInk {
    static let background = Color(red:0.045,green:0.075,blue:0.10)
    static let muted = Color(red:0.57,green:0.65,blue:0.70)
    static let track = Color(red:1,green:0.57,blue:0.22)

    static func grid(_ context: inout GraphicsContext, size: CGSize) {
        var path = Path()
        for x in stride(from:CGFloat(20),through:size.width,by:24) {
            for y in stride(from:CGFloat(20),through:size.height,by:24) {
                path.addEllipse(in:CGRect(x:x,y:y,width:1.4,height:1.4))
            }
        }
        context.fill(path,with:.color(.white.opacity(0.10)))
    }
    static func line(_ context: inout GraphicsContext, from: CGPoint, to: CGPoint,
                     color: Color, width: CGFloat = 1, dashed: Bool = false) {
        var path = Path(); path.move(to:from); path.addLine(to:to)
        context.stroke(path,with:.color(color),style:StrokeStyle(lineWidth:width,lineCap:.round,dash:dashed ? [4,5] : []))
    }
    static func arrow(_ context: inout GraphicsContext, from: CGPoint, to: CGPoint, color: Color, width: CGFloat = 2) {
        line(&context,from:from,to:to,color:color,width:width)
        let angle = atan2(to.y-from.y,to.x-from.x), length: CGFloat = 7
        var head = Path()
        head.move(to:CGPoint(x:to.x-length*cos(angle-0.48),y:to.y-length*sin(angle-0.48)))
        head.addLine(to:to)
        head.addLine(to:CGPoint(x:to.x-length*cos(angle+0.48),y:to.y-length*sin(angle+0.48)))
        context.stroke(head,with:.color(color),style:.init(lineWidth:width,lineCap:.round,lineJoin:.round))
    }
    static func text(_ context: inout GraphicsContext, _ text: String, at: CGPoint,
                     color: Color = .white, size: CGFloat = 11, anchor: UnitPoint = .center) {
        context.draw(Text(text).font(.system(size:size,weight:.medium,design:.monospaced)).foregroundColor(color),
                     at:at,anchor:anchor)
    }
    static func dot(_ context: inout GraphicsContext, at: CGPoint, color: Color, radius: CGFloat = 4) {
        context.fill(Path(ellipseIn:CGRect(x:at.x-radius*2.5,y:at.y-radius*2.5,width:radius*5,height:radius*5)),with:.color(color.opacity(0.12)))
        context.fill(Path(ellipseIn:CGRect(x:at.x-radius,y:at.y-radius,width:radius*2,height:radius*2)),with:.color(color))
    }
    static func car(_ context: GraphicsContext, at: CGPoint, angle: Double, width: CGFloat, topDown: Bool = false) {
        var c = context
        c.translateBy(x:at.x,y:at.y); c.rotate(by:.degrees(angle))
        let factor = width/100
        c.scaleBy(x:factor,y:factor)
        if topDown {
            for x: CGFloat in [-29,26] {
                for y: CGFloat in [-23,18] {
                    c.fill(Path(roundedRect:CGRect(x:x-8,y:y,width:16,height:7),cornerRadius:3),with:.color(GuideInk.muted))
                }
            }
            c.fill(Path(roundedRect:CGRect(x:-49,y:-21,width:98,height:42),cornerRadius:12),with:.color(track.opacity(0.20)))
            c.stroke(Path(roundedRect:CGRect(x:-49,y:-21,width:98,height:42),cornerRadius:12),with:.color(track),lineWidth:1.5)
            c.fill(Path(roundedRect:CGRect(x:7,y:-16,width:17,height:32),cornerRadius:4),with:.color(track.opacity(0.40)))
        } else {
            var body = Path()
            body.move(to:.init(x:-49,y:4)); body.addLine(to:.init(x:-45,y:-14))
            body.addLine(to:.init(x:-21,y:-17)); body.addLine(to:.init(x:-8,y:-29))
            body.addLine(to:.init(x:16,y:-29)); body.addLine(to:.init(x:30,y:-15))
            body.addLine(to:.init(x:47,y:-9)); body.addLine(to:.init(x:49,y:4)); body.closeSubpath()
            c.fill(body,with:.color(track.opacity(0.22)))
            c.stroke(body,with:.color(track),style:.init(lineWidth:1.5,lineJoin:.round))
            for x: CGFloat in [-29,29] {
                c.fill(Path(ellipseIn:CGRect(x:x-10,y:-3,width:20,height:20)),with:.color(background))
                c.stroke(Path(ellipseIn:CGRect(x:x-10,y:-3,width:20,height:20)),with:.color(muted),lineWidth:2)
                c.fill(Path(ellipseIn:CGRect(x:x-3,y:4,width:6,height:6)),with:.color(muted))
            }
        }
        // A schematic earbud makes the rigid sensor mounting visible.
        let sensorY: CGFloat = topDown ? -4 : -38
        c.fill(Path(roundedRect:CGRect(x:-15,y:sensorY,width:20,height:11),cornerRadius:5),with:.color(.white))
        c.fill(Path(roundedRect:CGRect(x:-12,y:sensorY+5,width:5,height:18),cornerRadius:2.5),with:.color(.white))
    }
}

struct GuideMountDiagram: View {
    let language: GuideLanguage
    let tilt: Double
    var body: some View {
        Canvas { context,size in
            GuideInk.grid(&context,size:size)
            let carWidth = min(112.0,size.width*0.28), y = size.height*0.59
            let left = CGPoint(x:size.width*0.25,y:y), right = CGPoint(x:size.width*0.75,y:y)
            GuideInk.text(&context,language.text("1. LEVEL", "1. РІВНО"),at:.init(x:left.x,y:27),color:GuideInk.muted)
            GuideInk.text(&context,language.text("2. NOSE UP", "2. НІС УГОРУ"),at:.init(x:right.x,y:27),color:GuideInk.muted)
            for center in [left,right] {
                GuideInk.line(&context,from:.init(x:center.x-carWidth*0.62,y:y+carWidth*0.18),
                              to:.init(x:center.x+carWidth*0.62,y:y+carWidth*0.18),color:.white.opacity(0.22),dashed:true)
                GuideInk.arrow(&context,from:.init(x:center.x,y:y+34),to:.init(x:center.x,y:y+67),color:.cyan.opacity(0.7))
                GuideInk.text(&context,"g",at:.init(x:center.x+12,y:y+56),color:.cyan)
            }
            GuideInk.car(context,at:left,angle:0,width:carWidth)
            GuideInk.car(context,at:right,angle:-tilt,width:carWidth)
            let angle = tilt * .pi/180
            let origin = CGPoint(x:right.x+18,y:right.y-26)
            let end = CGPoint(x:origin.x+carWidth*0.65*cos(angle),y:origin.y-carWidth*0.65*sin(angle))
            GuideInk.arrow(&context,from:origin,to:end,color:PodTheme.teal)
            GuideInk.text(&context,language.text("forward", "вперед"),at:.init(x:right.x+4,y:68),color:PodTheme.teal)
            GuideInk.text(&context,"\(Int(tilt))°",at:.init(x:right.x+carWidth*0.48,y:y+33),color:GuideInk.track,size:13)
            GuideInk.arrow(&context,from:.init(x:left.x-carWidth*0.63,y:y-5),
                           to:.init(x:left.x-carWidth*0.63,y:y-59),color:PodTheme.teal)
            GuideInk.text(&context,language.text("up", "вгору"),at:.init(x:left.x-carWidth*0.6,y:y-73),color:PodTheme.teal)
        }
        .background(GuideInk.background,in:RoundedRectangle(cornerRadius:14))
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(language.text("Mounting diagram. A level car and the same car with its nose raised \(Int(tilt)) degrees. Gravity points down in both poses.",
                                         "Схема кріплення. Рівна машинка й та сама машинка з носом, піднятим на \(Int(tilt)) градусів. В обох позах тяжіння спрямоване вниз."))
    }
}

struct GuideDirectionDiagram: View {
    let language: GuideLanguage
    let heading: Double
    let slope: Double
    var body: some View {
        Canvas { context,size in
            GuideInk.grid(&context,size:size)
            let left = CGPoint(x:size.width*0.25,y:size.height*0.55)
            let right = CGPoint(x:size.width*0.75,y:size.height*0.55)
            let radius = min(size.width*0.19,78.0), carWidth = radius*1.1
            GuideInk.line(&context,from:.init(x:size.width/2,y:22),to:.init(x:size.width/2,y:size.height-22),color:.white.opacity(0.08))
            GuideInk.text(&context,language.text("TOP VIEW", "ВИГЛЯД ЗГОРИ"),at:.init(x:left.x,y:26),color:GuideInk.muted)
            GuideInk.text(&context,language.text("SIDE VIEW", "ВИГЛЯД ЗБОКУ"),at:.init(x:right.x,y:26),color:GuideInk.muted)
            context.stroke(Path(ellipseIn:CGRect(x:left.x-radius,y:left.y-radius,width:radius*2,height:radius*2)),
                           with:.color(.white.opacity(0.1)),style:.init(lineWidth:1,dash:[3,5]))
            for center in [left,right] {
                GuideInk.line(&context,from:.init(x:center.x-radius,y:center.y),to:.init(x:center.x+radius,y:center.y),
                              color:.white.opacity(0.25),dashed:true)
            }
            GuideInk.car(context,at:left,angle:-heading,width:carWidth,topDown:true)
            GuideInk.car(context,at:right,angle:-slope,width:carWidth)
            for (center,angle) in [(left,heading),(right,slope)] {
                let radians = angle * .pi/180
                let from = CGPoint(x:center.x+carWidth*0.48*cos(radians),y:center.y-carWidth*0.48*sin(radians))
                let to = CGPoint(x:center.x+radius*1.05*cos(radians),y:center.y-radius*1.05*sin(radians))
                GuideInk.arrow(&context,from:from,to:to,color:PodTheme.teal)
            }
            GuideInk.text(&context,"\(language.text("Turn", "Поворот")) \(Int(heading))°",
                          at:.init(x:left.x,y:size.height-23),color:PodTheme.teal)
            GuideInk.text(&context,"\(language.text("Slope", "Нахил")) \(Int(slope))°",
                          at:.init(x:right.x,y:size.height-23),color:PodTheme.teal)
        }
        .background(GuideInk.background,in:RoundedRectangle(cornerRadius:14))
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(language.text("Car direction: horizontal turn \(Int(heading)) degrees; slope \(Int(slope)) degrees. The arrows follow the nose.",
                                         "Напрямок машинки: горизонтальний поворот \(Int(heading)) градусів, нахил \(Int(slope)) градусів. Стрілки спрямовані вздовж носа."))
    }
}

struct GuideSpeedDiagram: View {
    let language: GuideLanguage
    let result: AnalysisResult
    let time: Double
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            Text(language.text("FORWARD ACCELERATION · m/s²", "ПРИСКОРЕННЯ ВПЕРЕД · m/s²"))
                .font(.system(size:9,weight:.medium,design:.monospaced)).foregroundStyle(PodTheme.teal)
            Chart {
                RuleMark(y:.value("Zero",0)).foregroundStyle(.white.opacity(0.18))
                ForEach(result.signals) { signal in
                    LineMark(x:.value("Time",signal.time),y:.value("Acceleration",signal.tangentialUserAcceleration*result.inferredAccelerationSign))
                        .foregroundStyle(PodTheme.teal).lineStyle(.init(lineWidth:1.7))
                }
                RuleMark(x:.value("Cursor",time)).foregroundStyle(.white.opacity(0.6)).lineStyle(.init(dash:[3,4]))
            }
            .chartXScale(domain:0...result.metrics.recordingDuration)
            .chartXAxis(.hidden).chartYAxis { AxisMarks(position:.leading,values:.automatic(desiredCount:3)) }
            .frame(height:70)
            Text(language.text("ESTIMATED SPEED · m/s", "ОЦІНЕНА ШВИДКІСТЬ · m/s"))
                .font(.system(size:9,weight:.medium,design:.monospaced)).foregroundStyle(GuideInk.track)
            Chart {
                ForEach(result.points) { point in
                    AreaMark(x:.value("Time",point.time),y:.value("Speed",point.speed))
                        .foregroundStyle(LinearGradient(colors:[GuideInk.track.opacity(0.25),GuideInk.track.opacity(0.015)],startPoint:.top,endPoint:.bottom))
                    LineMark(x:.value("Time",point.time),y:.value("Speed",point.speed)).foregroundStyle(GuideInk.track)
                        .lineStyle(.init(lineWidth:2))
                }
                RuleMark(x:.value("Cursor",time)).foregroundStyle(.white.opacity(0.6)).lineStyle(.init(dash:[3,4]))
                if let point = result.points.min(by:{ abs($0.time-time)<abs($1.time-time) }) {
                    PointMark(x:.value("Time",point.time),y:.value("Speed",point.speed)).foregroundStyle(.white).symbolSize(26)
                }
            }
            .chartXScale(domain:0...result.metrics.recordingDuration)
            .chartXAxis { AxisMarks(values:.automatic(desiredCount:5)) }
            .chartYAxis { AxisMarks(position:.leading,values:.automatic(desiredCount:3)) }
            .frame(height:83)
            HStack {
                Text(language.text("Start at rest", "Спокій на старті"))
                Spacer()
                Text(language.text("Time · s", "Час · s"))
                Spacer()
                Text(language.text("End at rest", "Спокій на фініші"))
            }.font(.system(size:9)).foregroundStyle(GuideInk.muted)
        }
        .padding(17)
        .background(GuideInk.background,in:RoundedRectangle(cornerRadius:14))
        .environment(\.colorScheme,.dark)
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(language.text("Synthetic run. The top graph shows forward sensor acceleration with its sign aligned; the lower graph shows estimated speed. Speed starts and ends at zero. Cursor: \(formatted(time)) seconds.",
                                         "Синтетичний заїзд. Верхній графік — прискорення вздовж машинки з узгодженим знаком, нижній — оцінена швидкість. На початку й наприкінці швидкість нульова. Курсор: \(formatted(time)) секунди."))
    }
}

struct GuidePathDiagram: View {
    let language: GuideLanguage
    let result: AnalysisResult
    let time: Double
    let heightCentimetres: Double
    let showScale: Bool

    var body: some View {
        Canvas { context,size in
            GuideInk.grid(&context,size:size)
            let positions = result.points.map(\.position)
            let maxX = max(0.01,positions.map(\.x).max() ?? 1)
            let maxY = max(0.01,positions.map(\.y).max() ?? 1)
            let factor = heightCentimetres/58
            // The same camera is retained for every H, so uniform scaling is visible.
            let maxFactor = showScale ? 1.5 : 1.0
            let projectedX = positions.map { 0.84*$0.x-0.58*$0.y } + [0]
            let projectedY = positions.map { -$0.z-0.26*$0.x-0.38*$0.y } + [0]
            let minProjectedX = projectedX.min() ?? 0
            let maxProjectedX = max(0.01,projectedX.max() ?? 1)
            let minProjectedY = min(-0.01,projectedY.min() ?? -1)
            let extentX = (maxProjectedX-minProjectedX)*maxFactor
            let extentY = -minProjectedY*maxFactor
            let drawingWidth = Double(size.width)-100
            let drawingHeight = Double(size.height)-88
            let unit = min(drawingWidth/extentX,drawingHeight/extentY)
            let offsetX = 60+(drawingWidth-extentX*unit)/2
            let offsetY = 48+(drawingHeight-extentY*unit)/2
            let originX = offsetX-minProjectedX*maxFactor*unit
            let originY = offsetY-minProjectedY*maxFactor*unit
            let origin = CGPoint(x:originX,y:originY)
            func project(_ p: Vector3, scale: Double = 1) -> CGPoint {
                CGPoint(x:origin.x+(0.84*p.x-0.58*p.y)*unit*scale,
                        y:origin.y-(p.z+0.26*p.x+0.38*p.y)*unit*scale)
            }
            func trace(_ points: [Vector3], scale: Double) -> Path {
                var path = Path()
                for (i,p) in points.enumerated() {
                    let v = project(p,scale:scale)
                    if i == 0 { path.move(to:v) } else { path.addLine(to:v) }
                }
                return path
            }
            // Perspective ground grid with a common metric scale.
            for f in stride(from:0.0,through:1.001,by:0.25) {
                GuideInk.line(&context,from:project(.init(maxX*maxFactor*f,0,0)),
                              to:project(.init(maxX*maxFactor*f,maxY*maxFactor,0)),color:.white.opacity(0.08))
                GuideInk.line(&context,from:project(.init(0,maxY*maxFactor*f,0)),
                              to:project(.init(maxX*maxFactor,maxY*maxFactor*f,0)),color:.white.opacity(0.08))
            }
            let shadow = positions.map { Vector3($0.x,$0.y,0) }
            context.stroke(trace(shadow,scale:factor),with:.color(.white.opacity(0.13)),style:.init(lineWidth:1.2,dash:[3,5]))
            if showScale {
                context.stroke(trace(positions,scale:1),with:.color(.white.opacity(0.25)),style:.init(lineWidth:2,dash:[5,5]))
                GuideInk.text(&context,language.text("Dashed: 58 cm reference", "Пунктир: зразок 58 см"),
                              at:.init(x:17,y:22),color:GuideInk.muted,size:10,anchor:.leading)
            } else {
                GuideInk.text(&context,language.text("ESTIMATED 3D CENTERLINE", "ОЦІНЕНА 3D-ТРАЄКТОРІЯ"),
                              at:.init(x:17,y:22),color:GuideInk.muted,size:10,anchor:.leading)
            }
            let full = trace(positions,scale:factor)
            context.stroke(full,with:.color(GuideInk.track.opacity(showScale ? 0.16 : 0.20)),style:.init(lineWidth:9,lineCap:.round,lineJoin:.round))
            context.stroke(full,with:.color(GuideInk.track.opacity(showScale ? 1 : 0.25)),style:.init(lineWidth:2.5,lineCap:.round,lineJoin:.round))
            if !showScale {
                let travelled = result.points.filter { $0.time <= time }.map(\.position)
                context.stroke(trace(travelled,scale:factor),with:.color(GuideInk.track),style:.init(lineWidth:3,lineCap:.round,lineJoin:.round))
                if let current = result.points.min(by:{ abs($0.time-time)<abs($1.time-time) }) {
                    let p = project(current.position,scale:factor)
                    GuideInk.dot(&context,at:p,color:.white,radius:5)
                    if let signal = result.signals.min(by:{ abs($0.time-time)<abs($1.time-time) }), current.speed > 0.05 {
                        let next = project(current.position+signal.direction*0.35,scale:factor)
                        GuideInk.arrow(&context,from:p,to:next,color:PodTheme.teal)
                    }
                }
            }
            if let first = positions.first, let last = positions.last {
                GuideInk.dot(&context,at:project(first,scale:factor),color:PodTheme.teal,radius:3)
                GuideInk.dot(&context,at:project(last,scale:factor),color:GuideInk.track,radius:3)
                if !showScale {
                    let start = project(first), end = project(last)
                    GuideInk.text(&context,language.text("Start", "Старт"),at:.init(x:start.x,y:start.y-16),color:PodTheme.teal)
                    GuideInk.text(&context,language.text("Finish", "Фініш"),at:.init(x:end.x,y:end.y-16),color:GuideInk.track)
                }
            }
            if showScale, let highest = positions.max(by:{ $0.z < $1.z }) {
                // The dimension is vertical in world space, between horizontal Z planes.
                let topPoint = project(highest,scale:factor)
                let groundPoint = project(.init(highest.x,highest.y,0),scale:factor)
                let x = topPoint.x-18
                let top = topPoint.y
                let baseline = groundPoint.y
                GuideInk.line(&context,from:.init(x:x,y:top),to:.init(x:x,y:baseline),color:PodTheme.teal,width:1.5)
                for y in [top,baseline] {
                    GuideInk.line(&context,from:.init(x:x-4,y:y),to:.init(x:x+5,y:y),color:PodTheme.teal,width:1.5)
                    GuideInk.line(&context,from:.init(x:x+6,y:y),to:.init(x:topPoint.x,y:y),color:PodTheme.teal.opacity(0.4),dashed:true)
                }
                GuideInk.text(&context,"H = \(Int(heightCentimetres)) cm",
                              at:.init(x:max(17,x-12),y:top-17),color:PodTheme.teal,size:12,anchor:.leading)
                GuideInk.text(&context,"0",at:.init(x:x,y:baseline+13),color:GuideInk.muted,size:10)
            }
            let axisOrigin = CGPoint(x:size.width-65,y:size.height-33)
            GuideInk.arrow(&context,from:axisOrigin,to:.init(x:axisOrigin.x+24,y:axisOrigin.y-7),color:GuideInk.muted,width:1)
            GuideInk.arrow(&context,from:axisOrigin,to:.init(x:axisOrigin.x-16,y:axisOrigin.y-11),color:GuideInk.muted,width:1)
            GuideInk.arrow(&context,from:axisOrigin,to:.init(x:axisOrigin.x,y:axisOrigin.y-29),color:PodTheme.teal,width:1)
            GuideInk.text(&context,"X",at:.init(x:axisOrigin.x+31,y:axisOrigin.y-8),color:GuideInk.muted,size:9)
            GuideInk.text(&context,"Y",at:.init(x:axisOrigin.x-23,y:axisOrigin.y-16),color:GuideInk.muted,size:9)
            GuideInk.text(&context,"Z",at:.init(x:axisOrigin.x,y:axisOrigin.y-38),color:PodTheme.teal,size:9)
        }
        .background(GuideInk.background,in:RoundedRectangle(cornerRadius:14))
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(showScale
            ? language.text("Synthetic trajectory at H \(Int(heightCentimetres)) centimetres. The dashed reference is 58 centimetres. Shape is preserved while all dimensions scale together.",
                            "Синтетична траєкторія з H \(Int(heightCentimetres)) сантиметрів. Пунктирний зразок — 58 сантиметрів. Форма зберігається, усі розміри масштабуються разом.")
            : language.text("Synthetic 3D trajectory. Orange marks the path travelled by \(formatted(time)) seconds. A dot marks the car; an arrow shows its direction.",
                            "Синтетична 3D-траєкторія. Помаранчевим — шлях за \(formatted(time)) секунди. Точка позначає машинку, стрілка — її напрямок."))
    }
}

struct GuideAmbiguityDiagram: View {
    var body: some View {
        Canvas { context,size in
            for y in [CGFloat(8),size.height-8] {
                GuideInk.line(&context,from:.init(x:2,y:y),to:.init(x:size.width-15,y:y),color:PodTheme.amber.opacity(0.35),dashed:true)
            }
            var a = Path()
            a.move(to:.init(x:3,y:8))
            a.addCurve(to:.init(x:96,y:size.height-8),control1:.init(x:20,y:8),control2:.init(x:34,y:size.height-8))
            context.stroke(a,with:.color(PodTheme.amber),style:.init(lineWidth:2,lineCap:.round))
            var b = Path()
            b.move(to:.init(x:3,y:8))
            b.addCurve(to:.init(x:96,y:size.height-8),control1:.init(x:77,y:8),control2:.init(x:86,y:size.height-8))
            context.stroke(b,with:.color(PodTheme.teal),style:.init(lineWidth:2,lineCap:.round))
            GuideInk.line(&context,from:.init(x:100,y:8),to:.init(x:100,y:size.height-8),color:PodTheme.amber)
            GuideInk.text(&context,"H",at:.init(x:108,y:size.height/2),color:PodTheme.amber,size:9)
        }
    }
}
