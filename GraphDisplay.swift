//
//  emgGraphDisplay.swift
//  EMG-ble-kth
//
//  Created by Linus Remahl on 2021-10-31.
//

import CoreGraphics
import SwiftUI

class emgGraph: ObservableObject {
    @Published private(set) var values: Array<CGFloat>
    var recorded_values: Array<CGFloat> = []
    var recorded_rms: Array<CGFloat> = []
    var timestamps: Array<CFTimeInterval> = [] // Store timestamps for each value
    var recording: Bool = false
    var start_time: CFTimeInterval = 0
    var lastUpdateTime: Date = Date()
    @Published var max1SecRMS: CGFloat = 0.0 // Tracks the maximum 1-second RMS during recording
    private var buffer: [CGFloat] = [] // Buffer for short-term RMS calculations
    private let sampleRate: Int = 10 // Number of samples per second

    // 1-second RMS buffer and settings
    private var shortTermRMSBuffer: [Float] = []
    private let shortTermRMSWindowSize = 10 // 10 samples for 1-second RMS

    init(firstValues: Array<CGFloat>) {
        values = firstValues
    }

    func record() {
        recording = true
        start_time = CACurrentMediaTime()
        max1SecRMS = 0.0 // Reset max RMS for new recording session
        recorded_values.removeAll()
        recorded_rms.removeAll()
        timestamps.removeAll()
        buffer.removeAll()
        shortTermRMSBuffer.removeAll() // Clear the 1-second buffer
    }
    
    func stop_recording_and_save() -> String {
        recording = false
        let sampleInterval = 1.0 / Double(sampleRate) // Interval per sample (e.g., 0.1 seconds for 10 Hz)

        // Prepare CSV dataset
        var dataset = "Time,EMG,RMS,Max1SecRMS\n"
        for (index, value) in recorded_values.enumerated() {
            let time = Double(index) * sampleInterval // Calculate time based on index
            let rmsValue = index < recorded_rms.count ? recorded_rms[index] : 0.0
            let maxRMSValue = max1SecRMS // Use consistent Max1SecRMS
            dataset += "\(time),\(value),\(rmsValue),\(maxRMSValue)\n"
        }

        // Save dataset to file
        DispatchQueue.global(qos: .background).async {
            let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            let date = Date()
            let dateformatter = DateFormatter()
            dateformatter.locale = Locale(identifier: "en_US_POSIX")
            dateformatter.dateFormat = "yyyy-MM-dd'T'HH_mm_ss"

            let filename = paths[0].appendingPathComponent("emg_data_" +
                dateformatter.string(from: date) +
                ".csv")
            do {
                try dataset.write(to: filename, atomically: true, encoding: .utf8)
                print("File saved successfully")
            } catch {
                print("Failed to write file: \(error.localizedDescription)")
            }
        }

        // Clear buffers
        recorded_values.removeAll()
        recorded_rms.removeAll()
        buffer.removeAll()
        shortTermRMSBuffer.removeAll()
        return dataset
    }

    func append(value: CGFloat) {
        let now = CACurrentMediaTime() // Use high-precision timestamp for recording
        if recording {
            recorded_values.append(value)
            timestamps.append(now - start_time) // Store relative time
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

                // Update 1-second RMS using the new method
                updateMoving1SecRMS(fromShortTermRMS: Float(rmsValue))
            } else {
                DispatchQueue.main.async {
                    self.recorded_rms.append(0.0) // Pad with zero if buffer is not yet full
                }
            }
        }

        // Throttle UI updates for performance
        let currentTime = Date()
        if currentTime.timeIntervalSince(lastUpdateTime) > 0.1 { // Throttle to 10 Hz updates
            DispatchQueue.main.async {
                self.values.append(value)
                self.lastUpdateTime = currentTime
            }
        }
    }

    func append(values: Array<CGFloat>) {
        let now = CACurrentMediaTime() // Capture timestamp once for consistency
        if recording {
            self.recorded_values += values
            self.timestamps.append(contentsOf: values.map { _ in now - start_time })

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
                        self.recorded_rms.append(rmsValue)
                    }

                    // Update 1-second RMS using the new method
                    updateMoving1SecRMS(fromShortTermRMS: Float(rmsValue))
                } else {
                    DispatchQueue.main.async {
                        self.recorded_rms.append(0.0) // Pad with zero if buffer is not yet full
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
        let squaredSum = values.reduce(0.0) { $0 + $1 * $1 }
        let result = sqrt(squaredSum / CGFloat(values.count))
        return result.isNaN ? 0.0 : result // Prevent NaN values
    }

    private func updateMoving1SecRMS(fromShortTermRMS newRMS: Float) {
        shortTermRMSBuffer.append(newRMS)

        // Maintain a rolling 1-second buffer
        if shortTermRMSBuffer.count > shortTermRMSWindowSize {
            shortTermRMSBuffer.removeFirst()
        }

        // Calculate the maximum RMS over the buffer
        if !shortTermRMSBuffer.isEmpty {
            let maxRMS = shortTermRMSBuffer.max() ?? 0.0
            DispatchQueue.main.async {
                self.max1SecRMS = CGFloat(maxRMS.isNaN ? 0.0 : maxRMS) // Prevent NaN values
            }
        }
    }
}

