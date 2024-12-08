import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var graph: emgGraph
    @ObservedObject var BLE: BLEManager
    @State private var showingExporter = false
    @State var file_content: TextFile = TextFile(initialText: "")

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 10) {

                // Raw EMG Graph
                VStack {
                    Text("Raw EMG Data")
                        .font(.headline)

                    Path { path in
                        let height = geometry.size.height / 8
                        let width = geometry.size.width

                        guard graph.values.count > 1 else { return }

                        let firstSample = max(0, graph.values.count - 50)
                        let cutGraph = graph.values[firstSample..<graph.values.count]
                        let midY = height / 2

                        guard !cutGraph.isEmpty else { return }

                        path.move(to: CGPoint(x: 0, y: midY - height / 2 * CGFloat(cutGraph.first ?? 0)))

                        for (index, value) in cutGraph.enumerated() {
                            let x = width * CGFloat(index) / CGFloat(cutGraph.count - 1)
                            let y = midY - height / 2 * CGFloat(value)
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    .stroke(Color.blue, lineWidth: 1.5)
                    .frame(height: geometry.size.height / 8)
                }

                // 1-Second RMS Graph
                VStack {
                    Text("1-Second RMS Data")
                        .font(.headline)

                    Path { path in
                        let height = geometry.size.height / 12
                        let width = geometry.size.width

                        guard !graph.max1SecRMSHistory.isEmpty else { return }
                        let midY = height / 2

                        path.move(to: CGPoint(x: 0, y: midY - height / 2 * CGFloat(graph.max1SecRMSHistory.first ?? 0)))

                        for (index, value) in graph.max1SecRMSHistory.enumerated() {
                            let x = CGFloat(index) * width / CGFloat(graph.max1SecRMSHistory.count - 1)
                            let y = midY - height / 2 * CGFloat(value)
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    .stroke(Color.green, lineWidth: 2.0)
                    .frame(height: geometry.size.height / 12)
                }

                // Current 1-Second RMS Value
                Text("1-Second RMS: \(graph.max1SecRMS, specifier: "%.2f")")
                    .font(.system(size: 14))
                    .foregroundColor(.green)

                // Connect to Sensor Section
                if !BLE.isConnected {
                    VStack {
                        Text("Connect to Sensor")
                            .font(.headline)

                        List(BLE.BLEPeripherals) { peripheral in
                            HStack {
                                Text(peripheral.name).onTapGesture {
                                    BLE.connectSensor(p: peripheral)
                                }
                                Spacer()
                                Text("\(peripheral.rssi)")
                            }
                        }
                        .frame(height: geometry.size.height / 10)
                    }
                } else {
                    Text("Connected to EMGBLE2!")
                        .font(.headline)
                        .foregroundColor(.green)
                }

                // Status Display
                VStack {
                    Text("STATUS")
                        .font(.headline)
                    if BLE.BLEisOn {
                        Text("Bluetooth is switched on")
                            .foregroundColor(.green)
                    } else {
                        Text("Bluetooth is NOT switched on")
                            .foregroundColor(.red)
                    }
                }

                // Buttons for Bluetooth scanning and recording
                HStack {
                    VStack(spacing: 5) {
                        Button("Start Scanning") { BLE.startScanning() }
                            .disabled(BLE.isConnected)

                        Button("Stop Scanning") { BLE.stopScanning() }
                            .disabled(!BLE.BLEisOn || BLE.isConnected)
                    }
                    .padding()

                    Spacer()

                    VStack(spacing: 5) {
                        Button("Start Recording") {
                            DispatchQueue.global(qos: .background).async {
                                graph.record()
                                DispatchQueue.main.async {
                                    print("Recording started.")
                                }
                            }
                        }

                        Button("Stop Recording") {
                            DispatchQueue.global(qos: .background).async {
                                let fileContent = graph.stop_recording_and_save()
                                DispatchQueue.main.async {
                                    file_content.text = fileContent
                                    print("Recording stopped and saved.")
                                }
                            }
                        }

                        Button("Export last") { showingExporter = true }
                    }
                    .padding()
                }
            }
            .padding(10)
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


