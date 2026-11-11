import Foundation
import CoreImage
import Vision

nonisolated struct DetectionSnapshot<Value> {
    let value: Value
    let sequence: Int
    let timestamp: Date
}

nonisolated struct RateGate {
    private var nextDue: TimeInterval = 0

    mutating func allow(now: TimeInterval, interval: TimeInterval) -> Bool {
        guard interval > 0 else { return true }
        if now < nextDue - 0.004 { return false }
        let next = nextDue + interval
        nextDue = next > now ? next : now + interval
        return true
    }
}

nonisolated struct DetectionPacer {
    private var lastMotion = Date()
    private var baseRate = ZoomTuning.detectionRate
    private var lastEnvCheck = Date.distantPast

    mutating func noteMotion(at now: Date) { lastMotion = now }

    mutating func interval(now: Date) -> TimeInterval {
        if now.timeIntervalSince(lastEnvCheck) >= ZoomTuning.envCheckInterval {
            lastEnvCheck = now
            let info = ProcessInfo.processInfo
            switch info.thermalState {
            case .nominal: baseRate = ZoomTuning.detectionRate
            case .fair: baseRate = ZoomTuning.fairRate
            default: baseRate = ZoomTuning.seriousRate
            }
            if info.isLowPowerModeEnabled { baseRate = min(baseRate, ZoomTuning.seriousRate) }
        }
        var rate = baseRate
        if now.timeIntervalSince(lastMotion) >= ZoomTuning.idleAfter {
            rate = min(rate, ZoomTuning.idleRate)
        }
        return 1 / rate
    }
}

nonisolated enum AnalysisImage {
    static func handler(for pixelBuffer: CVPixelBuffer, enhancer: LowLightEnhancer? = nil) -> VNImageRequestHandler {
        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let target = ZoomTuning.analysisWidth
        let needsScale = ZoomTuning.downscaleEnabled && width > target * 1.2
        guard needsScale || enhancer != nil else {
            return VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .leftMirrored)
        }
        var image = CIImage(cvPixelBuffer: pixelBuffer)
        if needsScale {
            image = image.applyingFilter(
                "CILanczosScaleTransform",
                parameters: [kCIInputScaleKey: target / width, kCIInputAspectRatioKey: 1.0]
            )
        }
        if let enhancer { image = enhancer.enhance(image) }
        return VNImageRequestHandler(ciImage: image, orientation: .leftMirrored)
    }
}
