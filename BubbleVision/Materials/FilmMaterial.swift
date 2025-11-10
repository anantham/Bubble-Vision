import Foundation
import RealityKit
import Metal
import simd

/// Wraps the RealityKit CustomMaterial used by the film plane so we have a single place to configure shader inputs.
/// Matches the design doc's intent while operating within RealityKit's custom parameter limits.
final class FilmMaterial {

    struct FXState {
        var mask: UInt32 = 0
        var intensity: Float = 0
        var param2: Float = 0
        var param3: Float = 0
    }

    private let template: CustomMaterial
    private var fxState = FXState()
    private var wobbleTexture: TextureResource?

    init(device: MTLDevice, library: MTLLibrary) throws {
        let surfaceShader = CustomMaterial.SurfaceShader(
            named: "filmPlane_fragment",
            in: library
        )

        let geometryModifier = CustomMaterial.GeometryModifier(
            named: "wobbleDisplacement_geometry",
            in: library
        )

        var material = try CustomMaterial(
            surfaceShader: surfaceShader,
            geometryModifier: geometryModifier,
            lightingModel: .lit
        )
        material.custom.value = SIMD4<Float>(0, 0, 0, 0)
        self.template = material
    }

    /// Returns a copy of the template material configured for the specified camera position and seam state.
    func material(cameraPosition: SIMD3<Float>, seamEnabled: Bool) -> CustomMaterial {
        var material = template

        if let wobbleTexture {
            material.custom.texture = CustomMaterial.Texture(wobbleTexture)
        } else {
            material.custom.texture = nil
        }

        let seamBit: UInt32 = seamEnabled ? (1 << 7) : 0
        let packedMask = seamBit | fxState.mask
        material.custom.value = SIMD4<Float>(Float(packedMask),
                                             fxState.intensity,
                                             fxState.param2,
                                             fxState.param3)

        return material
    }

    func setFXState(_ state: FXState) {
        fxState = state
    }

    func setWobbleTexture(_ texture: TextureResource?) {
        wobbleTexture = texture
    }

    /// Unconfigured base material (used for shared references).
    var baseMaterial: CustomMaterial {
        template
    }
}
