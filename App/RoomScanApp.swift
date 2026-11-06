import RoomDressing
import RoomViewer
import SwiftUI

@main
struct RoomScanApp: App {
    /// `-demoRealistic` opens the realistic viewer on a colour-faced cube, to
    /// check per-vertex colours without scanning anything.
    private let showsRealisticDemo = ProcessInfo.processInfo.arguments.contains("-demoRealistic")

    var body: some SwiftUI.Scene {
        WindowGroup {
            if showsRealisticDemo {
                RealisticRoomView(mesh: .demoCube(size: 1))
                    .ignoresSafeArea()
            } else {
                LibraryView()
            }
        }
    }
}
