import Vision
import QuartzCore

nonisolated final class FaceLandmarkDetector: @unchecked Sendable {
    private let request = VNDetectFaceLandmarksRequest()
    private let queue = DispatchQueue(label: "zoom.face")
    private let noseGain = 0.55
    private let cheekGain = 0.6
    private let lock = NSLock()
    private var busy = false
    private var gate = RateGate()
    private var cache: FaceObservation?
    private var cacheTime = Date.distantPast
    private var sequence = 0

    var snapshot: DetectionSnapshot<FaceObservation?> {
        lock.lock()
        defer { lock.unlock() }
        return DetectionSnapshot(value: cache, sequence: sequence, timestamp: cacheTime)
    }

    var latest: FaceObservation? { snapshot.value }

    func reset() {
        lock.lock()
        cache = nil
        lock.unlock()
    }

    func submit(_ pixelBuffer: CVPixelBuffer, minInterval: TimeInterval = 0) {
        let mediaNow = CACurrentMediaTime()
        lock.lock()
        let skip = busy || !gate.allow(now: mediaNow, interval: minInterval)
        if !skip { busy = true }
        lock.unlock()
        guard !skip else { return }

        let stamp = Date()
        let aspect = CGFloat(CVPixelBufferGetHeight(pixelBuffer)) / CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        nonisolated(unsafe) let buffer = pixelBuffer
        queue.async { [self] in
            let handler = AnalysisImage.handler(for: buffer)
            try? handler.perform([request])
            let face = parse(aspect: aspect)
            lock.lock()
            cache = face
            cacheTime = stamp
            sequence += 1
            busy = false
            lock.unlock()
        }
    }

    private func parse(aspect: CGFloat) -> FaceObservation? {
        guard let face = request.results?.max(by: { $0.boundingBox.height < $1.boundingBox.height }),
              let lm = face.landmarks else { return nil }
        let box = face.boundingBox

        func point(_ p: CGPoint) -> CGPoint {
            CGPoint(x: box.minX + p.x * box.width, y: box.minY + p.y * box.height)
        }
        func center(_ region: VNFaceLandmarkRegion2D?) -> CGPoint? {
            guard let pts = region?.normalizedPoints, !pts.isEmpty else { return nil }
            let sx = pts.reduce(0) { $0 + $1.x } / CGFloat(pts.count)
            let sy = pts.reduce(0) { $0 + $1.y } / CGFloat(pts.count)
            return point(CGPoint(x: sx, y: sy))
        }

        let eyes = [center(lm.leftEye), center(lm.rightEye)].compactMap { $0 }.sorted { $0.x < $1.x }
        var leftEye: CGPoint?
        var rightEye: CGPoint?
        if eyes.count == 2 {
            leftEye = eyes[0]
            rightEye = eyes[1]
        } else if let only = eyes.first {
            if only.x < box.midX { leftEye = only } else { rightEye = only }
        }

        var yaw = Double.nan
        if let l = leftEye, let r = rightEye {
            let contour = lm.faceContour?.normalizedPoints.map(point) ?? []
            yaw = estimateYaw(leftEye: l, rightEye: r, nose: center(lm.nose),
                              contour: contour, aspect: aspect)
        }

        var pitch = Double.nan
        if ZoomTuning.pitchEnabled, let l = leftEye, let r = rightEye,
           !(yaw.isFinite && abs(yaw) > ZoomTuning.pitchMaxYaw) {
            pitch = estimatePitch(leftEye: l, rightEye: r, nose: center(lm.nose),
                                  mouth: center(lm.outerLips), aspect: aspect)
        }

        var mouth: (width: Double, height: Double, gap: Double)?
        if let l = leftEye, let r = rightEye {
            mouth = estimateMouth(leftEye: l, rightEye: r,
                                  outer: lm.outerLips?.normalizedPoints.map(point) ?? [],
                                  inner: lm.innerLips?.normalizedPoints.map(point) ?? [],
                                  aspect: aspect)
        }

        var leftOpen = Double.nan
        var rightOpen = Double.nan
        var widthRatio = Double.nan
        let shapes = [lm.leftEye, lm.rightEye].compactMap { region -> (c: CGPoint, pts: [CGPoint])? in
            guard let pts = region?.normalizedPoints, pts.count >= 4, let c = center(region) else { return nil }
            return (c, pts.map(point))
        }.sorted { $0.c.x < $1.c.x }
        if shapes.count == 2, let r = estimateEyeOpen(shapes[0].pts, shapes[1].pts, aspect: aspect) {
            leftOpen = r.left
            rightOpen = r.right
            widthRatio = r.widthRatio
        }

        return FaceObservation(
            leftEye: leftEye,
            rightEye: rightEye,
            lips: center(lm.outerLips).map { CGPoint(x: $0.x, y: $0.y - box.height * 0.06) },
            center: CGPoint(x: box.midX, y: box.midY),
            width: box.width,
            yaw: yaw,
            aspect: Double(box.height / (box.width * aspect)),
            pitch: pitch,
            mouthWidth: mouth?.width ?? .nan,
            mouthHeight: mouth?.height ?? .nan,
            mouthGap: mouth?.gap ?? .nan,
            leftEyeOpen: leftOpen,
            rightEyeOpen: rightOpen,
            visibleEyes: eyes.count,
            eyeWidthRatio: widthRatio,
            lipsTop: estimateLipsTop(leftEye: leftEye, rightEye: rightEye,
                                     outer: lm.outerLips?.normalizedPoints.map(point) ?? [], aspect: aspect),
            nose: estimateNoseFocus(nose: center(lm.nose), crest: center(lm.noseCrest))
        )
    }

    private func estimateLipsTop(leftEye l: CGPoint?, rightEye r: CGPoint?,
                                 outer: [CGPoint], aspect: CGFloat) -> CGPoint? {
        guard outer.count >= 4 else { return nil }
        func iso(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * aspect, y: p.y) }
        if let l, let r {
            let le = iso(l), re = iso(r)
            let dist = hypot(re.x - le.x, re.y - le.y)
            if dist > 0 {
                let ux = (re.x - le.x) / dist, uy = (re.y - le.y) / dist
                let vx = uy, vy = -ux
                func down(_ p: CGPoint) -> CGFloat { iso(p).x * vx + iso(p).y * vy }
                return outer.min { down($0) < down($1) }
            }
        }
        return outer.max { $0.y < $1.y }
    }

    private func estimateNoseFocus(nose: CGPoint?, crest: CGPoint?) -> CGPoint? {
        switch (nose, crest) {
        case let (n?, c?): return CGPoint(x: (n.x + c.x) / 2, y: (n.y + c.y) / 2)
        case let (n?, nil): return n
        case let (nil, c?): return c
        default: return nil
        }
    }

    private func estimateMouth(leftEye l: CGPoint, rightEye r: CGPoint,
                               outer: [CGPoint], inner: [CGPoint],
                               aspect: CGFloat) -> (width: Double, height: Double, gap: Double)? {
        guard outer.count >= 4 else { return nil }
        func iso(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * aspect, y: p.y) }
        let le = iso(l), re = iso(r)
        let dist = hypot(re.x - le.x, re.y - le.y)
        guard dist > 0 else { return nil }
        let ux = (re.x - le.x) / dist, uy = (re.y - le.y) / dist
        let vx = uy, vy = -ux
        func span(_ pts: [CGPoint], _ ax: CGFloat, _ ay: CGFloat) -> Double {
            let vals = pts.map { iso($0).x * ax + iso($0).y * ay }
            guard let lo = vals.min(), let hi = vals.max() else { return 0 }
            return Double((hi - lo) / dist)
        }
        return (width: span(outer, ux, uy),
                height: span(outer, vx, vy),
                gap: inner.count >= 2 ? span(inner, vx, vy) : 0)
    }

    private func estimateEyeOpen(_ a: [CGPoint], _ b: [CGPoint], aspect: CGFloat)
        -> (left: Double, right: Double, widthRatio: Double)? {
        func iso(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * aspect, y: p.y) }
        func mean(_ pts: [CGPoint]) -> CGPoint {
            let q = pts.map(iso)
            return CGPoint(x: q.reduce(0) { $0 + $1.x } / CGFloat(q.count),
                           y: q.reduce(0) { $0 + $1.y } / CGFloat(q.count))
        }
        let ca = mean(a), cb = mean(b)
        let len = hypot(cb.x - ca.x, cb.y - ca.y)
        guard len > 0 else { return nil }
        let ux = (cb.x - ca.x) / len, uy = (cb.y - ca.y) / len
        let vx = uy, vy = -ux
        func shape(_ pts: [CGPoint]) -> (open: Double, width: Double)? {
            let q = pts.map(iso)
            let along = q.map { $0.x * ux + $0.y * uy }
            let across = q.map { $0.x * vx + $0.y * vy }
            guard let aMax = along.max(), let aMin = along.min(),
                  let cMax = across.max(), let cMin = across.min(), aMax - aMin > 0 else { return nil }
            return (Double((cMax - cMin) / (aMax - aMin)), Double(aMax - aMin))
        }
        guard let l = shape(a), let r = shape(b), max(l.width, r.width) > 0 else { return nil }
        return (l.open, r.open, min(l.width, r.width) / max(l.width, r.width))
    }

    private func estimatePitch(leftEye l: CGPoint, rightEye r: CGPoint, nose: CGPoint?,
                               mouth: CGPoint?, aspect: CGFloat) -> Double {
        guard let nose, let mouth else { return .nan }
        func iso(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * aspect, y: p.y) }
        let le = iso(l), re = iso(r)
        let dist = hypot(re.x - le.x, re.y - le.y)
        guard dist > 0 else { return .nan }
        let ux = (re.x - le.x) / dist, uy = (re.y - le.y) / dist
        let vx = uy, vy = -ux
        let mx = (le.x + re.x) / 2, my = (le.y + re.y) / 2
        func down(_ p: CGPoint) -> CGFloat {
            let q = iso(p)
            return (q.x - mx) * vx + (q.y - my) * vy
        }
        let noseDown = down(nose), mouthDown = down(mouth)
        guard mouthDown > dist * 0.4, noseDown > 0 else { return .nan }
        let ratio = Double(noseDown / mouthDown)
        return atan((ZoomTuning.pitchNominalRatio - ratio) / ZoomTuning.pitchNoseGain) * 180 / .pi
    }

    private func estimateYaw(leftEye l: CGPoint, rightEye r: CGPoint, nose: CGPoint?,
                             contour: [CGPoint], aspect: CGFloat) -> Double {
        func iso(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * aspect, y: p.y) }
        let le = iso(l), re = iso(r)
        let dist = hypot(re.x - le.x, re.y - le.y)
        guard dist > 0 else { return .nan }
        let ux = (re.x - le.x) / dist, uy = (re.y - le.y) / dist
        let mx = (le.x + re.x) / 2, my = (le.y + re.y) / 2
        func along(_ p: CGPoint) -> CGFloat {
            let q = iso(p)
            return (q.x - mx) * ux + (q.y - my) * uy
        }

        var angles: [Double] = []
        if let nose {
            angles.append(atan(Double(along(nose) / dist) / noseGain))
        }
        if contour.count >= 5 {
            let xs = contour.map(along)
            let right = xs.max() ?? 0
            let left = -(xs.min() ?? 0)
            if right > 0, left > 0 {
                angles.append(atan(Double((left - right) / (left + right)) / cheekGain))
            }
        }
        guard !angles.isEmpty else { return .nan }
        if angles.count == 2, abs(angles[0] - angles[1]) > 35 * .pi / 180 { return .nan }
        return angles.reduce(0, +) / Double(angles.count) * 180 / .pi
    }
}
