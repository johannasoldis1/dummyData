import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var graph: emgGraph
    @ObservedObject var BLE: BLEManager
    @State private var showingExporter = false
    @State var file_content: TextFile = TextFile(initialText: "")
    @State private var isFakeDataEnabled = false // State for toggle control

    var body: some View {
        VStack {
            // Graph visualization
            Path { path in
                let height = UIScreen.main.bounds.height / 3
                let width = UIScreen.main.bounds.width
                let firstSample = { () -> Int in
                    if graph.values.count > 1000 {
                        return graph.values.count - 1000
                    } else {
                        return 0
                    }
                }
                let cutGraph = graph.values[firstSample()..<graph.values.count]
                path.move(to: CGPoint(x: 0.0, y: 0.0))

                cutGraph.enumerated().forEach { index, item in
                    path.addLine(to: CGPoint(x: width * CGFloat(index) / (CGFloat(cutGraph.count) - 1.0), y: height * item))
                }
            }
            .stroke(Color.red, lineWidth: 1.5)

            // Bluetooth device list
            Text("Connect to sensor")
                .font(.title)
                .frame(maxWidth: .infinity, alignment: .center)
            List(BLE.BLEPeripherals) { peripheral in
                HStack {
                    Text(peripheral.name).onTapGesture {
                        print(peripheral)
                        BLE.connectSensor(p: peripheral)
                    }
                    Spacer()
                    Text(String(peripheral.rssi))
                }
            }
            .frame(height: 300)

            Spacer()

            // Status display
            Text("STATUS")
                .font(.headline)
            if BLE.BLEisOn {
                Text("Bluetooth is switched on")
                    .foregroundColor(.green)
            } else {
                Text("Bluetooth is NOT switched on")
                    .foregroundColor(.red)
            }

            Spacer()

            // Buttons for Bluetooth scanning and recording
            HStack {
                VStack(spacing: 10) {
                    Button(action: {
                        BLE.startScanning()
                    }) {
                        Text("Start Scanning")
                    }
                    Button(action: {
                        BLE.stopScanning()
                    }) {
                        Text("Stop Scanning")
                    }
                }
                .padding()

                Spacer()

                VStack(spacing: 10) {
                    Button(action: {
                        graph.record()
                    }) {
                        Text("Start Recording")
                    }
                    Button(action: {
                        file_content.text = graph.stop_recording_and_save()
                    }) {
                        Text("Stop Recording")
                    }
                    Button(action: {
                        showingExporter = true
                    }) {
                        Text("Export last")
                    }
                }
                .padding()
            }

            Spacer()

            // Toggle for Dummy Data Control
            VStack {
                Toggle("Enable Fake Data", isOn: $isFakeDataEnabled)
                    .onChange(of: isFakeDataEnabled) { value in
                        if value {
                            BLE.startDummyData()
                        } else {
                            BLE.stopDummyData()
                        }
                    }
                    .padding()
            }
        }
        .fileExporter(isPresented: $showingExporter, document: file_content, contentType: .commaSeparatedText, defaultFilename: "emg-data") { result in
            switch result {
            case .success(let url):
                print("Saved to \(url)")
            case .failure(let error):
                print(error.localizedDescription)
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let graph = emgGraph(firstValues: Array(repeating: 0.5, count: 100)).enableDummyData()
        let BLE = BLEManager(emg: graph)
        BLE.startDummyData() // Enable dummy data in preview
        return ContentView(graph: graph, BLE: BLE)
            .previewInterfaceOrientation(.portrait)
    }
}

struct TextFile: FileDocument {
    static var readableContentTypes = [UTType.commaSeparatedText]
    static var preferredFilenameExtension: String? { "csv" }
    var text = ""

    init(initialText: String = "") {
        text = initialText
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            text = String(decoding: data, as: UTF8.self)
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(text.utf8)
        return FileWrapper(regularFileWithContents: data)
    }
}
