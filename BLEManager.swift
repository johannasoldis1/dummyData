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
    private var emgBuffer: [Float] = []
    private let windowSize = 16 // 128 ms at 8 Hz
    @Published var currentRMS: Float = 0.0
    @Published var rmsHistory: [Float] = []
    private let dataQueue = DispatchQueue(label: "com.emg.ble.data")
    
    // 1-Second RMS and Maximum Calculation
    private var shortTermRMSBuffer: [Float] = [] // Buffer for 0.1-second RMS values
    private let shortTermRMSWindowSize = 10 // 10 x 0.1s = 1 second
    private var maxRMSOverTime: Float = 0.0
    private let maxRMSUpdateInterval: TimeInterval = 1.0
    private var lastMaxRMSUpdateTime: Date = Date()
    @Published var max1SecRMS: Float = 0.0
    @Published var max1SecRMSHistory: [Float] = []
    
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
    
    // RMS calculations and updates
    func processAndAppendEMGData(_ rawEMGData: [Float]) {
        // Calculate mean and center the data
        let mean = rawEMGData.reduce(0.0, +) / Float(rawEMGData.count)
        let centeredData = rawEMGData.map { $0 - mean }
        
        DispatchQueue.main.async {
            self.emg.append(values: centeredData.map { CGFloat($0) })
        }
        
        // Proceed with RMS calculations
        updateRMS(with: centeredData)
    }
    
    func updateRMS(with newValues: [Float]) {
        dataQueue.async {
            self.emgBuffer.append(contentsOf: newValues)
            
            if self.emgBuffer.count > self.windowSize {
                self.emgBuffer.removeFirst(self.emgBuffer.count - self.windowSize)
            }
            
            if self.emgBuffer.count == self.windowSize {
                let rms = self.calculateRMS(from: self.emgBuffer)
                
                DispatchQueue.main.async {
                    self.currentRMS = rms
                    self.rmsHistory.append(rms)
                    if self.rmsHistory.count > 100 {
                        self.rmsHistory.removeFirst()
                    }
                }
                
                // Update 1-second RMS and maximum RMS
                self.updateMoving1SecRMS(fromShortTermRMS: rms)
            }
        }
    }
    
    func calculateRMS(from samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0.0 }
        let squaredSum = samples.reduce(0.0) { $0 + $1 * $1 }
        return sqrt(squaredSum / Float(samples.count))
    }

    private func updateMoving1SecRMS(fromShortTermRMS newRMS: Float) {
        // Add the new 0.1-second RMS value to the buffer
        shortTermRMSBuffer.append(newRMS)

        // Maintain a buffer size of 10 (representing 1 second of data)
        if shortTermRMSBuffer.count > shortTermRMSWindowSize {
            shortTermRMSBuffer.removeFirst()
        }

        // Calculate the 1-second RMS using a moving average if the buffer is full
        if shortTermRMSBuffer.count == shortTermRMSWindowSize {
            let movingAverageRMS = shortTermRMSBuffer.reduce(0.0) { $0 + $1 } / Float(shortTermRMSBuffer.count)

            DispatchQueue.main.async {
                // Update the 1-second RMS history
                self.max1SecRMSHistory.append(movingAverageRMS)
                if self.max1SecRMSHistory.count > 100 {
                    self.max1SecRMSHistory.removeFirst()
                }
            }

            // Update the maximum RMS for the last 1-second interval
            self.updateMaxRMS(movingAverageRMS)
        }
    }
    private func updateMaxRMS(_ oneSecondRMS: Float) {
        let currentTime = Date()
        maxRMSOverTime = max(maxRMSOverTime, oneSecondRMS)

        // Ensure proper update timing
        if currentTime.timeIntervalSince(lastMaxRMSUpdateTime) >= maxRMSUpdateInterval {
            DispatchQueue.main.async {
                self.max1SecRMS = self.maxRMSOverTime
            }
            maxRMSOverTime = oneSecondRMS // Start tracking from current value
            lastMaxRMSUpdateTime = currentTime
        }
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
                graphData.append(value / 4096.0)
            }

            processAndAppendEMGData(graphData)
        default:
            print("Unhandled characteristic UUID: \(characteristic.uuid)")
        }
    }
}
