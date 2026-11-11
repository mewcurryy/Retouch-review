import Foundation

nonisolated struct EyeZoomFlow {
    enum Phase: Equatable { case idle, entering, active, releasing }

    struct Input {
        var poseLeft = false
        var poseRight = false
        var holdLeft = false
        var holdRight = false
        var gripLeft = false
        var gripRight = false
        var pointLeft = false
        var pointRight = false
        var activityLeft: EyeActivity = .idle
        var activityRight: EyeActivity = .idle
        var enterDwellFactor: TimeInterval = 1
        var handLost = false
    }

    var enterDwell = ZoomTuning.eyeFlowEnterDwell
    var gripDwell = ZoomTuning.gripEnterDwell
    var pointDwell = ZoomTuning.fingerPointDwell
    var switchDwell = ZoomTuning.eyeFlowSwitchDwell
    var releaseDwell = ZoomTuning.eyeFlowReleaseDwell
    var poseGrace = ZoomTuning.eyeFlowPoseGrace
    var softHoldCap = ZoomTuning.eyeSoftHoldCap

    private(set) var phase: Phase = .idle
    private(set) var side: EyeSide?
    private(set) var holdReason = "-"
    private var leftSince: Date?
    private var rightSince: Date?
    private var leftSeen: Date?
    private var rightSeen: Date?
    private var gripLeftSince: Date?
    private var gripRightSince: Date?
    private var gripLeftSeen: Date?
    private var gripRightSeen: Date?
    private var pointLeftSince: Date?
    private var pointRightSince: Date?
    private var pointLeftSeen: Date?
    private var pointRightSeen: Date?
    private var switchPending: (side: EyeSide, since: Date)?
    private var releaseSince: Date?
    private var softSince: Date?
    private var lostSince: Date?

    var isActive: Bool { phase == .active || phase == .releasing }

    var target: ZoomTarget? {
        guard isActive, let side else { return nil }
        return side == .left ? .leftEye : .rightEye
    }

    func releaseRemaining(now: Date) -> TimeInterval? {
        guard phase == .releasing, let since = releaseSince else { return nil }
        return max(releaseDwell - now.timeIntervalSince(since), 0)
    }

    private static func trackPose(_ present: Bool, since: Date?, seen: inout Date?,
                                  now: Date, grace: TimeInterval) -> Date? {
        if present {
            seen = now
            return since ?? now
        }
        if let last = seen, let since, now.timeIntervalSince(last) <= grace { return since }
        seen = nil
        return nil
    }

    @discardableResult
    mutating func update(_ input: Input, now: Date) -> ZoomTarget? {
        switch phase {
        case .idle, .entering:
            holdReason = "-"
            leftSince = Self.trackPose(input.poseLeft, since: leftSince, seen: &leftSeen,
                                       now: now, grace: poseGrace)
            rightSince = Self.trackPose(input.poseRight, since: rightSince, seen: &rightSeen,
                                        now: now, grace: poseGrace)
            gripLeftSince = Self.trackPose(input.gripLeft, since: gripLeftSince, seen: &gripLeftSeen,
                                           now: now, grace: poseGrace)
            gripRightSince = Self.trackPose(input.gripRight, since: gripRightSince, seen: &gripRightSeen,
                                            now: now, grace: poseGrace)
            pointLeftSince = Self.trackPose(input.pointLeft, since: pointLeftSince, seen: &pointLeftSeen,
                                            now: now, grace: poseGrace)
            pointRightSince = Self.trackPose(input.pointRight, since: pointRightSince, seen: &pointRightSeen,
                                             now: now, grace: poseGrace)
            let need = enterDwell * input.enterDwellFactor
            let pointNeed = pointDwell * input.enterDwellFactor
            let gripNeed = gripDwell * input.enterDwellFactor
            func due(_ since: Date?, _ need: TimeInterval) -> Date? {
                guard let s = since, now.timeIntervalSince(s) >= need else { return nil }
                return s
            }
            let dueL = [due(leftSince, need), due(gripLeftSince, gripNeed), due(pointLeftSince, pointNeed)].compactMap { $0 }.min()
            let dueR = [due(rightSince, need), due(gripRightSince, gripNeed), due(pointRightSince, pointNeed)].compactMap { $0 }.min()
            if dueL != nil || dueR != nil {
                if let l = dueL, let r = dueR {
                    side = l <= r ? .left : .right
                } else {
                    side = dueL != nil ? .left : .right
                }
                begin()
            } else {
                phase = (leftSince != nil || rightSince != nil || gripLeftSince != nil || gripRightSince != nil
                         || pointLeftSince != nil || pointRightSince != nil)
                    ? .entering : .idle
            }

        case .active, .releasing:
            guard let current = side else {
                goIdle()
                break
            }
            clearTimers()
            let other: EyeSide = current == .left ? .right : .left
            let poseHere = current == .left ? input.poseLeft : input.poseRight
            let poseThere = other == .left ? input.poseLeft : input.poseRight
            let gripHere = current == .left ? input.gripLeft : input.gripRight
            let gripThere = other == .left ? input.gripLeft : input.gripRight
            let pointHere = current == .left ? input.pointLeft : input.pointRight
            let pointThere = other == .left ? input.pointLeft : input.pointRight

            if (poseThere || gripThere || pointThere) && !(poseHere || gripHere || pointHere) {
                if switchPending?.side != other { switchPending = (other, now) }
                let switchNeed = poseThere ? switchDwell : (gripThere ? gripDwell : pointDwell)
                if let p = switchPending, now.timeIntervalSince(p.since) >= switchNeed {
                    side = other
                    switchPending = nil
                    releaseSince = nil
                    softSince = nil
                    phase = .active
                    return target
                }
            } else {
                switchPending = nil
            }

            let handHold = current == .left ? input.holdLeft : input.holdRight
            let activity = current == .left ? input.activityLeft : input.activityRight

            let soft = activity == .active || activity == .turning
            if handHold || !soft {
                softSince = nil
            } else if softSince == nil {
                softSince = now
            }
            let softOK = soft && (softHoldCap <= 0 || (softSince.map { now.timeIntervalSince($0) < softHoldCap } ?? true))

            let lostOK: Bool
            if input.handLost && !handHold {
                if lostSince == nil { lostSince = now }
                lostOK = now.timeIntervalSince(lostSince!) < ZoomTuning.handLostHoldCap
            } else {
                lostSince = nil
                lostOK = false
            }

            let holding = handHold || softOK || activity == .unknown || lostOK
            if handHold {
                holdReason = "jari"
            } else if softOK {
                holdReason = activity == .turning ? "menoleh" : "mata aktif"
            } else if activity == .unknown {
                holdReason = "data hilang"
            } else if lostOK {
                holdReason = "tangan hilang"
            } else {
                holdReason = "-"
            }

            if holding {
                releaseSince = nil
                phase = .active
            } else {
                if releaseSince == nil { releaseSince = now }
                phase = .releasing
                if let since = releaseSince, now.timeIntervalSince(since) >= releaseDwell {
                    goIdle()
                }
            }
        }
        return target
    }

    mutating func cancel() { goIdle() }

    private mutating func clearTimers() {
        leftSince = nil
        rightSince = nil
        leftSeen = nil
        rightSeen = nil
        gripLeftSince = nil
        gripRightSince = nil
        gripLeftSeen = nil
        gripRightSeen = nil
        pointLeftSince = nil
        pointRightSince = nil
        pointLeftSeen = nil
        pointRightSeen = nil
    }

    private mutating func begin() {
        phase = .active
        clearTimers()
        switchPending = nil
        releaseSince = nil
        softSince = nil
    }

    private mutating func goIdle() {
        phase = .idle
        side = nil
        holdReason = "-"
        clearTimers()
        switchPending = nil
        releaseSince = nil
        softSince = nil
    }
}
