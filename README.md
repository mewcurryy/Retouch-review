# Retouch: Code Review Excerpt

Retouch is a portable digital mirror for iPhone. It uses the front camera for makeup and grooming, adjusts to your room light, and zooms in on the part of your face you're working on, with less tapping.

- App Store (v1.0 live, v2.0 in review): https://apps.apple.com/id/app/retouch-the-better-mirror/id6827142921
- TestFlight (v2.0): https://testflight.apple.com/join/a6sEP244

## What this excerpt is

18 files from the v2.0 codebase covering **one feature: hands-free eye zoom gesture**, from the composition root down to the algorithms. It is an excerpt for review and **does not build standalone**, because the rest of the project is intentionally omitted.

## Architecture

View → ViewModel → Service (protocol) → Model. Services are created only in `AppContainer`. The screen that surfaces this feature is the Mirror screen; only its ViewModel is included here.

## Suggested reading order

1. `Retouch/App/AppContainer.swift`: composition root and dependency injection
2. `Retouch/Features/Mirror/ViewModels/MirrorViewModel.swift`: boundary between UI and services
3. `Retouch/Services/ZoomGesture/ZoomService.swift`: `ZoomServicing` protocol and implementation
4. `Retouch/Services/ZoomGesture/ZoomService+Frame.swift`: per-frame hot path
5. `Retouch/Services/ZoomGesture/Tracking/FusedStabilizer.swift`: stabilizer
6. `Retouch/Services/ZoomGesture/Detection/FaceLandmarkDetector.swift`: Vision entry point

## All files

| Layer | Files |
|---|---|
| App | `AppContainer` |
| ViewModel | `MirrorViewModel` |
| Service | `ZoomService`, `ZoomService+Frame`, `ZoomGestureResolver`, `ZoomAnimator`, `ZoomTuning`, `ZoomReadiness` |
| Flows / Recognition | `EyeZoomFlow`, `EyeZones`, `EyeActivityRecognizer` |
| Tracking / Detection | `FusedStabilizer`, `OneEuroFilter`, `DetectionPacer`, `FaceLandmarkDetector` |
| Geometry | `DistanceCompensator` |
| Models | `ZoomState`, `FaceObservation` |

## Stack

SwiftUI (iOS 18+), AVFoundation, Vision, Core Image / Metal, WidgetKit / Live Activities / App Intents, XcodeGen, Jenkins and Xcode Cloud. No third-party dependencies.

## Commit history

This is a fresh repo. The project history lives in the previous repository: [OLD REPO LINK]
