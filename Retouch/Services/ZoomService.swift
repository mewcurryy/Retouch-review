import AVFoundation

nonisolated protocol ZoomServicing: AnyObject, Sendable {
    var onZoomChange: (@Sendable (ZoomState) -> Void)? { get set }
    var onTracking: (@Sendable (ZoomTracking) -> Void)? { get set }
    func start()
    func stop()
    func setViewSize(_ size: CGSize)
    func process(_ pixelBuffer: CVPixelBuffer)
    func setGestureEnabled(_ isEnabled: Bool)
    func setManualTarget(_ target: ZoomTarget)
    func pinchChanged(_ magnification: CGFloat)
    func pinchEnded()
    func resetSession()
    func select(_ part: FacePart)
}

nonisolated final class ZoomService: ZoomServicing, @unchecked Sendable {
    var onZoomChange: (@Sendable (ZoomState) -> Void)? {
        get { animator.onChange }
        set { animator.onChange = newValue }
    }
    var onTracking: (@Sendable (ZoomTracking) -> Void)?

    static let preemptDwellFactor: TimeInterval = 0.4

    let animator = ZoomAnimator()
    let faceDetector = FaceLandmarkDetector()
    let handDetector = HandPointDetector()
    let stateQueue = DispatchQueue(label: "zoom.state")

    let seqLock = NSLock()
    var queuedFaceSeq = 0
    var queuedHandSeq = 0

    var headPose: HeadPoseRecognizer
    var turnAnchor: Double
    var pitchRecognizer: HeadPitchRecognizer
    var resolver: ZoomGestureResolver
    var faceTracker = FacePointTracker()
    var pacer = DetectionPacer()
    var viewSize: CGSize = .zero
    var isGestureEnabled = true
    var manualTarget: ZoomTarget = .fullFace

    var lastFace: FaceObservation?
    var lastScan = HandScan()
    var lastHand: CGPoint?

    var lipFlow = LipsZoomFlow()
    var lipMotion = LipMotionRecognizer()
    var lipsInput = LipsZoomFlow.Input()

    var noseFlow = NoseZoomFlow()
    var noseInput = NoseZoomFlow.Input()
    enum FlowOwner { case eye, lips, nose }
    var handTarget: ZoomTarget?
    var headTarget: ZoomTarget?
    var lastLogicTime = Date.distantPast
    var prevFace: FaceObservation?
    var prevFaceTime = Date.distantPast
    var handBank = HandTrackBank()
    var hands: [TrackedHand] = []
    var activeHands: [TrackedHand] { hands.filter { $0.hasPose || $0.holding } }
    var eyeFlow = EyeZoomFlow()
    var eyeActivity = EyeActivityRecognizer()
    var eyeInput = EyeZoomFlow.Input()
    var distComp = DistanceCompensator()

    var pinchScale: CGFloat = 1
    var pinchBase: CGFloat = 1
    var pinchActive = false
    var pinchStartScale: CGFloat = 1
    var pinchStartAuto = false
    var pinchStartIdle = false
    var pinchStartSide = false

    var handProfile: HandProfile
    var savedProfile = HeadProfile()
    var savedHandProfile = HandProfile()
    var savedPitchProfile = PitchProfile()
    var lastProfileCheck = Date.distantPast
    var autoZoomSince: Date?
    var lastAutoZoomEnd = Date.distantPast
    var sideZoomSince: Date?
    var lastSideZoomStart = Date.distantPast
    var lastSideZoomEnd = Date.distantPast
    var lastCorrection = Date.distantPast

    init() {
        var profile = HandProfileStore.load()
        profile.beginSession()
        handProfile = profile
        resolver = ZoomGestureResolver()
        let head = HeadPoseRecognizer(profile: HeadProfileStore.load())
        headPose = head
        turnAnchor = head.turnAnchor
        pitchRecognizer = HeadPitchRecognizer(profile: PitchProfileStore.load())
        handBank.apply(profile)
    }

    func makeResolver() -> ZoomGestureResolver {
        ZoomGestureResolver()
    }

    func makeHeadPose() -> HeadPoseRecognizer {
        HeadPoseRecognizer(profile: headPose.profile, turnAnchor: turnAnchor)
    }

    func makePitch() -> HeadPitchRecognizer {
        HeadPitchRecognizer(profile: pitchRecognizer.profile)
    }

    func makeHandBank() -> HandTrackBank {
        var bank = HandTrackBank()
        bank.apply(handProfile)
        return bank
    }

    func clearCachedDetections() {
        lastFace = nil
        lastScan = HandScan()
        lastHand = nil
        handTarget = nil
        headTarget = nil
        prevFace = nil
        handBank = makeHandBank()
        hands = []
        lipFlow = LipsZoomFlow()
        lipMotion = LipMotionRecognizer()
        lipsInput = LipsZoomFlow.Input()
        eyeFlow = EyeZoomFlow()
        eyeActivity = EyeActivityRecognizer()
        eyeInput = EyeZoomFlow.Input()
        noseFlow = NoseZoomFlow()
        noseInput = NoseZoomFlow.Input()
        distComp = DistanceCompensator()
    }

    func syncQueuedSequences() {
        let faceSeq = faceDetector.snapshot.sequence
        let handSeq = handDetector.snapshot.sequence
        seqLock.lock()
        queuedFaceSeq = faceSeq
        queuedHandSeq = handSeq
        seqLock.unlock()
    }

    func start() { DispatchQueue.main.async { [animator] in animator.start() } }

    func stop() {
        DispatchQueue.main.async { [animator] in animator.stop() }
        stateQueue.async { [self] in
            HeadProfileStore.save(headPose.profile)
            HandProfileStore.save(handProfile)
            PitchProfileStore.save(pitchRecognizer.profile)
        }
    }

    func setViewSize(_ size: CGSize) {
        DispatchQueue.main.async { [animator] in animator.setViewSize(size) }
        stateQueue.async { [self] in viewSize = size }
    }

    func resetSession() {
        DispatchQueue.main.async { [animator] in animator.reset() }
        faceDetector.reset()
        handDetector.reset()
        syncQueuedSequences()
        stateQueue.async { [self] in
            headPose = makeHeadPose()
            pitchRecognizer = makePitch()
            faceTracker = FacePointTracker()
            resolver = makeResolver()
            clearCachedDetections()
            pinchScale = 1
            pinchBase = 1
            pinchActive = false
            autoZoomSince = nil
            sideZoomSince = nil
            publish(isGestureEnabled ? .fullFace : manualTarget)
        }
    }

    func process(_ pixelBuffer: CVPixelBuffer) {
        let (isAuto, interval) = stateQueue.sync { (isGestureEnabled, pacer.interval(now: Date())) }
        faceDetector.submit(pixelBuffer, minInterval: interval)
        if isAuto { handDetector.submit(pixelBuffer, minInterval: interval) }

        let face = faceDetector.snapshot
        let hand: DetectionSnapshot<HandScan>? = isAuto ? handDetector.snapshot : nil

        seqLock.lock()
        let newFace = face.sequence != queuedFaceSeq
        let newHand = hand.map { $0.sequence != queuedHandSeq } ?? false
        if newFace { queuedFaceSeq = face.sequence }
        if let hand, newHand { queuedHandSeq = hand.sequence }
        seqLock.unlock()
        guard newFace || newHand else { return }

        let imageSize = CGSize(width: CVPixelBufferGetHeight(pixelBuffer),
                               height: CVPixelBufferGetWidth(pixelBuffer))
        stateQueue.async { [self] in
            update(faceSnap: newFace ? face : nil,
                   handSnap: newHand ? hand : nil,
                   imageSize: imageSize)
        }
    }

    func setGestureEnabled(_ isEnabled: Bool) {
        syncQueuedSequences()
        stateQueue.async { [self] in
            isGestureEnabled = isEnabled
            headPose = makeHeadPose()
            pitchRecognizer = makePitch()
            resolver = makeResolver()
            clearCachedDetections()
            manualTarget = .fullFace
            pinchScale = 1
            pinchBase = 1
            pinchActive = false
            autoZoomSince = nil
            sideZoomSince = nil
            publish(.fullFace)
        }
    }

    func select(_ part: FacePart) {
        guard let target = part.zoomTarget else {
            setGestureEnabled(true)
            return
        }
        setGestureEnabled(false)
        setManualTarget(target)
    }

    func setManualTarget(_ target: ZoomTarget) {
        stateQueue.async { [self] in
            manualTarget = target
            pinchScale = 1
            pinchBase = 1
            pinchActive = false
            if !isGestureEnabled { publish(target) }
        }
    }
}
