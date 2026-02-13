import AVFoundation
import Accelerate

/// AVAudioEngine-based recorder with Accelerate FFT for waveform visualization.
/// Same parameters as Python: 16kHz, mono, float32, 512-sample FFT, 25 exponential bars,
/// 70/30 smoothing, 0.08 RMS silence gate.
final class AudioRecorder {
    // Visualization parameters (match recorder.py)
    static let numBars = 25
    static let fftSize = 512
    static let smoothing: Float = 0.7
    static let silenceThreshold: Float = 0.08
    static let minFreqBin = 4

    var onLevels: (([Float]) -> Void)?

    private var engine: AVAudioEngine?
    private var audioData: [Float] = []
    private var prevLevels = [Float](repeating: 0, count: numBars)
    private let sampleRate: Double = 16000

    // FFT setup (reusable)
    private let log2n = vDSP_Length(log2(Float(fftSize)))
    private lazy var fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
    private var window = [Float](repeating: 0, count: fftSize)

    init() {
        // Pre-compute Hanning window
        vDSP_hann_window(&window, vDSP_Length(Self.fftSize), Int32(vDSP_HANN_NORM))
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    func start() {
        audioData = []
        prevLevels = [Float](repeating: 0, count: Self.numBars)

        engine = AVAudioEngine()
        guard let engine else { return }

        let inputNode = engine.inputNode
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!

        // Install tap on input
        inputNode.installTap(onBus: 0, bufferSize: AVAudioFrameCount(Self.fftSize), format: format) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }

        do {
            try engine.start()
            print("[AudioRecorder] Recording started")
        } catch {
            print("[AudioRecorder] Failed to start: \(error)")
        }
    }

    func stop() -> [Float] {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil

        let audio = audioData
        let duration = Float(audio.count) / Float(sampleRate)
        print("[AudioRecorder] Captured \(String(format: "%.2f", duration))s, \(audio.count) samples")
        return audio
    }

    // MARK: - Audio processing

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)

        // Accumulate raw audio
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
        audioData.append(contentsOf: samples)

        // FFT-based waveform visualization
        guard let onLevels else { return }

        // RMS gate
        var rms: Float = 0
        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameLength))
        let baseLevel = min(1.0, rms * 100)

        if baseLevel < Self.silenceThreshold {
            // Smooth decay
            vDSP_vsmul(prevLevels, 1, [Self.smoothing], &prevLevels, 1, vDSP_Length(Self.numBars))
            onLevels(prevLevels)
            return
        }

        // Prepare FFT input (zero-pad or truncate to fftSize)
        var fftInput = [Float](repeating: 0, count: Self.fftSize)
        let copyCount = min(frameLength, Self.fftSize)
        fftInput.replaceSubrange(0..<copyCount, with: samples.prefix(copyCount))

        // Apply Hanning window
        vDSP_vmul(fftInput, 1, window, 1, &fftInput, 1, vDSP_Length(Self.fftSize))

        // Real FFT
        let halfN = Self.fftSize / 2
        var realp = [Float](repeating: 0, count: halfN)
        var imagp = [Float](repeating: 0, count: halfN)

        realp.withUnsafeMutableBufferPointer { realBuf in
            imagp.withUnsafeMutableBufferPointer { imagBuf in
                var splitComplex = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)

                fftInput.withUnsafeBufferPointer { inputBuf in
                    inputBuf.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfN) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(halfN))
                    }
                }

                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))

                // Magnitude
                var magnitudes = [Float](repeating: 0, count: halfN)
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfN))

                // Convert to dB, normalize
                var one: Float = 1e-10
                vDSP_vsadd(magnitudes, 1, &one, &magnitudes, 1, vDSP_Length(halfN))

                var logMags = [Float](repeating: 0, count: halfN)
                var count = Int32(halfN)
                vvlog10f(&logMags, magnitudes, &count)

                var twenty: Float = 20
                vDSP_vsmul(logMags, 1, &twenty, &logMags, 1, vDSP_Length(halfN))

                // Normalize: map -60dB..0dB to 0..1
                var addSixty: Float = 60
                vDSP_vsadd(logMags, 1, &addSixty, &logMags, 1, vDSP_Length(halfN))
                var divSixty: Float = 1.0 / 60.0
                vDSP_vsmul(logMags, 1, &divSixty, &logMags, 1, vDSP_Length(halfN))

                // Clamp 0..1
                var lo: Float = 0
                var hi: Float = 1
                vDSP_vclip(logMags, 1, &lo, &hi, &logMags, 1, vDSP_Length(halfN))

                // Map to exponential frequency bars
                let usableBins = halfN - Self.minFreqBin
                var levels = [Float](repeating: 0, count: Self.numBars)

                for i in 0..<Self.numBars {
                    let loIdx = Self.minFreqBin + Int(Float(usableBins) * pow(Float(i) / Float(Self.numBars), 2.5))
                    var hiIdx = Self.minFreqBin + Int(Float(usableBins) * pow(Float(i + 1) / Float(Self.numBars), 2.5))
                    hiIdx = max(hiIdx, loIdx + 1)
                    hiIdx = min(hiIdx, halfN)

                    let range = loIdx..<hiIdx
                    let avg = range.isEmpty ? Float(0) : logMags[range].reduce(0, +) / Float(range.count)

                    // Bass reduction
                    var adjusted = avg
                    if i < 4 {
                        adjusted *= 0.5 + Float(i) * 0.125
                    }
                    levels[i] = adjusted
                }

                // Temporal smoothing: 70% previous + 30% new
                var smoothed = [Float](repeating: 0, count: Self.numBars)
                var smoothFactor: Float = Self.smoothing
                var newFactor: Float = 1.0 - Self.smoothing
                vDSP_vsmul(self.prevLevels, 1, &smoothFactor, &smoothed, 1, vDSP_Length(Self.numBars))
                var newScaled = [Float](repeating: 0, count: Self.numBars)
                vDSP_vsmul(levels, 1, &newFactor, &newScaled, 1, vDSP_Length(Self.numBars))
                vDSP_vadd(smoothed, 1, newScaled, 1, &smoothed, 1, vDSP_Length(Self.numBars))

                self.prevLevels = smoothed
                onLevels(smoothed)
            }
        }
    }
}
