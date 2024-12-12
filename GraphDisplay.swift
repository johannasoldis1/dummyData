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

    // Short-term and 1-second RMS buffers with updated sizes
    private var buffer: [CGFloat] = [] // Buffer for short-term RMS calculations
    private let shortTermRMSWindowSize = 10 // Start with 10 samples for short-term RMS

    private var oneSecondRawBuffer: [CGFloat] = [] // Buffer for raw data to calculate 1-second RMS
    private let oneSecondRawWindowSize = 100 // Start with 100 samples for 1-second RMS

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
        oneSecondRawBuffer.removeAll()
        longTermRMSBuffer.removeAll()
    }

    func stop_recording_and_save() -> String {
        recording = false

        // Header for CSV
        var dataset = "Sample,EMG (Raw Data),Short-Term RMS,1-Second RMS,Max RMS (10s)\n"

        for (index, rawValue) in recorded_values.enumerated() {
            let shortTermRMS = index < shortTermRMSValues.count ? shortTermRMSValues[index] : 0.0
            let oneSecondRMS = index < recorded_rms.count ? recorded_rms[index] : 0.0
            let maxRMSString = index % oneSecondRawWindowSize == 0 && index > 0 ? "\(longTermRMSBuffer.max() ?? 0.0)" : ""

            dataset += "\(index),\(rawValue),\(shortTermRMS),\(oneSecondRMS),\(maxRMSString)\n"
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
        let now = CACurrentMediaTime() // High-precision timestamp for recording
        if recording {
            recorded_values.append(contentsOf: values)
            timestamps.append(contentsOf: values.map { _ in now - start_time })

            for value in values {
                // Update short-term RMS
                buffer.append(value)
                if buffer.count > shortTermRMSWindowSize {
                    buffer.removeFirst(buffer.count - shortTermRMSWindowSize)
                }
                if buffer.count == shortTermRMSWindowSize {
                    let shortTermRMS = calculateRMS(for: buffer)
                    DispatchQueue.main.async {
                        self.shortTermRMSHistory.append(shortTermRMS)
                        self.shortTermRMSValues.append(Float(shortTermRMS))
                    }
                }

                // Update 1-second RMS
                oneSecondRawBuffer.append(value)
                if oneSecondRawBuffer.count > oneSecondRawWindowSize {
                    oneSecondRawBuffer.removeFirst(oneSecondRawBuffer.count - oneSecondRawWindowSize)
                }
                if oneSecondRawBuffer.count == oneSecondRawWindowSize {
                    let oneSecondRMS = calculateRMS(for: oneSecondRawBuffer)
                    DispatchQueue.main.async {
                        self.oneSecondRMSHistory.append(oneSecondRMS)
                        self.recorded_rms.append(oneSecondRMS)
                    }
                    updateMax10SecRMS(oneSecondRMS)
                }
            }
        }

        DispatchQueue.main.async {
            self.values.append(contentsOf: values)
            if self.values.count > 1000 {
                self.values.removeFirst(self.values.count - 1000)
            }
        }
    }

    private func calculateRMS(for values: [CGFloat]) -> CGFloat {
        guard !values.isEmpty else { return 0.0 }
        let squaredSum = values.reduce(0.0) { $0 + $1 * $1 }
        return sqrt(squaredSum / CGFloat(values.count))
    }

    private func updateMax10SecRMS(_ oneSecondRMS: CGFloat) {
        longTermRMSBuffer.append(oneSecondRMS)
        if longTermRMSBuffer.count > longTermRMSWindowSize {
            longTermRMSBuffer.removeFirst()
        }
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

