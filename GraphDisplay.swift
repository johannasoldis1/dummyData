import CoreGraphics
import SwiftUI

class emgGraph: ObservableObject {
    @Published private(set) var values: [CGFloat] = [] // Raw EMG values for display
    @Published var max1SecRMS: CGFloat = 0.0 // Tracks the maximum 1-second RMS during recording
    @Published var max1SecRMSHistory: [CGFloat] = [] // History of max1SecRMS

    var recorded_values: [CGFloat] = [] // Recorded EMG values for export
    var recorded_rms: [CGFloat] = [] // RMS values for export
    var timestamps: [CFTimeInterval] = [] // Time for each recorded value
    var recording: Bool = false // Recording state
    var start_time: CFTimeInterval = 0 // Start time for recording
    var lastUpdateTime: Date = Date() // Last time the graph UI was updated
    private var buffer: [CGFloat] = [] // Buffer for short-term RMS calculations
    private let sampleRate: Int = 10 // Number of samples per second

    private var shortTermRMSBuffer: [Float] = [] // Buffer for 1-second RMS calculation
    private let shortTermRMSWindowSize = 10 // 10 samples for 1-second RMS

    init(firstValues: [CGFloat]) {
        values = firstValues
    }

    func record() {
        recording = true
        start_time = CACurrentMediaTime()
        DispatchQueue.main.async {
            self.max1SecRMS = 0.0 // Reset max RMS for new recording session
        }
        recorded_values.removeAll()
        recorded_rms.removeAll()
        timestamps.removeAll()
        buffer.removeAll()
        shortTermRMSBuffer.removeAll()
        max1SecRMSHistory.removeAll()
    }
    
    func stop_recording_and_save() -> String {
        recording = false
        let sampleInterval = 1.0 // 1-second intervals

        // Calculate centered raw data
        let mean = recorded_values.reduce(0.0, +) / CGFloat(recorded_values.count)
        let centeredValues = recorded_values.map { $0 - mean }

        // Header for CSV
        var dataset = "Time,1-Second RMS,Max RMS\n"

        // Export every 1-second interval
        for (index, rmsValue) in recorded_rms.enumerated() {
            guard index % sampleRate == 0 else { continue } // Only export 1-second intervals
            let time = Double(index) * sampleInterval

            // Ensure alignment with max RMS history
            let historyIndex = index / sampleRate
            let maxRMSValue = historyIndex < max1SecRMSHistory.count ? max1SecRMSHistory[historyIndex] : 0.0

            dataset += "\(time),\(rmsValue),\(maxRMSValue)\n"
        }

        // Save dataset to file
        saveToFile(dataset)
        return dataset
    }

    private func saveToFile(_ dataset: String) {
        DispatchQueue.global(qos: .background).async {
            let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            let date = Date()
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH_mm_ss"

            let filename = paths[0].appendingPathComponent("emg_data_" + dateFormatter.string(from: date) + ".csv")
            do {
                try dataset.write(to: filename, atomically: true, encoding: .utf8)
                print("File saved successfully")
            } catch {
                print("Failed to write file: \(error.localizedDescription)")
            }
        }
    }

    func append(value: CGFloat) {
        let now = CACurrentMediaTime() // High-precision timestamp for recording
        if recording {
            recorded_values.append(value)
            timestamps.append(now - start_time)
            buffer.append(value)

            // Maintain buffer size for short-term RMS calculation
            if buffer.count > sampleRate {
                buffer.removeFirst(buffer.count - sampleRate)
            }

            // Calculate short-term RMS if buffer is full
            if buffer.count == sampleRate {
                let rmsValue = calculateRMS(for: buffer)
                DispatchQueue.main.async {
                    self.recorded_rms.append(rmsValue)
                }
                updateMoving1SecRMS(fromShortTermRMS: Float(rmsValue))
            } else {
                DispatchQueue.main.async {
                    self.recorded_rms.append(0.0)
                }
            }
        }

        // Throttle UI updates for performance
        let currentTime = Date()
        if currentTime.timeIntervalSince(lastUpdateTime) > 0.1 {
            DispatchQueue.main.async {
                self.values.append(value)
                self.lastUpdateTime = currentTime
            }
        }
    }

    func append(values: [CGFloat]) {
        let now = CACurrentMediaTime()
        if recording {
            recorded_values += values
            timestamps.append(contentsOf: values.map { _ in now - start_time })

            for value in values {
                buffer.append(value)

                // Maintain buffer size for short-term RMS calculation
                if buffer.count > sampleRate {
                    buffer.removeFirst(buffer.count - sampleRate)
                }

                if buffer.count == sampleRate {
                    let rmsValue = calculateRMS(for: buffer)
                    DispatchQueue.main.async {
                        self.recorded_rms.append(rmsValue)
                    }
                    updateMoving1SecRMS(fromShortTermRMS: Float(rmsValue))
                } else {
                    DispatchQueue.main.async {
                        self.recorded_rms.append(0.0)
                    }
                }
            }
        }

        DispatchQueue.main.async {
            self.values += values

            // Keep UI values limited to a maximum count
            if self.values.count > 1000 {
                self.values.removeFirst(self.values.count - 1000)
            }
        }
    }

    func calculateRMS(for values: [CGFloat]) -> CGFloat {
        guard !values.isEmpty else { return 0.0 }
        let mean = values.reduce(0.0, +) / CGFloat(values.count)
        let centeredValues = values.map { $0 - mean }
        let squaredSum = centeredValues.reduce(0.0) { $0 + $1 * $1 }
        return sqrt(squaredSum / CGFloat(centeredValues.count))
    }

    private func updateMoving1SecRMS(fromShortTermRMS newRMS: Float) {
        shortTermRMSBuffer.append(newRMS)

        if shortTermRMSBuffer.count > shortTermRMSWindowSize {
            shortTermRMSBuffer.removeFirst()
        }

        if shortTermRMSBuffer.count == shortTermRMSWindowSize {
            let sumOfSquares = shortTermRMSBuffer.reduce(0.0) { $0 + $1 * $1 }
            let oneSecondRMS = sqrt(sumOfSquares / Float(shortTermRMSBuffer.count))

            DispatchQueue.main.async {
                self.max1SecRMSHistory.append(CGFloat(oneSecondRMS))
                if self.max1SecRMSHistory.count > 100 {
                    self.max1SecRMSHistory.removeFirst()
                }
                self.max1SecRMS = max(self.max1SecRMS, CGFloat(oneSecondRMS))
            }
        }
    }
}

