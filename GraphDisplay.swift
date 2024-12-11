import CoreGraphics
import SwiftUI

class emgGraph: ObservableObject {
    @Published var values: [CGFloat] = [] // Raw EMG values for display
    @Published var oneSecondRMSHistory: [CGFloat] = [] // 1-second RMS values for display
    @Published var shortTermRMSHistory: [CGFloat] = [] // Short-term RMS (0.1s) values for display
    @Published var max10SecRMSHistory: [CGFloat] = [] // Max RMS values for the last 10 seconds

    var recorded_values: [CGFloat] = [] // Recorded raw EMG values for export
    var recorded_rms: [CGFloat] = [] // 1-second RMS values for export
    var shortTermRMSValues: [Float] = [] // Short-term RMS values for export
    var timestamps: [CFTimeInterval] = [] // Timestamps for each recorded value

    var recording: Bool = false // Recording state
    var start_time: CFTimeInterval = 0 // Start time for recording
    private let sampleRate: Int = 128 // Number of samples per second

    private var shortTermRMSBuffer: [Float] = [] // Buffer for short-term (0.1s) RMS calculation
    private let shortTermRMSWindowSize = 13 // 0.1 seconds of samples at 128 Hz

    private var oneSecondRMSBuffer: [CGFloat] = [] // Buffer for 1-second RMS calculation
    private let oneSecondRMSWindowSize = 128 // 1 second of samples at 128 Hz

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
        shortTermRMSBuffer.removeAll()
        oneSecondRMSBuffer.removeAll()
        longTermRMSBuffer.removeAll()
    }
    
    func stop_recording_and_save() -> String {
        recording = false
        let sampleInterval = 1.0 / Double(sampleRate)

        // Header for CSV
        var dataset = "Time,EMG (Raw Data),Short-Term RMS (0.1s),1-Second RMS,Max RMS (10s)\n"

        // Export raw EMG data, short-term RMS, 1-second RMS, and max RMS
        for (index, rawValue) in recorded_values.enumerated() {
            let time = Double(index) * sampleInterval
            let shortTermRMS = index < shortTermRMSValues.count ? shortTermRMSValues[index] : 0.0
            let oneSecondRMS = index < recorded_rms.count ? recorded_rms[index] : 0.0
            let maxRMS = (index / sampleRate) < max10SecRMSHistory.count ? max10SecRMSHistory[index / sampleRate] : 0.0

            dataset += "\(time),\(rawValue),\(shortTermRMS),\(oneSecondRMS),\(maxRMS)\n"
        }

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
        let now = CACurrentMediaTime()

        if recording {
            recorded_values.append(contentsOf: values)
            timestamps.append(contentsOf: values.map { _ in now - start_time })

            for value in values {
                // Update short-term RMS (0.1s)
                shortTermRMSBuffer.append(Float(value))
                if shortTermRMSBuffer.count > shortTermRMSWindowSize {
                    shortTermRMSBuffer.removeFirst()
                }

                if shortTermRMSBuffer.count == shortTermRMSWindowSize {
                    let shortTermRMS = calculateRMS(for: shortTermRMSBuffer.map { CGFloat($0) })
                    DispatchQueue.main.async {
                        self.shortTermRMSValues.append(Float(shortTermRMS))
                        self.shortTermRMSHistory.append(shortTermRMS)
                        self.updateGraphDisplay(for: values, rmsValue: shortTermRMS)
                    }
                }

                // Update 1-second RMS
                oneSecondRMSBuffer.append(value)
                if oneSecondRMSBuffer.count > oneSecondRMSWindowSize {
                    oneSecondRMSBuffer.removeFirst()
                }

                if oneSecondRMSBuffer.count == oneSecondRMSWindowSize {
                    let oneSecondRMS = calculateRMS(for: oneSecondRMSBuffer)
                    DispatchQueue.main.async {
                        self.recorded_rms.append(oneSecondRMS)
                        self.oneSecondRMSHistory.append(oneSecondRMS)
                    }

                    // Update 10-second max RMS
                    updateMax10SecRMS(oneSecondRMS)
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
    
    private func updateMax10SecRMS(_ oneSecondRMS: CGFloat) {
        longTermRMSBuffer.append(oneSecondRMS)

        if longTermRMSBuffer.count > longTermRMSWindowSize {
            longTermRMSBuffer.removeFirst()
        }

        let maxRMS = longTermRMSBuffer.max() ?? 0.0
        DispatchQueue.main.async {
            self.max10SecRMSHistory.append(maxRMS)
            if self.max10SecRMSHistory.count > self.longTermRMSWindowSize { // Explicit use of `self`
                self.max10SecRMSHistory.removeFirst()
            }
        }
    }

    func calculateRMS(for values: [CGFloat]) -> CGFloat {
        guard !values.isEmpty else { return 0.0 }
        let squaredSum = values.reduce(0.0) { $0 + $1 * $1 }
        return sqrt(squaredSum / CGFloat(values.count))
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


