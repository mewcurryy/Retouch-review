import Foundation

nonisolated struct DistanceCompensator {
    private var filter: OneEuroFilter = {
        var f = OneEuroFilter()
        f.minCutoff = ZoomTuning.distFilterMinCutoff
        f.beta = ZoomTuning.distFilterBeta
        return f
    }()
    private var smoothed: Double?
    private var reference: Double?
    private(set) var factor: CGFloat = 1

    private var usesBaseline: Bool { ZoomTuning.distBaselineSpan > 0 }

    mutating func clearReference() {
        reference = nil
        if !usesBaseline { factor = 1 }
    }

    mutating func latchReferenceIfNeeded() {
        guard !usesBaseline, reference == nil, let s = smoothed else { return }
        reference = s
        factor = 1
    }

    mutating func update(span: Double, yawDegrees: Double, valid: Bool, now: Double) {
        guard valid, span > 0, yawDegrees.isFinite, abs(yawDegrees) < ZoomTuning.distMaxYaw else { return }
        let c = max(cos(yawDegrees * .pi / 180), 0.5)
        let s = filter.filter(log(span / c), t: now)
        smoothed = s

        let ref: Double
        if usesBaseline {
            ref = log(ZoomTuning.distBaselineSpan)
        } else if let r = reference {
            ref = r
        } else {
            return
        }

        let raw = exp(ZoomTuning.distGamma * (ref - s))
        let clamped = min(max(raw, ZoomTuning.distMinFactor), ZoomTuning.distMaxFactor)
        if abs(clamped / Double(factor) - 1) > ZoomTuning.distDeadBand {
            factor = CGFloat(clamped)
        }
    }
}
