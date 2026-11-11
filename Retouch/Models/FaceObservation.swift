import CoreGraphics

nonisolated struct FaceObservation {
    var leftEye: CGPoint?
    var rightEye: CGPoint?
    var lips: CGPoint?
    var center: CGPoint
    var width: CGFloat
    var yaw: Double
    var aspect: Double
    var pitch: Double = .nan
    var mouthWidth: Double = .nan
    var mouthHeight: Double = .nan
    var mouthGap: Double = .nan
    var leftEyeOpen: Double = .nan
    var rightEyeOpen: Double = .nan
    var visibleEyes = 2
    var eyeWidthRatio: Double = .nan
    var lipsTop: CGPoint?
    var nose: CGPoint?
}

nonisolated struct FacePoints {
    var leftEye: CGPoint?
    var rightEye: CGPoint?
    var lips: CGPoint?
    var nose: CGPoint?
    var lipsTop: CGPoint?
    var center: CGPoint?
    var width: CGFloat = 0
    var scale: CGFloat = 0

    var handTargets: [(ZoomTarget, CGPoint)] {
        var result: [(ZoomTarget, CGPoint)] = []
        if let p = leftEye { result.append((.leftEye, p)) }
        if let p = rightEye { result.append((.rightEye, p)) }
        if let p = lips { result.append((.lips, p)) }
        if let p = nose { result.append((.nose, p)) }
        return result
    }
}
