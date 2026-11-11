import Foundation
import CoreImage
import Vision

nonisolated struct ZoomTuning {
    static let detectionRate = 12.0
    static let fairRate = 8.0
    static let seriousRate = 5.0
    static let idleRate = 6.0
    static let idleAfter: TimeInterval = 3.0
    static let idleFaceSpeed = 0.3
    static let idleYawRate = 25.0
    static let envCheckInterval: TimeInterval = 2.0

    static let downscaleEnabled = true
    static let analysisWidth: CGFloat = 640

    static let yawTau = 0.15
    static let pointTau: CGFloat = 0.1
    static let scaleTau: CGFloat = 0.65
    static let handSpeedTau: CGFloat = 0.15
    static let fullFaceZoom: CGFloat = 1.1
    static let eyeZoomScale: CGFloat = 2.25
    static let lipsZoomScale: CGFloat = 2.12
    static let noseZoomScale: CGFloat = 1.9

    static let sideZoom: CGFloat = 1.6
    static let sideEnterDwell: TimeInterval = 0.5
    static let sideExitDwell: TimeInterval = 0.7
    static let sideFocusStrength: CGFloat = 1
    static let sideFocusOutward: CGFloat = 0.30
    static let sideFocusDrop: CGFloat = 0.3
    static let sideResolverExitHold: TimeInterval = 0.3
    static let sideFastExitEnabled = true
    static let sideFastExitTravel = 55.0
    static let sideFastExitTravelTau = 0.5
    static let sideFastExitArmDelay: TimeInterval = 0.6

    static let handEnterDistance = 0.38
    static let handMaxSpeed = 1.2
    static let eyeEnterFactor: CGFloat = 0.85
    static let handEnterDwell: TimeInterval = 0.35
    static let eyeEnterDwell: TimeInterval = 0.4
    static let handWinMargin: CGFloat = 0.12
    static let handSwitchMargin: CGFloat = 0.12
    static let handSwitchDwell: TimeInterval = 0.3
    static let handHoldGrace: TimeInterval = 0.4
    static let coverDistance: CGFloat = 0.65
    static let coverGrace: TimeInterval = 1.8
    static let coverHold: TimeInterval = 1.8
    static let coverFollowEnabled = true
    static let coverFollowMinScale: CGFloat = 0.8
    static let coverFollowMaxScale: CGFloat = 1.25
    static let widthTau: CGFloat = 0.65

    static let resolverSwitchDwell: TimeInterval = 0.15

    static let zoomInTau: CGFloat = 0.2
    static let zoomOutTau: CGFloat = 0.25

    static let exitHold: TimeInterval = 1.2
    static let minTurnEnter = 16.0
    static let turnPeakDefault = 33.0
    static let turnLearnMinEpisode: TimeInterval = 1.0
    static let turnLearnStep = 0.1
    static let turnLearnSessionCap = 6.0
    static let turnUnwantedStep = 2.0
    static let sideCorrectionWindow: TimeInterval = 6.0
    static let sideCorrectionAfterEnd: TimeInterval = 3.0
    static let handLearnSessionRange = 0.15
    static let headRearmEnabled = true
    static let headRearmStraight: TimeInterval = 0.3
    static let eventLogCapacity = 500
    static let flipFlopWindow: TimeInterval = 1.5

    static let pitchEnabled = true
    static let pitchYawFreezeEnabled = true
    static let pitchHandSupportEnabled = true
    static let pitchNominalRatio = 0.6
    static let pitchNoseGain = 0.4
    static let pitchMaxYaw = 35.0
    static let pitchTau = 0.2
    static let pitchLiftEnter = 6.0
    static let pitchLiftExit = 3.0
    static let pitchLiftDwell: TimeInterval = 0.2
    static let pitchReleaseDwell: TimeInterval = 0.3
    static let pitchFreezeRate = 40.0
    static let pitchFreezeHold: TimeInterval = 0.35
    static let pitchLearnWindow = 8.0
    static let pitchBaselineTau = 6.0
    static let maxPitchBaseline = 10.0
    static let pitchLipsReach: CGFloat = 1.15
    static let pitchLipsDwellFactor: TimeInterval = 0.6
    static let pitchEyeReach: CGFloat = 1.1
    static let pitchEyeDwellFactor: TimeInterval = 0.75

    static let toolTipReach: CGFloat = 0.3
    static let toolReachFist: CGFloat = 0.5
    static let toolFistMaxExt: CGFloat = 1.6
    static let gripCurlMax: CGFloat = 1.45
    static let gripStraightMin: CGFloat = 1.75
    static let gripMinCurled = 2
    static let gripThumbMax: CGFloat = 0.8
    static let gripEnterDwell: TimeInterval = 0.5

    static let eyeGripScaleOuter: CGFloat = 1.35
    static let eyeGripScaleInner: CGFloat = 1.0
    static let eyeGripScaleY: CGFloat = 1.5

    static var eyeHoldScaleX: CGFloat { max(eyeHoldScale, eyeGripScaleOuter) }
    static var eyeHoldScaleY: CGFloat { max(eyeHoldScale, eyeGripScaleY) }

    static let handMaxGap: TimeInterval = 0.5
    static let maxStep: TimeInterval = 0.35
    static let nominalStep: TimeInterval = 1.0 / 12.0

    static let lipsEnterDwell: TimeInterval = 0.5
    static let lipsReleaseDwell: TimeInterval = 1.0
    static let lipsPose2Max: CGFloat = 0.4
    static let lipsHoldRadius = handEnterDistance * 0.85
    static let lipMotionBaselineTau = 0.8
    static let lipMotionDevTau = 0.15
    static let lipMotionEnter = 0.05
    static let lipMotionExit = 0.025
    static let lipMotionLostGrace: TimeInterval = 0.5
    static let lipsTriggerStretchX: CGFloat = 1.1
    static let lipsTriggerStretchY: CGFloat = 0.7
    static let lipsHoldScale: CGFloat = 1.3

    static let lipsLineOffset: CGFloat = 0
    static let lipsHoldLineTolerance: CGFloat = 0.1

    static let eyeTriggerRadiusX: CGFloat = 0.5
    static let eyeTriggerRadiusY: CGFloat = 0.4
    static let eyeZoneHold: CGFloat = 0.70
    static let eyeZoneDead: CGFloat = 0.09
    static let eyeZoneOffsetX: CGFloat = 0.12
    static let eyeHoldScale: CGFloat = 1.2
    static let eyeFlowEnterDwell: TimeInterval = 0.5
    static let eyeFlowSwitchDwell: TimeInterval = 0.15
    static let eyeFlowReleaseDwell: TimeInterval = 1.0
    static let eyeActivityEnter = 0.15
    static let eyeActivityExit = 0.07
    static let eyeTurnWidthRatio = 0.6
    static let eyeActivitySustain: TimeInterval = 0.45
    static let eyeActivityClear: TimeInterval = 0.2
    static let eyeActivityTau = 0.1
    static let eyeBaselineTau = 6.0
    static let eyeActivityMaxYaw = 25.0
    static let eyeLearnMaxYaw = 15.0
    static let eyeUnknownCap: TimeInterval = 2.2
    static let eyeFlowPoseGrace: TimeInterval = 0.3
    static let eyeSoftHoldCap: TimeInterval = 3.0
    static let eyeHoldUsesAllFingertips = true

    static let noseEnterDwell: TimeInterval = 0.5
    static let noseReleaseDwell: TimeInterval = 1.0
    static let noseTriggerRadiusX: CGFloat = 0.35
    static let noseTriggerRadiusY: CGFloat = 0.7
    static let noseHoldScale: CGFloat = 1.3
    static let noseTopLimit: CGFloat = 0.3
    static let noseOwnHalfWidth: CGFloat = 0.45
    static let noseCenterOffsetX: CGFloat = 0
    static let noseCenterOffsetY: CGFloat = -0.2
    static let fingerPointEnabled = true
    static let fingerPointDwell: TimeInterval = 0.6
    static let nosePointDwell: TimeInterval = fingerPointDwell
    static let noseLostHoldCap: TimeInterval = 1.5

    static let pinInset: CGFloat = 0.12
    static let panSmoothTime: CGFloat = 0.18
    static let focusMinCutoff: Double = 0.4
    static let focusBeta: Double = 0.06

    static let distGamma: Double = 1.0
    static let distMinFactor: Double = 0.1
    static let distMaxFactor: Double = 10.0
    static let distMaxScale: CGFloat = 30.0
    static let distMaxYaw: Double = 40.0
    static let distDeadBand: Double = 0.02
    static let distFilterMinCutoff: Double = 0.7
    static let distFilterBeta: Double = 3.0
    static let distBaselineSpan: Double = 0.4

    static let stabSampleRate: Double = 100.0
    static let stabMarginUse: Double = 0.95
    static let fusedPathTau: Double = 0.4

    static let handLowLightEnabled = true
    static let handDarkRelaxEnabled = true
    static let handSeenBoostsRate = true
    static let handLowLightTargetLuma = 0.18
    static let handLowLightMinEV = 0.6
    static let handLowLightMaxEV = 3.0
    static let handLowLightMeasureInterval: TimeInterval = 0.5
    static let handDarkEVThreshold = 1.0
    static let handDarkJointConfidence: Float = 0.15
    static let handDarkBaseConfidence: Float = 0.12

    static let handLostHoldCap: TimeInterval = 0.75
    static let handLostHoldEnabled = true

    static let poseKeepEnabled = true
    static let poseKeepMaxAge: TimeInterval = 0.6
    static let poseKeepRadius: CGFloat = 0.8
    static let poseKeepFactor: CGFloat = 1.3
    static let poseKeepJointConfidence: Float = 0.15
    static let poseKeepBaseConfidence: Float = 0.12
    static let gripCurlKeepMax: CGFloat = 1.6
    static let gripStraightKeepMin: CGFloat = 1.85
    static let gripThumbKeepMax: CGFloat = 1.0

    static let trackEnabled: Bool = true
    static let trackInvertX: Bool = false
    static let trackInvertY: Bool = false
}
