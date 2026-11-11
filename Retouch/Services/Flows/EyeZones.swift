import CoreGraphics

nonisolated enum EyeSide { case left, right }

nonisolated struct EyeZones {
    private let leftEye: CGPoint
    private let rightEye: CGPoint
    private let mid: CGPoint
    private let u: CGPoint
    private let v: CGPoint
    private let d: CGFloat
    private let lineT: CGFloat?

    var triggerScale: CGFloat = 1

    init?(points: FacePoints) {
        guard let l = points.leftEye, let r = points.rightEye, points.scale > 0 else { return nil }
        let len = hypot(r.x - l.x, r.y - l.y)
        guard len > 0 else { return nil }
        leftEye = l
        rightEye = r
        d = points.scale
        mid = CGPoint(x: (l.x + r.x) / 2, y: (l.y + r.y) / 2)
        u = CGPoint(x: (r.x - l.x) / len, y: (r.y - l.y) / len)
        v = CGPoint(x: -u.y, y: u.x)
        let m = mid, vv = v, scale = points.scale
        func along(_ p: CGPoint) -> CGFloat { ((p.x - m.x) * vv.x + (p.y - m.y) * vv.y) / scale }
        var line: CGFloat?
        if let top = points.lipsTop {
            line = along(top) + ZoomTuning.lipsLineOffset
        } else if let lips = points.lips {
            line = along(lips) * 0.5
        }
        if let lv = line, lv > 0 { lineT = lv } else { lineT = nil }
    }

    func s(_ p: CGPoint) -> CGFloat { ((p.x - mid.x) * u.x + (p.y - mid.y) * u.y) / d }

    func t(_ p: CGPoint) -> CGFloat { ((p.x - mid.x) * v.x + (p.y - mid.y) * v.y) / d }

    func isLipsSide(_ p: CGPoint) -> Bool {
        guard let lt = lineT else { return false }
        return t(p) > lt
    }

    func isLipsHoldSide(_ p: CGPoint) -> Bool {
        guard let lt = lineT else { return false }
        return t(p) > lt - ZoomTuning.lipsHoldLineTolerance
    }

    func lineSegment(halfLength: CGFloat, shift: CGFloat = 0) -> (CGPoint, CGPoint)? {
        guard let lt = lineT else { return nil }
        let c = CGPoint(x: mid.x + v.x * (lt + shift) * d, y: mid.y + v.y * (lt + shift) * d)
        return (CGPoint(x: c.x - u.x * d * halfLength, y: c.y - u.y * d * halfLength),
                CGPoint(x: c.x + u.x * d * halfLength, y: c.y + u.y * d * halfLength))
    }

    private func eye(_ side: EyeSide) -> CGPoint { side == .left ? leftEye : rightEye }

    func distance(_ p: CGPoint, to side: EyeSide) -> CGFloat {
        let e = eye(side)
        return hypot(p.x - e.x, p.y - e.y) / d
    }

    private func zoneCenter(_ side: EyeSide) -> CGPoint {
        let e = eye(side)
        let sign: CGFloat = side == .left ? -1 : 1
        let shift = sign * ZoomTuning.eyeZoneOffsetX * d
        return CGPoint(x: e.x + u.x * shift, y: e.y + u.y * shift)
    }

    func triggerEye(at p: CGPoint, owner: CGPoint? = nil) -> EyeSide? {
        guard !isLipsSide(owner ?? p) else { return nil }
        let vl = triggerValue(p, to: .left), vr = triggerValue(p, to: .right)
        if vl <= 1, vl <= vr { return .left }
        if vr <= 1 { return .right }
        return nil
    }

    func holds(_ side: EyeSide, at p: CGPoint) -> Bool {
        guard !isLipsSide(p) else { return false }
        let e = eye(side)
        let dx = p.x - e.x, dy = p.y - e.y
        let a = (dx * u.x + dy * u.y) / d
        let b = (dx * v.x + dy * v.y) / d
        let rx = ZoomTuning.eyeTriggerRadiusX * ZoomTuning.eyeHoldScaleX
        let ry = ZoomTuning.eyeTriggerRadiusY * ZoomTuning.eyeHoldScaleY
        guard hypot(a / rx, b / ry) <= 1 else { return false }
        let x = s(p)
        let dead = ZoomTuning.eyeZoneDead
        return side == .left ? x <= dead : x >= -dead
    }

    func gripValue(_ p: CGPoint, to side: EyeSide) -> CGFloat {
        let e = eye(side)
        let dx = p.x - e.x, dy = p.y - e.y
        let a = (dx * u.x + dy * u.y) / d
        let b = (dx * v.x + dy * v.y) / d
        let outward = side == .left ? -a : a
        let sx = outward > 0 ? ZoomTuning.eyeGripScaleOuter : ZoomTuning.eyeGripScaleInner
        let rx = ZoomTuning.eyeTriggerRadiusX * triggerScale * sx
        let ry = ZoomTuning.eyeTriggerRadiusY * triggerScale * ZoomTuning.eyeGripScaleY
        return hypot(a / rx, b / ry)
    }

    func gripTriggerEye(at p: CGPoint, owner: CGPoint? = nil) -> EyeSide? {
        guard !isLipsSide(owner ?? p) else { return nil }
        let vl = gripValue(p, to: .left), vr = gripValue(p, to: .right)
        if vl <= 1, vl <= vr { return .left }
        if vr <= 1 { return .right }
        return nil
    }

    var axisU: CGPoint { u }
    var axisV: CGPoint { v }

    func triggerValue(_ p: CGPoint, to side: EyeSide) -> CGFloat {
        let e = eye(side)
        let dx = p.x - e.x, dy = p.y - e.y
        let a = (dx * u.x + dy * u.y) / d
        let b = (dx * v.x + dy * v.y) / d
        let rx = ZoomTuning.eyeTriggerRadiusX * triggerScale
        let ry = ZoomTuning.eyeTriggerRadiusY * triggerScale
        return hypot(a / rx, b / ry)
    }
}
