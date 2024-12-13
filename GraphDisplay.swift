import CoreGraphics
import SwiftUI

class emgGraph: ObservableObject {
    @Published var values: [CGFloat] = [] // Raw EMG values for display
    @Published var oneSecondRMSHistory: [CGFloat] = [] // 1-second RMS values for display
    @Published var shortTermRMSHistory: [CGFloat] = [] // Short-term RMS values for display
    @Published var max10SecRMSHistory: [CGFloat] = [] // Max RMS values for the last 10 seconds

    var recorded_values: [CGFloat] = [] // Recorded raw EMG values for export
    var recorded_rms: [CGFloat] = [] // 1-second RMS values for export
    var shortTermRMSValues: [Float] = [] // Short-term RMS values for export
    var timestamps: [CFTimeInterval] = [] // Timestamps for each recorded value

    var recording: Bool = false // Recording state
    var start_time: CFTimeInterval = 0 // Start time for recording
    private var buffer: [CGFloat] = [] // Buffer for short-term RMS calculations
    private let sampleRate: Int = 10 // Number of samples per second

    private var shortTermRMSBuffer: [Float] = [] // Buffer for 1-second RMS calculation
    private let shortTermRMSWindowSize = 100 // 10 samples for 1-second RMS

    private var longTermRMSBuffer: [CGFloat] = [] // Buffer for 10-second max RMS calculation
    private let longTermRMSWindowSize = 10 // 10 x 1-second RMS values

    init(firstValues: [CGFloat]) {
        values = firstValues
    }

    func record() {
        recording = true
        start_time = CACurrentMediaTime()
        recorded_values.removeAll()
        recorded_rms.removeAll()
        shortTermRMSValues.removeAll()
        max10SecRMSHistory.removeAll()
        timestamps.removeAll()
        buffer.removeAll()
        shortTermRMSBuffer.removeAll()
        longTermRMSBuffer.removeAll()
    }
    
    func stop_recording_and_save() -> String {
        recording = false

        // Header for CSV
        var dataset = "Sample,EMG (Raw Data),Short-Term RMS (0.1s),1-Second RMS,Max RMS (10s)\n"

        // Export raw EMG data, short-term RMS, 1-second RMS, and max RMS
        for (index, rawValue) in recorded_values.enumerated() {
            let sampleIndex = index // Use index directly as the sample number
            let shortTermRMS = index < shortTermRMSValues.count ? shortTermRMSValues[index] : 0.0
            var oneSecondRMS: Float = 0.0
            var maxRMSString = ""

            // 1-Second RMS: Update every 10 samples
            if index % sampleRate == 0 && index / sampleRate < recorded_rms.count {
                oneSecondRMS = Float(recorded_rms[index / sampleRate])
            }

            // Max RMS over 10 seconds: Update every 10 seconds
            if index % (sampleRate * 10) == 0 && index > 0 {
                let startIndex = max(0, index - (sampleRate * 10 - 1)) / sampleRate
                let endIndex = index / sampleRate
                if startIndex < recorded_rms.count && endIndex < recorded_rms.count {
                    let maxRMS = recorded_rms[startIndex...endIndex].max() ?? 0.0
                    maxRMSString = "\(maxRMS)"
                }
            }

            dataset += "\(sampleIndex),\(rawValue),\(shortTermRMS),\(oneSecondRMS),\(maxRMSString)\n"
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

    func append(values: [CGFloat]) {
        let now = CACurrentMediaTime() // High-precision timestamp for recording
        if recording {
            recorded_values.append(contentsOf: values)
            timestamps.append(contentsOf: values.map { _ in now - start_time })

            for value in values {
                buffer.append(value)

                // Maintain buffer size for short-term RMS calculation
                if buffer.count > sampleRate {
                    buffer.removeFirst(buffer.count - sampleRate)
                }

                // Calculate short-term RMS if buffer is full
                if buffer.count == sampleRate {
                    let rmsValue = calculateRMS(for: buffer)
                    DispatchQueue.main.async {
                        self.shortTermRMSValues.append(Float(rmsValue)) // Append short-term RMS
                        self.shortTermRMSHistory.append(rmsValue) // Update display history
                        self.recorded_rms.append(rmsValue) // Append 1-second RMS
                        self.updateGraphDisplay(for: values, rmsValue: rmsValue)
                    }
                    updateMoving1SecRMS(fromShortTermRMS: Float(rmsValue))
                }
            }
        }

        DispatchQueue.main.async {
            self.values.append(contentsOf: values)

            // Limit raw data points for display
            if self.values.count > 1000 {
                self.values.removeFirst(self.values.count - 1000)
            }
        }
    }

    func calculateRMS(for values: [CGFloat]) -> CGFloat {
        guard !values.isEmpty else { return 0.0 }
        let squaredSum = values.reduce(0.0) { $0 + $1 * $1 }
        return sqrt(squaredSum / CGFloat(values.count))
    }

    private func updateMoving1SecRMS(fromShortTermRMS newRMS: Float) {
        shortTermRMSBuffer.append(newRMS)

        if shortTermRMSBuffer.count > shortTermRMSWindowSize {
            shortTermRMSBuffer.removeFirst()
        }

        if shortTermRMSBuffer.count == shortTermRMSWindowSize {
            let oneSecondRMS = calculateRMS(for: shortTermRMSBuffer.map { CGFloat($0) })

            DispatchQueue.main.async {
                self.oneSecondRMSHistory.append(oneSecondRMS)
                if self.oneSecondRMSHistory.count > 100 {
                    self.oneSecondRMSHistory.removeFirst()
                }
            }

            // Update 10-second max RMS
            updateMax10SecRMS(oneSecondRMS)
        }
    }

    private func updateMax10SecRMS(_ oneSecondRMS: CGFloat) {
        longTermRMSBuffer.append(oneSecondRMS)

        // Maintain a buffer size of 10 (representing 10 seconds)
        if longTermRMSBuffer.count > longTermRMSWindowSize {
            longTermRMSBuffer.removeFirst()
        }

        // Calculate the maximum RMS over the last 10 seconds
        let maxRMS = longTermRMSBuffer.max() ?? 0.0

        DispatchQueue.main.async {
            self.max10SecRMSHistory.append(maxRMS)
            if self.max10SecRMSHistory.count > 100 {
                self.max10SecRMSHistory.removeFirst()
            }
        }
    }

    private func updateGraphDisplay(for rawValues: [CGFloat], rmsValue: CGFloat) {
        self.values.append(contentsOf: rawValues)
        if self.values.count > 1000 {
            self.values.removeFirst(self.values.count - 1000)
        }
        self.shortTermRMSHistory.append(rmsValue)
        if self.shortTermRMSHistory.count > 100 {
            self.shortTermRMSHistory.removeFirst()
        }
    }
}
