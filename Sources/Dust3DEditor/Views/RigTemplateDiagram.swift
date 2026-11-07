import Dust3DEditorModel
import Dust3DKit
import SwiftUI

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
}

struct RigTemplateDiagram: View {
    let hierarchy: RigTemplateHierarchy
    let selectedName: String?
    @State private var plane: EditingPlane = .front

    var body: some View {
        if hierarchy.bones.contains(where: { $0.segment != nil }) {
            Picker("Template Diagram View", selection: $plane) {
                Text("Front").tag(EditingPlane.front)
                Text("Side").tag(EditingPlane.side)
            }
            .pickerStyle(.segmented)
            Canvas { context, size in
                let lines = RigTemplateDiagramLayout.lines(
                    in: hierarchy, plane: plane, width: size.width, height: size.height)
                for line in lines where !line.isSelected(selectedName) {
                    draw(line, context: context, color: .secondary, lineWidth: 1.5)
                }
                if let line = lines.first(where: { $0.isSelected(selectedName) }) {
                    draw(line, context: context, color: .accentColor, lineWidth: 3.5)
                }
            }
            .frame(height: 140)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rig template diagram")
            .accessibilityValue(accessibilityValue)
        } else {
            Text("Template diagram unavailable.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var accessibilityValue: Text {
        guard let selectedName else { return Text("\(plane.rawValue), no bone selected") }
        if hierarchy.bones.contains(where: { $0.segment != nil && $0.name.utf8.elementsEqual(selectedName.utf8) }) {
            return Text("\(plane.rawValue), \(selectedName) highlighted")
        }
        return Text("\(plane.rawValue), \(selectedName) has no diagram segment")
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
