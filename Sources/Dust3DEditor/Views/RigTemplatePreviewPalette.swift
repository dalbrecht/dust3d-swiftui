#if MOTE3D_EXPERIMENTAL_RIG_TEMPLATE || MOTE3D_EXPERIMENTAL_GENERATED_RIG
    import AppKit
    import SwiftUI

    /// Resolve platform colors in the view's actual light/dark and contrast environment.
    @MainActor enum RigTemplatePreviewPalette {
        static func appearanceName(colorScheme: ColorScheme, contrast: ColorSchemeContrast) -> NSAppearance.Name {
            if contrast == .increased {
                return colorScheme == .dark ? .accessibilityHighContrastDarkAqua : .accessibilityHighContrastAqua
            }
            return colorScheme == .dark ? .darkAqua : .aqua
        }

        static func resolve(colorScheme: ColorScheme, contrast: ColorSchemeContrast) -> RigTemplatePreviewAppearance {
            func palette() -> RigTemplatePreviewAppearance {
                func rgba(_ color: NSColor) -> SIMD4<Float> {
                    let rgb = color.usingColorSpace(.deviceRGB) ?? .gray
                    return SIMD4(
                        Float(rgb.redComponent), Float(rgb.greenComponent), Float(rgb.blueComponent),
                        Float(rgb.alphaComponent))
                }
                return RigTemplatePreviewAppearance(
                    boneColor: rgba(.systemGreen), selectedBoneColor: rgba(.controlAccentColor),
                    ringColor: rgba(.systemGreen))
            }
            var result: RigTemplatePreviewAppearance?
            if let native = NSAppearance(named: appearanceName(colorScheme: colorScheme, contrast: contrast)) {
                native.performAsCurrentDrawingAppearance { result = palette() }
            }
            return result ?? palette()
        }
    }
#endif
