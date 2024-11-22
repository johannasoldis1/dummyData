import SwiftUI

@main
struct EMG_ble_kthApp: App {
    var body: some Scene {
        WindowGroup {
            let data: Array<CGFloat> = [0.0]
            let graph = emgGraph(firstValues: data) // Create the emgGraph instance
            let BLE = BLEManager(emg: graph) // Pass the emgGraph instance to BLEManager
            ContentView(graph: graph, BLE: BLE) // Provide both instances to ContentView
        }
    }
}
