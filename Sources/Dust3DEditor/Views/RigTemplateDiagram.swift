import Dust3DEditorModel
import Dust3DKit
import SwiftUI
import simd

struct RigTemplateOrbit: Equatable {
    static let initial = Self().rotated(yaw: -0.35, pitch: 0.15)

    private(set) var yaw = 0.0
    private(set) var pitch = 0.0

    func rotated(yaw deltaYaw: Double, pitch deltaPitch: Double) -> Self {
        guard deltaYaw.isFinite, deltaPitch.isFinite else { return self }
        let revolution = 2 * Double.pi
        var next = self
        next.yaw = (yaw + deltaYaw.truncatingRemainder(dividingBy: revolution))
            .truncatingRemainder(dividingBy: revolution)
        next.pitch = min(.pi / 2, max(-Double.pi / 2, pitch + deltaPitch))
        return next
    }
}

enum RigTemplateDiagramLayout {
    struct Line: Equatable {
        let name: String
        let start: CanvasPoint
        let end: CanvasPoint

        func isSelected(_ selectedName: String?) -> Bool {
            selectedName.map { name.utf8.elementsEqual($0.utf8) } ?? false
        }
    }

    static func lines(
        in hierarchy: RigTemplateHierarchy, plane: EditingPlane, width: Double, height: Double
    ) -> [Line] {
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return [] }
        func project(_ point: SIMD3<Double>) -> CanvasPoint {
            .init(x: plane == .front ? point.x : point.z, y: -point.y)
        }
        let source = hierarchy.bones.compactMap { bone -> Line? in
            guard let segment = bone.segment else { return nil }
            return Line(name: bone.name, start: project(segment.start), end: project(segment.end))
        }
        let points = source.flatMap { [$0.start, $0.end] }
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return [] }
        let spanX = maxX - minX
        let spanY = maxY - minY
        let scale = min(spanX > 0 ? width * 0.8 / spanX : .infinity, spanY > 0 ? height * 0.8 / spanY : .infinity)
        let fitScale = scale.isFinite ? scale : 1
        func fit(_ point: CanvasPoint) -> CanvasPoint {
            .init(
                x: width / 2 + (point.x - minX - spanX / 2) * fitScale,
                y: height / 2 + (point.y - minY - spanY / 2) * fitScale)
        }
        return source.map { Line(name: $0.name, start: fit($0.start), end: fit($0.end)) }
    }

    static func lines(
        in hierarchy: RigTemplateHierarchy, orbit: RigTemplateOrbit, width: Double, height: Double
    ) -> [Line] {
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return [] }
        let source: [(name: String, segment: RigTemplateSegment)] = hierarchy.bones.compactMap { bone in
            bone.segment.map { (bone.name, $0) }
        }
        let endpoints = source.flatMap { [$0.segment.start, $0.segment.end] }
        guard let first = endpoints.first else { return [] }
        let minimum = endpoints.reduce(first, simd_min)
        let maximum = endpoints.reduce(first, simd_max)
        let span = maximum - minimum
        // Fit a rotation-invariant envelope so dragging does not change magnification.
        let diameter = hypot(hypot(span.x, span.y), span.z)
        guard diameter > 0 else { return [] }
        let normalizedCenter = (span / diameter) * 0.5
        let screenDiameter = min(width, height) * 0.8
        let yawCosine = cos(orbit.yaw)
        let yawSine = sin(orbit.yaw)
        let pitchCosine = cos(orbit.pitch)
        let pitchSine = sin(orbit.pitch)
        func project(_ point: SIMD3<Double>) -> (point: CanvasPoint, depth: Double) {
            let normalized = (point - minimum) / diameter - normalizedCenter
            let x = yawCosine * normalized.x + yawSine * normalized.z
            let yawDepth = -yawSine * normalized.x + yawCosine * normalized.z
            let y = pitchCosine * normalized.y - pitchSine * yawDepth
            let depth = pitchSine * normalized.y + pitchCosine * yawDepth
            return (.init(x: width / 2 + x * screenDiameter, y: height / 2 - y * screenDiameter), depth)
        }
        let projected: [(line: Line, depth: Double, index: Int)] = source.enumerated().map { index, item in
            let start = project(item.segment.start)
            let end = project(item.segment.end)
            let line = Line(name: item.name, start: start.point, end: end.point)
            return (line, start.depth + end.depth, index)
        }
        return
            projected
            .sorted { $0.depth == $1.depth ? $0.index < $1.index : $0.depth < $1.depth }
            .map(\.line)
    }
}

