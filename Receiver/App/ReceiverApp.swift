import SwiftUI

@main
struct ReceiverApp: App {
    @StateObject private var receiver = ReceiverModel()
    var body: some Scene {
        WindowGroup { ReceiverView().environmentObject(receiver) }
    }
}
