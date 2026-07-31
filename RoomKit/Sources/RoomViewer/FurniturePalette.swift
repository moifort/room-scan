#if os(iOS)
import UIKit
import RoomModel

/// Couleur d'un meuble dans la maquette. Des teintes franches et distinctes
/// priment sur le réalisme : le but est de lire la catégorie d'un coup d'œil.
public enum FurniturePalette {
    public static func color(for category: FurnitureCategory) -> UIColor {
        switch category {
        case .sofa: UIColor(red: 0.29, green: 0.56, blue: 0.85, alpha: 1)
        case .chair: UIColor(red: 0.36, green: 0.72, blue: 0.72, alpha: 1)
        case .table: UIColor(red: 0.85, green: 0.62, blue: 0.30, alpha: 1)
        case .bed: UIColor(red: 0.60, green: 0.45, blue: 0.85, alpha: 1)
        case .storage: UIColor(red: 0.52, green: 0.58, blue: 0.66, alpha: 1)
        case .television: UIColor(red: 0.25, green: 0.28, blue: 0.33, alpha: 1)
        case .fireplace: UIColor(red: 0.80, green: 0.40, blue: 0.32, alpha: 1)
        case .stairs: UIColor(red: 0.45, green: 0.50, blue: 0.42, alpha: 1)
        case .refrigerator, .stove, .oven, .dishwasher, .washerDryer:
            UIColor(red: 0.62, green: 0.68, blue: 0.74, alpha: 1)
        case .sink, .toilet, .bathtub:
            UIColor(red: 0.45, green: 0.75, blue: 0.83, alpha: 1)
        case .unknown: UIColor(red: 0.70, green: 0.70, blue: 0.72, alpha: 1)
        }
    }
}
#endif
