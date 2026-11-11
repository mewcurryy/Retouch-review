import CoreGraphics

nonisolated struct ZoomReadiness {
    let hands: [TrackedHand]
    let scan: HandScan
    let converter: CoordinateConverter
    let handProfile: HandProfile
    let maxIntentSpeed: CGFloat
    let noseActive: Bool

    private var activeHands: [TrackedHand] { hands.filter { $0.hasPose || $0.holding } }

    func lips(points: FacePoints, support: Bool) -> LipsZoomFlow.Input {
        var input = LipsZoomFlow.Input()
        input.handLost = scan.handsSeen == 0 && hands.isEmpty
        let W = points.width
        guard W > 0, let lips = points.lips else { return input }
        let eyes = [points.leftEye, points.rightEye].compactMap { $0 }
        let zones = EyeZones(points: points)
        func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
        func ownedByLips(_ p: CGPoint) -> Bool {
            if let zones { return zones.isLipsSide(p) }
            return dist(p, lips) < (eyes.map { dist(p, $0) }.min() ?? .infinity)
        }
        func holdOwnedByLips(_ p: CGPoint) -> Bool {
            if let zones { return zones.isLipsHoldSide(p) }
            return ownedByLips(p)
        }

        let axisU = zones?.axisU ?? CGPoint(x: 1, y: 0)
        let axisV = zones?.axisV ?? CGPoint(x: 0, y: 1)
        func inOval(_ p: CGPoint, rx: CGFloat, ry: CGFloat) -> Bool {
            let dx = p.x - lips.x, dy = p.y - lips.y
            let a = (dx * axisU.x + dy * axisU.y) / W
            let b = (dx * axisV.x + dy * axisV.y) / W
            return hypot(a / rx, b / ry) < 1
        }

        let base = CGFloat(ZoomTuning.handEnterDistance)
        let holdRx = base * ZoomTuning.lipsTriggerStretchX * ZoomTuning.lipsHoldScale
        let holdRy = base * ZoomTuning.lipsTriggerStretchY * ZoomTuning.lipsHoldScale
        let tips = scan.fingertips.map { converter.toView($0) } + activeHands.map { $0.point }
        input.fingerNear = tips.contains { holdOwnedByLips($0) && inOval($0, rx: holdRx, ry: holdRy) }

        var limit = CGFloat(handProfile.enterDistance)
        if support { limit *= ZoomTuning.pitchLipsReach }
        let rx = limit * ZoomTuning.lipsTriggerStretchX
        let ry = limit * ZoomTuning.lipsTriggerStretchY
        for h in hands where (h.hasPose || h.holding) && h.speed < maxIntentSpeed {
            guard ownedByLips(h.point) else { continue }
            for p in h.checkPoints where inOval(p, rx: rx, ry: ry) {
                if h.pose2 { input.pose2Ready = true }
                if h.pose3 { input.pose3Ready = true }
                if h.holding { input.gripReady = true }
                break
            }
        }
        if ZoomTuning.fingerPointEnabled {
            for h in hands where h.isPoint && h.speed < maxIntentSpeed {
                if ownedByLips(h.point), inOval(h.point, rx: rx, ry: ry) { input.pointReady = true }
            }
        }
        return input
    }

    private func noseClaims(_ h: TrackedHand, _ zones: NoseZones) -> Bool {
        if noseActive {
            return zones.holds(h.point) || h.checkPoints.contains { zones.holds($0) }
        }
        return zones.owns(h.point) && h.checkPoints.contains { zones.inTrigger($0) }
    }

    func nose(points: FacePoints) -> NoseZoomFlow.Input {
        var input = NoseZoomFlow.Input()
        input.handLost = scan.handsSeen == 0 && hands.isEmpty
        guard var zones = NoseZones(points: points) else { return input }
        zones.triggerScale = min(CGFloat(handProfile.enterDistance / ZoomTuning.handEnterDistance), 1.1)

        for h in hands where (h.hasPose || h.holding) && h.speed < maxIntentSpeed {
            guard zones.owns(h.point) else { continue }
            for p in h.checkPoints where zones.inTrigger(p) {
                if h.pose2 { input.pose2Ready = true }
                if h.pose3 { input.pose3Ready = true }
                if h.holding { input.gripReady = true }
                break
            }
        }

        if ZoomTuning.fingerPointEnabled {
            for h in hands where h.isPoint && h.speed < maxIntentSpeed {
                if zones.owns(h.point), zones.inTrigger(h.point) { input.pointReady = true }
            }
        }

        var tips = scan.fingertips.map { converter.toView($0) }
        tips += activeHands.flatMap { $0.checkPoints }
        input.fingerNear = tips.contains { zones.holds($0) }
        return input
    }

    func eye(points: FacePoints, support: Bool) -> EyeZoomFlow.Input {
        var input = EyeZoomFlow.Input()
        input.handLost = scan.handsSeen == 0 && hands.isEmpty
        let W = points.width
        guard W > 0, var zones = EyeZones(points: points) else { return input }
        zones.triggerScale = min(CGFloat(handProfile.enterDistance / ZoomTuning.handEnterDistance), 1.1)
        var noseZones = NoseZones(points: points)
        noseZones?.triggerScale = zones.triggerScale
        if support { input.enterDwellFactor = ZoomTuning.pitchEyeDwellFactor }

        for h in hands where (h.hasPose || h.holding) && h.speed < maxIntentSpeed {

            if let noseZones, noseClaims(h, noseZones) { continue }
            if h.hasPose {
                for p in h.checkPoints {
                    guard let side = zones.triggerEye(at: p, owner: h.point) else { continue }
                    if side == .left { input.poseLeft = true } else { input.poseRight = true }
                    break
                }
            }
            if h.holding {
                for p in h.checkPoints {
                    guard let side = zones.gripTriggerEye(at: p, owner: h.point) else { continue }
                    if side == .left { input.gripLeft = true } else { input.gripRight = true }
                    break
                }
            }
        }

        if ZoomTuning.fingerPointEnabled {
            for h in hands where h.isPoint && h.speed < maxIntentSpeed {
                if let noseZones, noseClaims(h, noseZones) { continue }
                guard let side = zones.triggerEye(at: h.point, owner: h.point) else { continue }
                if side == .left { input.pointLeft = true } else { input.pointRight = true }
            }
        }

        let tips = (ZoomTuning.eyeHoldUsesAllFingertips ? scan.fingertips.map { converter.toView($0) } : [])
            + activeHands.map { $0.point }
        for p in tips {
            if zones.holds(.left, at: p) { input.holdLeft = true }
            if zones.holds(.right, at: p) { input.holdRight = true }
        }
        return input
    }
}
