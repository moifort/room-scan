import SwiftUI
import RoomModel

@main
struct RoomScanApp: App {
    var body: some SwiftUI.Scene {
        WindowGroup {
            Text("RoomScan — \(FurnitureCategory.sofa.displayName)")
        }
    }
}
