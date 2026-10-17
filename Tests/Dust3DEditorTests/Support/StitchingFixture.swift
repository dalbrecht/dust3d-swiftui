import Dust3DDocument
import Foundation

/// Independently serialized engine fixtures, not built by the commands under test.
enum StitchingFixture {
    static let groupID = identity(300)
    static func identity(_ value: Int) -> String { String(format: "{%08d-0000-4000-8000-%012d}", value, value) }

    static func document(
        loop: Bool, attributes: String = "sideClosed='true'", unsupported: Bool = false,
        degenerateStraight: Bool = false, fillLoopInterior: String = "true", isolatedLoop: Bool = false,
        includeUncombinedModel: Bool = true
    ) throws
        -> Dust3DDocument
    {
        var nodes = ""
        var edges = ""
        var parts = ""
        var children = ""
        let partCount = loop ? (isolatedLoop ? 1 : 2) : 3
        for partIndex in 0..<partCount {
            let part = identity(100 + partIndex)
            let component = identity(200 + partIndex)
            let count = loop ? 4 : 3
            for index in 0..<count {
                let angle = 2 * Double.pi * Double(loop ? index : partIndex) / Double(loop ? count : partCount)
                let radial = loop ? (partIndex == 0 ? 0.4 : 0.16) : 0.3
                let profileAngle = Double.pi * Double(index) / Double(count - 1)
                let profileRadius = 0.25 + Double(partIndex) * 0.05
                let x =
                    0.5 + cos(loop || degenerateStraight ? angle : profileAngle)
                    * (loop || degenerateStraight ? radial : profileRadius)
                let y =
                    0.5 + sin(loop || degenerateStraight ? angle : profileAngle)
                    * (loop || degenerateStraight ? radial : profileRadius)
                let z = loop ? (partIndex == 0 ? 0.5 : 0.6) : Double(degenerateStraight ? index : partIndex) * 0.5
                nodes +=
                    "<node id='\(identity(1000 + partIndex * 10 + index))' partId='\(part)' x='\(x)' y='\(y)' z='\(z)' radius='.05'/>"
                if index > 0 {
                    edges +=
                        "<edge id='\(identity(2000 + partIndex * 10 + index))' partId='\(part)' from='\(identity(1000 + partIndex * 10 + index - 1))' to='\(identity(1000 + partIndex * 10 + index))'/>"
                }
            }
            if loop {
                edges +=
                    "<edge id='\(identity(2000 + partIndex * 10))' partId='\(part)' from='\(identity(1000 + partIndex * 10 + count - 1))' to='\(identity(1000 + partIndex * 10))'/>"
            }
            parts +=
                "<part id='\(part)' target='\(loop ? "StitchingLoop" : "StitchingLine")' fillLoopInterior='\(fillLoopInterior)' future='keep'/>"
            children += "<component id='\(component)' linkDataType='partId' linkData='\(part)'/>"
        }
        if isolatedLoop && includeUncombinedModel {
            // A separate uncombined model keeps the scene nonempty when the isolated loop is unfilled.
            nodes += "<node id='\(identity(1999))' partId='\(identity(199))' x='2' y='2' z='2' radius='.05'/>"
            parts += "<part id='\(identity(199))' target='Model'/>"
            children +=
                "<component id='\(identity(299))' linkDataType='partId' linkData='\(identity(199))' combineMode='Uncombined'/>"
        }
        let settings =
            unsupported
            ? "frontClosed='future' backClosed='future' sideClosed='future' targetSegments='future' backCloseDepthRatio='future' backCloseSharpness='future'"
            : attributes
        let model = Data(
            "<canvas originX='.5' originY='.5' originZ='.5'><nodes>\(nodes)</nodes><edges>\(edges)</edges><parts>\(parts)</parts><components><component id='\(groupID)' name='Stitching QA' color='#3366cc' future='preserved' \(settings)>\(children)</component></components></canvas>"
                .utf8)
        let header =
            "<ds3><model name='model.xml' offset='0' size='\(model.count)'/><asset name='opaque.bin' offset='\(model.count)' size='4'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model + Data([0, 255, 10, 128]))
    }
}
