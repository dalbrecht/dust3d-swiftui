import XCTest

@testable import Dust3DDocument

final class AnimationControlDefinitionTests: XCTestCase {
    private func definition(
        name: String = "speed", label: String = "Speed", lower: Int = 0, upper: Int = 200,
        defaultSlider: Int = 100, nominal: Double = 1.005, divisor: Double = 100, multiplier: Double = 1
    ) throws -> AnimationControlDefinition {
        try AnimationControlDefinition(
            name: name, label: label, minimumSlider: lower, maximumSlider: upper,
            defaultSlider: defaultSlider, defaultParameter: nominal, divisor: divisor, multiplier: multiplier)
    }

    func testProjectionKeepsNominalDefaultDistinctFromDiscreteWidgetValue() throws {
        let control = try definition()
        XCTAssertEqual(control.defaultParameter, 1.005)
        XCTAssertEqual(control.defaultSlider, 100)
        XCTAssertEqual(try control.value(at: 100), 1)
        XCTAssertEqual(try control.slider(for: 1.005), 100)
        XCTAssertEqual(try control.slider(for: 1.019), 101)
        XCTAssertEqual(try control.slider(for: -0.001), 0)
        XCTAssertEqual(try control.value(at: 200), 2)
        let scaled = try definition(lower: -100, upper: 100, defaultSlider: 50, nominal: 10, divisor: 10, multiplier: 2)
        XCTAssertEqual(try scaled.value(at: -100), -20)
        XCTAssertEqual(try scaled.slider(for: -3.99), -19)
    }

    func testExplicitProjectionRejectsNonFiniteUnrepresentableAndOutOfRangeValues() throws {
        let control = try definition()
        for value in [Double.nan, .infinity, -.infinity] {
            XCTAssertThrowsError(try control.slider(for: value)) {
                XCTAssertEqual($0 as? AnimationCatalogError, .invalidValue)
            }
        }
        for value in [Double.greatestFiniteMagnitude, Double(Int32.max) + 1, Double(Int32.min) - 1] {
            XCTAssertThrowsError(try control.slider(for: value)) {
                XCTAssertEqual($0 as? AnimationCatalogError, .unrepresentableValue)
            }
        }
        for value in [-0.019, 3.0] {
            XCTAssertThrowsError(try control.slider(for: value)) {
                XCTAssertEqual($0 as? AnimationCatalogError, .invalidValue)
            }
        }
        for index in [-1, 201, Int.max] {
            XCTAssertThrowsError(try control.value(at: index)) {
                XCTAssertEqual($0 as? AnimationCatalogError, .invalidValue)
            }
        }
    }

    func testDefinitionRejectsInvalidMetadataBeforeItCanReachAControl() throws {
        let invalid: [() throws -> AnimationControlDefinition] = [
            { try self.definition(name: "") }, { try self.definition(name: "bad:name") },
            { try self.definition(name: "type") }, { try self.definition(label: "\n") },
            { try self.definition(name: String(repeating: "x", count: 129)) },
            { try self.definition(label: String(repeating: "x", count: 1025)) },
            { try self.definition(lower: 201) }, { try self.definition(upper: Int.max) },
            { try self.definition(defaultSlider: 201) }, { try self.definition(nominal: .nan) },
            { try self.definition(divisor: 0) }, { try self.definition(divisor: .infinity) },
            { try self.definition(multiplier: -1) }, { try self.definition(multiplier: .nan) },
            { try self.definition(divisor: .leastNonzeroMagnitude) },
            { try self.definition(nominal: .greatestFiniteMagnitude) },
            { try self.definition(defaultSlider: 99) },
            { try self.definition(defaultSlider: 200, nominal: 3) },
        ]
        for build in invalid {
            XCTAssertThrowsError(try build()) { XCTAssertEqual($0 as? AnimationCatalogError, .invalidDefinition) }
        }
        XCTAssertFalse(AnimationCatalogError.invalidDefinition.localizedDescription.isEmpty)
        XCTAssertFalse(AnimationCatalogError.invalidValue.localizedDescription.isEmpty)
        XCTAssertFalse(AnimationCatalogError.unrepresentableValue.localizedDescription.isEmpty)
    }
}
