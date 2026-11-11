import Foundation

nonisolated struct ZoomGestureResolver {
    var exitHold: TimeInterval = ZoomTuning.exitHold
    var switchDwell: TimeInterval = ZoomTuning.resolverSwitchDwell
    var handCooldown: TimeInterval = 0.5
    var exitCooldown: TimeInterval = 1.0
    var coverHold: TimeInterval = ZoomTuning.coverHold

    private(set) var target: ZoomTarget = .fullFace
    private(set) var headLocked = false
    private var straightSince: Date?
    private var lastActive = Date.distantPast
    private var lastHandSeen = Date.distantPast
    private var lastExit = Date.distantPast
    private var pending: (target: ZoomTarget, since: Date)?

    init(exitHold: TimeInterval = ZoomTuning.exitHold) { self.exitHold = exitHold }

    mutating func resolve(hand: ZoomTarget?, lips: Bool, nose: Bool = false, head: ZoomTarget?, covering: Bool, headStraight: Bool, headQuickRelease: Bool = false, now: Date) -> ZoomTarget
    {
        let handCandidate: ZoomTarget? = nose ? .nose : (hand ?? (lips ? .lips : nil))
        if handCandidate != nil { lastHandSeen = now }
        let handDriven = Self.isHandTarget(target)
        updateHeadLock(handActive: handCandidate != nil || handDriven, head: head,
                       headStraight: headStraight, now: now)

        let settle = handDriven ? exitHold : handCooldown
        let headAllowed = now.timeIntervalSince(lastHandSeen) >= settle
            && now.timeIntervalSince(lastExit) >= exitCooldown
            && !(covering && handDriven)
            && !headLocked

        guard let candidate = handCandidate ?? (headAllowed ? head : nil) else {
            pending = nil
            if Self.isHandTarget(target) {
                zoomOut(at: now)
                return target
            }
            if headQuickRelease, case .faceSide = target {
                target = .fullFace
                pending = nil
                return target
            }
            var hold = covering ? max(exitHold, coverHold) : exitHold
            if case .faceSide = target, !covering { hold = ZoomTuning.sideResolverExitHold }
            if target != .fullFace, now.timeIntervalSince(lastActive) >= hold {
                zoomOut(at: now)
            }
            return target
        }

        lastActive = now
        if candidate == target {
            pending = nil
            return target
        }
        if pending?.target != candidate { pending = (candidate, now) }

        let dwell: TimeInterval = (Self.isHandTarget(candidate) || target == .fullFace) ? 0 : switchDwell
        if let p = pending, now.timeIntervalSince(p.since) >= dwell {
            target = candidate
            pending = nil
        }
        return target
    }

    private mutating func updateHeadLock(handActive: Bool, head: ZoomTarget?, headStraight: Bool, now: Date) {
        guard ZoomTuning.headRearmEnabled else {
            headLocked = false
            return
        }
        if handActive {
            headLocked = true
            straightSince = nil
            return
        }
        guard headLocked else { return }
        if headStraight, head == nil {
            if straightSince == nil { straightSince = now }
            if let since = straightSince, now.timeIntervalSince(since) >= ZoomTuning.headRearmStraight {
                headLocked = false
                straightSince = nil
            }
        } else {
            straightSince = nil
        }
    }

    private mutating func zoomOut(at now: Date) {
        target = .fullFace
        lastExit = now
        pending = nil
    }

    private static func isEye(_ t: ZoomTarget) -> Bool { t == .leftEye || t == .rightEye }
    private static func isHandTarget(_ t: ZoomTarget) -> Bool { isEye(t) || t == .lips || t == .nose }

    func idleTime(now: Date) -> TimeInterval {
        target == .fullFace ? 0 : now.timeIntervalSince(lastActive)
    }
}
