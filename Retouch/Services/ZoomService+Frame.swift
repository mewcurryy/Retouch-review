import CoreGraphics
import Foundation

nonisolated extension ZoomService {
    func update(faceSnap: DetectionSnapshot<FaceObservation?>?,
                        handSnap: DetectionSnapshot<HandScan>?,
                        imageSize: CGSize) {
        guard viewSize.width > 0, viewSize.height > 0 else { return }
        let converter = CoordinateConverter(imageSize: imageSize, viewSize: viewSize)

        let now = max(max(faceSnap?.timestamp ?? .distantPast, handSnap?.timestamp ?? .distantPast),
                      lastLogicTime)
        lastLogicTime = now

        guard isGestureEnabled else {
            guard let faceSnap else { return }
            lastFace = faceSnap.value
            let points = faceTracker.update(face: lastFace, covering: false, converter: converter,
                                            now: faceSnap.timestamp)
            trackMotion(face: lastFace, hand: nil, at: faceSnap.timestamp)
            distComp.update(span: Double(points.scale / viewSize.width),
                            yawDegrees: Double(lastFace?.yaw ?? .nan),
                            valid: lastFace != nil,
                            now: faceSnap.timestamp.timeIntervalSinceReferenceDate)
            publish(manualTarget)
            onTracking?(ZoomTracking(target: manualTarget, face: points, viewSize: viewSize))
            return
        }

        let H = viewSize.height

        if let handSnap {
            lastScan = handSnap.value
            if ZoomTuning.handSeenBoostsRate, lastScan.handsSeen > 0 {
                pacer.noteMotion(at: handSnap.timestamp)
            }
            let candidates = lastScan.grips.map {
                HandTrackBank.Candidate(tip: converter.toView($0.tip), pose2: $0.twoFinger, pose3: $0.threeFinger,
                                        finger: converter.toView($0.grip), holding: $0.holding,
                                        mode: $0.mode, base: $0.base.map { converter.toView($0) }, kept: $0.kept)
            }
            let pointCandidates = lastScan.points.map {
                HandTrackBank.Candidate(tip: converter.toView($0.point), pose2: false, pose3: false,
                                        mode: $0.mode, isPoint: true)
            }
            hands = handBank.update(candidates + pointCandidates, faceWidth: faceTracker.points.width, viewHeight: H, now: handSnap.timestamp)
            lastHand = nearestHandPoint(faceTracker.points)
        }
        let covering = isCovering(points: faceTracker.points)

        var points = faceTracker.points
        if let faceSnap {
            lastFace = faceSnap.value
            points = faceTracker.update(face: lastFace, covering: covering, converter: converter, now: faceSnap.timestamp)
        }

        if handSnap != nil {
            let support = ZoomTuning.pitchEnabled && ZoomTuning.pitchHandSupportEnabled && pitchRecognizer.isLifted
            let readiness = ZoomReadiness(hands: hands, scan: lastScan, converter: converter,
                                          handProfile: handProfile, maxIntentSpeed: handBank.maxIntentSpeed,
                                          noseActive: noseFlow.isActive)
            eyeInput = readiness.eye(points: points, support: support)
            lipsInput = readiness.lips(points: points, support: support)
            noseInput = readiness.nose(points: points)
        }

        if let faceSnap {
            let learn = !eyeFlow.isActive && !lipFlow.isActive && !noseFlow.isActive
            let faceForHead = covering ? nil : faceSnap.value
            pitchRecognizer.update(face: faceForHead, learn: learn, covered: covering, now: faceSnap.timestamp)
            let freeze = ZoomTuning.pitchEnabled && ZoomTuning.pitchYawFreezeEnabled
                && pitchRecognizer.isFrozen(now: faceSnap.timestamp)
            headTarget = headPose.update(face: faceForHead, learn: learn && !freeze, covered: covering,yawFrozen: freeze, now: faceSnap.timestamp)
            distComp.update(span: Double(points.scale / viewSize.width),
                            yawDegrees: Double(faceForHead?.yaw ?? .nan),
                            valid: !covering && !freeze,
                            now: faceSnap.timestamp.timeIntervalSinceReferenceDate)
            lipMotion.update(face: faceForHead, ignore: freeze, now: faceSnap.timestamp)
            eyeActivity.update(face: faceForHead, learn: learn && !covering, ignore: freeze,
                               now: faceSnap.timestamp)
        }
        trackMotion(face: faceSnap != nil ? lastFace : nil, hand: lastHand, at: now,
                    faceChecked: faceSnap != nil)

        let lipsShowing = lipFlow.phase == .active
        let eyeShowing = eyeFlow.phase == .active
        var eyeIn = eyeInput
        eyeIn.activityLeft = eyeActivity.leftState
        eyeIn.activityRight = eyeActivity.rightState
        if lipsShowing { eyeIn.enterDwellFactor *= Self.preemptDwellFactor }
        eyeFlow.update(eyeIn, now: now)
        var lipIn = lipsInput
        lipIn.lipsMoving = lipMotion.isMoving
        lipFlow.update(lipIn, now: now)
        var noseIn = noseInput
        if eyeShowing || lipsShowing { noseIn.enterDwellFactor = Self.preemptDwellFactor }
        noseFlow.update(noseIn, now: now)

        let ranked: [(owner: FlowOwner, running: Bool, holding: Bool)] = [
            (.nose, noseFlow.isActive, noseFlow.phase == .active),
            (.eye, eyeFlow.isActive, eyeFlow.phase == .active),
            (.lips, lipFlow.isActive, lipFlow.phase == .active)
        ]
        let winner: FlowOwner? = ranked.first(where: { $0.holding })?.owner
            ?? ranked.first(where: { $0.running })?.owner
        if winner != .nose, noseFlow.phase == .releasing { noseFlow.cancel() }
        if winner != .eye, eyeFlow.phase == .releasing { eyeFlow.cancel() }
        if winner != .lips, lipFlow.phase == .releasing { lipFlow.cancel() }
        handTarget = winner == .eye ? eyeFlow.target : nil

        let target = resolver.resolve(hand: handTarget, lips: winner == .lips, nose: winner == .nose, head: headTarget, covering: covering, headStraight: headPose.isStraight, headQuickRelease: headPose.quickReleased, now: now)

        if target == .fullFace { distComp.clearReference() } else { distComp.latchReferenceIfNeeded() }

        let handDriven = target == .leftEye || target == .rightEye || target == .lips || target == .nose
        if handDriven, autoZoomSince == nil { autoZoomSince = now }
        if !handDriven, autoZoomSince != nil {
            autoZoomSince = nil
            lastAutoZoomEnd = now
        }

        var isSide = false
        if case .faceSide = target { isSide = true }
        if isSide, sideZoomSince == nil {
            sideZoomSince = now
            lastSideZoomStart = now
        }
        if !isSide, sideZoomSince != nil {
            sideZoomSince = nil
            lastSideZoomEnd = now
        }

        saveProfileIfNeeded(now: now)

        publish(target)

        onTracking?(ZoomTracking(target: target, face: points, viewSize: viewSize))
    }

    func trackMotion(face: FaceObservation?, hand: CGPoint?, at now: Date, faceChecked: Bool = true) {
        if hand != nil { pacer.noteMotion(at: now) }
        guard faceChecked else { return }
        guard let f = face else {
            prevFace = nil
            return
        }
        if let p = prevFace {
            let dt = max(now.timeIntervalSince(prevFaceTime), 0.001)
            let move = hypot(f.center.x - p.center.x, f.center.y - p.center.y) / max(f.width, 0.01) / dt
            let yawMove = (f.yaw.isFinite && p.yaw.isFinite) ? abs(f.yaw - p.yaw) / dt : 0
            if move > ZoomTuning.idleFaceSpeed || yawMove > ZoomTuning.idleYawRate {
                pacer.noteMotion(at: now)
            }
        }
        prevFace = f
        prevFaceTime = now
    }

    func isCovering(points: FacePoints) -> Bool {
        let W = points.width
        guard W > 0 else { return false }
        let anchors = points.handTargets.map { $0.1 }
        let near = activeHands.contains { h in
            anchors.contains { hypot(h.point.x - $0.x, h.point.y - $0.y) / W < ZoomTuning.coverDistance }
        }
        return near || (lipFlow.isActive && lipsInput.fingerNear) || (noseFlow.isActive && noseInput.fingerNear)
    }

    func nearestHandPoint(_ points: FacePoints) -> CGPoint? {
        let anchors = points.handTargets.map { $0.1 }
        guard !anchors.isEmpty else { return hands.first?.point }
        func nearest(_ h: TrackedHand) -> CGFloat {
            anchors.map { hypot(h.point.x - $0.x, h.point.y - $0.y) }.min() ?? .infinity
        }
        return hands.min { nearest($0) < nearest($1) }?.point
    }

    func publish(_ target: ZoomTarget) {
        if pinchScale > 1.01 {
            send(scale: pinchScale, focus: .pinch)
            return
        }
        guard let focus = focusPoint(for: target, faceTracker.points) else {
            send(scale: 1, focus: .center)
            return
        }
        let factor = target != .fullFace ? distComp.factor : 1
        let finalScale = max(1, min(target.zoomScale * factor, ZoomTuning.distMaxScale))
        send(scale: finalScale, focus: .target(target, focus, manual: !isGestureEnabled))
    }

    func focusPoint(for target: ZoomTarget, _ p: FacePoints) -> CGPoint? {
        switch target {
        case .fullFace: return nil
        case .leftEye: return p.leftEye
        case .rightEye: return p.rightEye
        case .lips: return p.lips
        case .nose: return p.nose
        case .faceSide(let side): return sideFocus(side, p)
        }
    }

    func sideFocus(_ side: FaceSide, _ p: FacePoints) -> CGPoint? {
        guard let c = p.center else { return nil }
        let k = ZoomTuning.sideFocusStrength
        guard let eye = side == .left ? p.leftEye : p.rightEye else {
            let dx = p.width * 0.08 * k
            return CGPoint(x: side == .left ? c.x - dx : c.x + dx, y: c.y)
        }
        var focus = CGPoint(x: c.x + (eye.x - c.x) * k, y: c.y + (eye.y - c.y) * k)

        if let l = p.leftEye, let r = p.rightEye {
            let len = hypot(r.x - l.x, r.y - l.y)
            if len > 0 {
                let ux = (r.x - l.x) / len, uy = (r.y - l.y) / len
                let sign: CGFloat = side == .left ? -1 : 1
                let out = p.scale * ZoomTuning.sideFocusOutward
                focus.x += sign * ux * out
                focus.y += sign * uy * out
                let drop = p.scale * ZoomTuning.sideFocusDrop
                focus.x += -uy * drop
                focus.y += ux * drop
            }
        }
        return focus
    }

    func send(scale: CGFloat, focus: ZoomAnimator.Focus) {
        DispatchQueue.main.async { [animator] in animator.setGoal(scale: scale, focus: focus) }
    }
}
