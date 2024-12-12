//
//  BLEManager.swift
//  EMG-ble-kth
//

import Foundation
import CoreBluetooth

struct Peripheral: Identifiable {
    let id: Int
    let name: String
    let rssi: Int
}

class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate {
    var myCentral: CBCentralManager!
    @Published var BLEisOn = false
    @Published var BLEPeripherals = [Peripheral]()
    @Published var isConnected = false
    var CBPeripherals = [CBPeripheral]()
    var emg: emgGraph

    // RMS Buffers and Calculation
    private var emgBuffer: [Float] = [] // Buffer for 0.1-second RMS calculation
    private let windowSize = 8 // 0.1 seconds at 8 Hz sampling rate
    @Published var currentRMS: Float = 0.0 // Latest 0.1-second RMS
    @Published var rmsHistory: [Float] = [] // Store historical 0.1-second RMS values

    private let dataQueue = DispatchQueue(label: "com.emg.ble.data")
    private var oneSecondRawBuffer: [Float] = [] // Buffer for raw data to calculate 1-second RMS
    private let oneSecondRawWindowSize = 80 // Assume 80 samples = 1 second at 80 Hz sampling rate
    @Published var oneSecondRawRMS: Float = 0.0 // Latest 1-second RMS calculated from raw data
    @Published var oneSecondRawRMSHistory: [Float] = [] // Historical 1-second RMS values

    init(emg: emgGraph) {
        self.emg = emg
        super.init()
        myCentral = CBCentralManager(delegate: self, queue: nil)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DispatchQueue.main.async {
            self.BLEisOn = (central.state == .poweredOn)
        }
    }

    func checkBluetoothPermissions() {
        switch myCentral.authorization {
        case .allowedAlways:
            print("Bluetooth is allowed")
        case .restricted, .denied:
            print("Bluetooth access denied")
        default:
            print("Bluetooth authorization pending")
        }
    }

    func startScanning() {
        guard !isConnected else {
            print("Already connected, skipping scanning.")
            return
        }
        print("Start Scanning")
        BLEPeripherals.removeAll()
        CBPeripherals.removeAll()
        myCentral.scanForPeripherals(withServices: nil)
    }

    func stopScanning() {
        print("Stop Scanning")
        myCentral.stopScan()
    }

    func connectSensor(p: Peripheral) {
        guard p.id < CBPeripherals.count else {
            print("Invalid peripheral ID")
            return
        }
        myCentral.connect(CBPeripherals[p.id])
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let peripheralName = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown"
        let targetDeviceName = "EMGBLE2"
        guard peripheralName == targetDeviceName else {
            print("Skipping device: \(peripheralName)")
            return
        }

        let newPeripheral = Peripheral(id: BLEPeripherals.count, name: peripheralName, rssi: RSSI.intValue)
        DispatchQueue.main.async {
            self.BLEPeripherals.append(newPeripheral)
        }
        CBPeripherals.append(peripheral)

        print("Added device: \(peripheralName) with RSSI: \(RSSI.intValue)")
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected to \(peripheral.name ?? "Unknown Device")")
        DispatchQueue.main.async {
            self.isConnected = true
        }
        myCentral.stopScan()
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Disconnected from \(peripheral.name ?? "Unknown Device")")
        DispatchQueue.main.async {
            self.isConnected = false
        }
    }

    // RMS Calculations and Updates
    func processAndAppendEMGData(_ rawEMGData: [Float]) {
        // Calculate mean and center the data
        let mean = rawEMGData.reduce(0.0, +) / Float(rawEMGData.count)
        let centeredData = rawEMGData.map { $0 - mean }

        DispatchQueue.main.async {
            self.emg.append(values: centeredData.map { CGFloat($0) })
        }

        // Update 0.1-second RMS
        updateShortTermRMS(with: centeredData)

        // Update 1-second RMS from raw data
        updateOneSecondRawRMS(with: rawEMGData)
    }

    func updateShortTermRMS(with newValues: [Float]) {
        dataQueue.async {
            self.emgBuffer.append(contentsOf: newValues)

            // Maintain a buffer for 0.1-second RMS
            if self.emgBuffer.count > self.windowSize {
                self.emgBuffer.removeFirst(self.emgBuffer.count - self.windowSize)
            }

            if self.emgBuffer.count == self.windowSize {
                // Calculate RMS for 0.1-second interval
                let shortTermRMS = self.calculateRMS(from: self.emgBuffer)

                DispatchQueue.main.async {
                    self.currentRMS = shortTermRMS
                    self.rmsHistory.append(shortTermRMS)
                    if self.rmsHistory.count > 100 {
                        self.rmsHistory.removeFirst()
                    }

                    print("Short-Term RMS (0.1s): \(shortTermRMS)")
                }
            }
        }
    }

    func updateOneSecondRawRMS(with newValues: [Float]) {
        dataQueue.async {
            // Append raw data to the 1-second buffer
            self.oneSecondRawBuffer.append(contentsOf: newValues)

            // Maintain buffer size for 1 second
            if self.oneSecondRawBuffer.count > self.oneSecondRawWindowSize {
                self.oneSecondRawBuffer.removeFirst(self.oneSecondRawBuffer.count - self.oneSecondRawWindowSize)
            }

            // Calculate RMS if the buffer is full
            if self.oneSecondRawBuffer.count == self.oneSecondRawWindowSize {
                let oneSecondRMS = self.calculateRMS(from: self.oneSecondRawBuffer)

                DispatchQueue.main.async {
                    self.oneSecondRawRMS = oneSecondRMS
                    self.oneSecondRawRMSHistory.append(oneSecondRMS)

                    // Limit history size
                    if self.oneSecondRawRMSHistory.count > 100 {
                        self.oneSecondRawRMSHistory.removeFirst()
                    }

                    print("1-Second RMS (Raw Data): \(oneSecondRMS)")
                }
            }
        }
    }

    func calculateRMS(from samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0.0 }
        let squaredSum = samples.reduce(0.0) { $0 + $1 * $1 }
        return sqrt(squaredSum / Float(samples.count))
    }
}

extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("Error discovering services: \(error.localizedDescription)")
            return
        }
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("Error discovering characteristics: \(error.localizedDescription)")
            return
        }
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            if characteristic.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Error updating value for characteristic: \(error.localizedDescription)")
            return
        }

        switch characteristic.uuid {
        case CBUUID(string: "E399EFC0-79F9-4E08-82A8-F3AA1DC609F1"):
            guard let characteristicData = characteristic.value else { return }
            let byteArray = [UInt8](characteristicData)
            guard byteArray.count % 2 == 0 else { return }

            var graphData: [Float] = []
            for i in stride(from: 0, to: byteArray.count, by: 2) {
                let value = Float(byteArray[i]) + Float(byteArray[i + 1]) * 256.0
                // Normalize to [-1, 1] range
                let normalizedValue = (value - 2048.0) / 2048.0
                graphData.append(normalizedValue)
            }
            processAndAppendEMGData(graphData)
        default:
            print("Unhandled characteristic UUID: \(characteristic.uuid)")
        }
    }
}