struct RigTemplateDiagram: View {
    private enum Viewpoint: Hashable {
        case front
        case side
        case orbit

        var name: String {
            switch self {
            case .front: EditingPlane.front.rawValue
            case .side: EditingPlane.side.rawValue
            case .orbit: String(localized: "Orbit")
            }
        }
    }

    let hierarchy: RigTemplateHierarchy
    let selectedName: String?
    @State private var viewpoint: Viewpoint = .front
    @State private var orbit = RigTemplateOrbit.initial
    @GestureState private var orbitDrag = CGSize.zero

    var body: some View {
        if hierarchy.bones.contains(where: { $0.segment != nil }) {
            Picker("Template Diagram View", selection: $viewpoint) {
                Text("Front").tag(Viewpoint.front)
                Text("Side").tag(Viewpoint.side)
                Text("Orbit").tag(Viewpoint.orbit)
            }
            .pickerStyle(.segmented)
            if viewpoint == .orbit {
                Menu("Rotate Template") {
                    Button("Rotate Left") { orbit = orbit.rotated(yaw: -.pi / 12, pitch: 0) }
                    Button("Rotate Right") { orbit = orbit.rotated(yaw: .pi / 12, pitch: 0) }
                    Button("Rotate Up") { orbit = orbit.rotated(yaw: 0, pitch: -.pi / 12) }
                    Button("Rotate Down") { orbit = orbit.rotated(yaw: 0, pitch: .pi / 12) }
                    Divider()
                    Button("Reset Orbit") { orbit = .initial }
                }
                .controlSize(.small)
            }
            Canvas { context, size in
                let lines = lines(in: size)
                for line in lines where !line.isSelected(selectedName) {
                    draw(line, context: context, color: .secondary, lineWidth: 1.5)
                }
                if let line = lines.first(where: { $0.isSelected(selectedName) }) {
                    draw(line, context: context, color: .accentColor, lineWidth: 3.5)
                }
            }
            .frame(height: 140)
            .contentShape(Rectangle())
            .gesture(orbitGesture, including: viewpoint == .orbit ? .all : .none)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rig template diagram")
            .accessibilityValue(accessibilityValue)
        } else {
            Text("Template diagram unavailable.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var accessibilityValue: Text {
        guard let selectedName else { return Text("\(viewpoint.name), no bone selected") }
        if hierarchy.bones.contains(where: { $0.segment != nil && $0.name.utf8.elementsEqual(selectedName.utf8) }) {
            return Text("\(viewpoint.name), \(selectedName) highlighted")
        }
        return Text("\(viewpoint.name), \(selectedName) has no diagram segment")
    }

    private var orbitGesture: some Gesture {
        DragGesture()
            .updating($orbitDrag) { gesture, drag, _ in drag = gesture.translation }
            .onEnded { gesture in
                guard viewpoint == .orbit else { return }
                orbit = orbit.rotated(yaw: gesture.translation.width * 0.01, pitch: gesture.translation.height * 0.01)
            }
    }

    private func lines(in size: CGSize) -> [RigTemplateDiagramLayout.Line] {
        if viewpoint == .orbit {
            return RigTemplateDiagramLayout.lines(
                in: hierarchy, orbit: orbit.rotated(yaw: orbitDrag.width * 0.01, pitch: orbitDrag.height * 0.01),
                width: size.width, height: size.height)
        }
        return RigTemplateDiagramLayout.lines(
            in: hierarchy, plane: viewpoint == .front ? .front : .side, width: size.width, height: size.height)
    }

    private func draw(_ line: RigTemplateDiagramLayout.Line, context: GraphicsContext, color: Color, lineWidth: Double)
    {
        let start = CGPoint(x: line.start.x, y: line.start.y)
        if line.start == line.end {
            let bounds = CGRect(
                x: start.x - lineWidth, y: start.y - lineWidth, width: lineWidth * 2, height: lineWidth * 2)
            context.fill(Path(ellipseIn: bounds), with: .color(color))
        } else {
            let path = Path { path in
                path.move(to: start)
                path.addLine(to: CGPoint(x: line.end.x, y: line.end.y))
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
    }
}
