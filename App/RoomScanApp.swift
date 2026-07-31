import RoomModel
import RoomViewer
import SwiftUI

@main
struct RoomScanApp: App {
    var body: some SwiftUI.Scene {
        WindowGroup {
            RoomMaquetteView(room: .demoLivingRoom)
                .ignoresSafeArea()
        }
    }
}
