import Foundation
import simd

/// Lecture d'une matrice de transformation : d'où vient l'objet et comment il
/// est tourné au sol. Isolé ici parce que c'est la conversion la plus facile à
/// écrire de travers, et la seule de la traduction d'un scan qui mérite des
/// tests — le reste n'est qu'un aiguillage de champs contrôlé par le compilateur.
public enum TransformReading {
    public static func position(of transform: simd_float4x4) -> SIMD3<Float> {
        SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
    }

    /// Angle de rotation autour de l'axe vertical. Lu sur la première colonne,
    /// normalisée : une mise à l'échelle ne doit pas fausser l'angle.
    public static func yaw(of transform: simd_float4x4) -> Float {
        let axis = SIMD2(transform.columns.0.x, transform.columns.0.z)
        guard simd_length(axis) > 0.0001 else { return 0 }
        return atan2(-axis.y, axis.x)
    }
}
