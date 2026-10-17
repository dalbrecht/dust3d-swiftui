import Dust3DDocument
import Foundation

/// Independent MIT synthetic one-sphere wrapping source, including opaque save data.
enum WrappingFixture {
    static let groupID = StitchingFixture.identity(300)
    static func document(mode: String = "", attributes: String = "wrapFaces='64'") throws -> Dust3DDocument {
        let partID = StitchingFixture.identity(100)
        let model = Data(
            "<canvas originX='.5' originY='.5' originZ='.5'><nodes><node id='\(StitchingFixture.identity(1000))' partId='\(partID)' x='.5' y='.5' z='.5' radius='.2'/></nodes><edges/><parts><part id='\(partID)'/></parts><components><component id='\(groupID)' wrap='\(mode)' future='keep' \(attributes)><!--keep--><component id='\(StitchingFixture.identity(200))' linkDataType='partId' linkData='\(partID)'/></component></components></canvas>"
                .utf8)
        let header =
            "<ds3><model name='model.xml' offset='0' size='\(model.count)'/><asset name='opaque.bin' offset='\(model.count)' size='4'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model + Data([0, 255, 10, 128]))
    }
}
