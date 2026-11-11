import Foundation

nonisolated enum EyeActivity { case active, idle, unknown, turning }

nonisolated struct EyeActivityRecognizer {
    var enter = ZoomTuning.eyeActivityEnter
    var exit = ZoomTuning.eyeActivityExit
    var sustain = ZoomTuning.eyeActivitySustain
    var clear = ZoomTuning.eyeActivityClear
    var tau = ZoomTuning.eyeActivityTau
    var baselineTau = ZoomTuning.eyeBaselineTau
    var maxYaw = ZoomTuning.eyeActivityMaxYaw
    var learnMaxYaw = ZoomTuning.eyeLearnMaxYaw
    var unknownCap = ZoomTuning.eyeUnknownCap

    private struct Side {
        var baseline: Double?
        var smoothed: Double?
        var pendingSince: Date?
        var clearSince: Date?
        var active = false
    }
    private var left = Side()
    private var right = Side()
    private var lastTime: Date?
    private var lostSince: Date?
    private(set) var leftState: EyeActivity = .idle
    private(set) var rightState: EyeActivity = .idle

    func state(_ side: EyeSide) -> EyeActivity { side == .left ? leftState : rightState }

    mutating func update(face: FaceObservation?, learn: Bool, ignore: Bool, now: Date) {
        if let face, !ignore, isTurned(face) {
            lostSince = nil
            lastTime = nil
            left.pendingSince = nil
            right.pendingSince = nil
            left.smoothed = nil
            right.smoothed = nil
            leftState = .turning
            rightState = .turning
            return
        }
        guard let face, !ignore,
              face.leftEyeOpen.isFinite, face.rightEyeOpen.isFinite,
              !(face.yaw.isFinite && abs(face.yaw) > maxYaw) else {
            markLost(now: now)
            return
        }
        lostSince = nil
        let dt = min(max(lastTime.map { now.timeIntervalSince($0) } ?? ZoomTuning.nominalStep, 0.001),
                     ZoomTuning.maxStep)
        lastTime = now
        let frontal = face.yaw.isFinite && abs(face.yaw) < learnMaxYaw
        let canLearn = learn && frontal
        step(&left, raw: face.leftEyeOpen, learn: canLearn, dt: dt, now: now)
        step(&right, raw: face.rightEyeOpen, learn: canLearn, dt: dt, now: now)
        leftState = left.active ? .active : .idle
        rightState = right.active ? .active : .idle
    }

    private func isTurned(_ f: FaceObservation) -> Bool {
        if f.visibleEyes < 2 { return true }
        if f.yaw.isFinite && abs(f.yaw) > maxYaw { return true }
        return f.eyeWidthRatio.isFinite && f.eyeWidthRatio < ZoomTuning.eyeTurnWidthRatio
    }

    private func step(_ s: inout Side, raw: Double, learn: Bool, dt: TimeInterval, now: Date) {
        let value = (s.smoothed ?? raw) + (1 - exp(-dt / tau)) * (raw - (s.smoothed ?? raw))
        s.smoothed = value
        guard let base = s.baseline else {
            if learn { s.baseline = value }
            return
        }
        let dev = abs(value - base) / max(base, 0.05)

        if s.active {
            if dev < exit {
                if s.clearSince == nil { s.clearSince = now }
                if let c = s.clearSince, now.timeIntervalSince(c) >= clear {
                    s.active = false
                    s.clearSince = nil
                }
            } else {
                s.clearSince = nil
            }
        } else if dev >= enter {
            if s.pendingSince == nil { s.pendingSince = now }
            if let p = s.pendingSince, now.timeIntervalSince(p) >= sustain {
                s.active = true
                s.pendingSince = nil
            }
        } else {
            s.pendingSince = nil
        }

        if learn, !s.active, s.pendingSince == nil, dev < exit {
            let k = 1 - exp(-dt / baselineTau)
            s.baseline = base + (value - base) * k
        }
    }

    private mutating func markLost(now: Date) {
        if lostSince == nil { lostSince = now }
        lastTime = nil
        left.pendingSince = nil
        right.pendingSince = nil
        left.smoothed = nil
        right.smoothed = nil
        if let since = lostSince, now.timeIntervalSince(since) >= unknownCap {
            left.active = false
            right.active = false
            left.clearSince = nil
            right.clearSince = nil
            leftState = .idle
            rightState = .idle
        } else {
            leftState = .unknown
            rightState = .unknown
        }
    }
}
