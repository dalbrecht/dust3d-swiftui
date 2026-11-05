import Dust3DDocument
import Foundation

/// Independent MIT data-only three-chain fixture family for source/hash review before native execution.
enum MultiBindingFixtureFamily {
    static func id(_ value: Int) -> String {
        String(format: "{%08d-0000-4000-8000-%012d}", value, value)
    }
    static let bodyID = id(1031)
    static let garmentID = id(1032)
    static let secondGarmentID = id(1033)
    static let secondGuidePartID = id(3)
    static let emptyID = id(1034)
    static let bodyPartID = id(1)
    static let guidePartID = id(2)

    static func inputs() throws -> [String: Data] {
        let model = Data(
            """
            <canvas originX='.5' originY='.5' originZ='.5'><nodes>
            <node id='\(id(10))' partId='\(id(1))' x='.5' y='.3' z='.5' radius='.12'/><node id='\(id(11))' partId='\(id(1))' x='.5' y='.7' z='.5' radius='.12'/>
            <node id='\(id(20))' partId='\(id(2))' x='.5' y='.3' z='.5' radius='.17'/><node id='\(id(21))' partId='\(id(2))' x='.5' y='.7' z='.5' radius='.17'/>
            <node id='\(id(30))' partId='\(id(3))' x='.52' y='.3' z='.5' radius='.17'/><node id='\(id(31))' partId='\(id(3))' x='.52' y='.7' z='.5' radius='.17'/></nodes><edges>
            <edge id='\(id(100))' partId='\(id(1))' from='\(id(10))' to='\(id(11))'/><edge id='\(id(200))' partId='\(id(2))' from='\(id(20))' to='\(id(21))'/><edge id='\(id(300))' partId='\(id(3))' from='\(id(30))' to='\(id(31))'/></edges>
            <parts><part id='\(id(1))'/><part id='\(id(2))'/><part id='\(id(3))'/></parts><components>
            <component id='\(bodyID)' name='Body' combineMode='Uncombined'><component id='\(id(1021))' linkDataType='partId' linkData='\(id(1))'/></component>
            <component id='\(garmentID)' name='Garment' combineMode='Uncombined' wrap='Cloth' wrapFaces='64' wrapKeep='true' wrapWrinkles='1' wrapWrinkleSize='1' wrapDrape='.5' future='keep'><component id='\(id(1022))' linkDataType='partId' linkData='\(id(2))'/></component>
            <component id='\(secondGarmentID)' name='Garment' combineMode='Uncombined' wrap='Cloth' wrapFaces='64' wrapKeep='true' wrapWrinkles='1' wrapWrinkleSize='1' wrapDrape='.5' future='keep'><component id='\(id(1023))' linkDataType='partId' linkData='\(id(3))'/></component>
            <component id='\(emptyID)' name='Empty Body'/></components></canvas>
            """.utf8)
        let header =
            "<ds3><model name='model.xml' offset='0' size='\(model.count)'/><asset name='opaque.bin' offset='\(model.count)' size='4'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        let source = try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model + Data([0, 255, 10, 128]))
        let bound = try source.applying(
            .editComponentWrapping(ids: [garmentID, secondGarmentID], edit: .binding(.group(bodyID))))
        let returned = try bound.applying(
            .editComponentWrapping(ids: [garmentID, secondGarmentID], edit: .binding(.ownChildren)))
        let empty = try bound.applying(
            .editComponentWrapping(ids: [garmentID, secondGarmentID], edit: .binding(.group(emptyID))))
        return [
            "own": source.encoded(), "body": bound.encoded(), "own-after": returned.encoded(), "empty": empty.encoded(),
        ]
    }
}
