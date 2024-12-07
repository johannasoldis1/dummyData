import CoreGraphics
import SwiftUI

class emgGraph: ObservableObject {
    // Published properties for UI updates
    @Published private(set) var values: [CGFloat] = [] // Raw EMG values for display
    @Published var max1SecRMS: CGFloat = 0.0 // Tracks the maximum 1-second RMS during recording
    @Published var max1SecRMSHistory: [CGFloat] = [] // History of max1SecRMS

    // Internal buffers and settings
    var recorded_values: [CGFloat] = [] // Recorded EMG values for export
    var recorded_rms: [CGFloat] = [] // RMS values for export
    var timestamps: [CFTimeInterval] = [] // Time for each recorded value
    var recording: Bool = false // Recording state
    var start_time: CFTimeInterval = 0 // Start time for recording
    var lastUpdateTime: Date = Date() // Last time the graph UI was updated
    private var buffer: [CGFloat] = [] // Buffer for short-term RMS calculations
    private let sampleRate: Int = 10 // Number of samples per second

    // Short-term and 1-second RMS buffers
    private var shortTermRMSBuffer: [Float] = []
    private let shortTermRMSWindowSize = 10 // 10 samples for 1-second RMS

    // Initialize the class
    init(firstValues: [CGFloat]) {
        values = firstValues
    }

    // Start recording
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
    }
    
    func stop_recording_and_save() -> String {
        recording = false
        let sampleInterval = 1.0 / Double(sampleRate)

        let mean = recorded_values.reduce(0.0, +) / CGFloat(recorded_values.count)
        let centeredValues = recorded_values.map { $0 - mean }

        var dataset = "Time,EMG,RMS,Max1SecRMS\n"
        for (index, value) in centeredValues.enumerated() {
            let time = Double(index) * sampleInterval
            let rmsValue = index < recorded_rms.count ? recorded_rms[index] : 0.0
            let maxRMSValue = index < max1SecRMSHistory.count ? max1SecRMSHistory[index] : 0.0
            dataset += "\(time),\(value),\(rmsValue),\(maxRMSValue)\n"
        }

        saveToFile(dataset)
        return dataset
    }

    private func saveToFile(_ dataset: String) {
        DispatchQueue.global(qos: .background).async {
            let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            let date = Date()
            let dateformatter = DateFormatter()
            dateformatter.dateFormat = "yyyy-MM-dd'T'HH_mm_ss"

            let filename = paths[0].appendingPathComponent("emg_data_" + dateformatter.string(from: date) + ".csv")
            do {
                try dataset.write(to: filename, atomically: true, encoding: .utf8)
                print("File saved successfully")
            } catch {
                print("Failed to write file: \(error.localizedDescription)")
            }
        }
    }

    // Append a single value to the graph and recording buffers
    func append(value: CGFloat) {
        let now = CACurrentMediaTime() // Use high-precision timestamp for recording
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

    // Append multiple values at once
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

    // Calculate RMS for an array of values
    func calculateRMS(for values: [CGFloat]) -> CGFloat {
        guard !values.isEmpty else { return 0.0 }
        let mean = values.reduce(0.0, +) / CGFloat(values.count)
        let centeredValues = values.map { $0 - mean }
        let squaredSum = centeredValues.reduce(0.0) { $0 + $1 * $1 }
        return sqrt(squaredSum / CGFloat(centeredValues.count))
    }

    // Update 1-second RMS based on short-term RMS values
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
