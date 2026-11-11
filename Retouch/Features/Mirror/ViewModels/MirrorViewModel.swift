import CoreGraphics
import Observation

@Observable
final class MirrorViewModel {
    private(set) var selectedPart: FacePart = .face
    private(set) var lightMode: LightMode = .off

    @ObservationIgnored let renderer: MirrorRenderer
    @ObservationIgnored private let camera: CameraServicing
    @ObservationIgnored private let lighting: LightingServicing
    @ObservationIgnored private let zoom: ZoomServicing
    @ObservationIgnored private let zoomStore: ZoomStore

    init(camera: CameraServicing, lighting: LightingServicing, zoom: ZoomServicing,
         zoomStore: ZoomStore, renderer: MirrorRenderer) {
        self.camera = camera
        self.lighting = lighting
        self.zoom = zoom
        self.zoomStore = zoomStore
        self.renderer = renderer
    }

    var zoomState: ZoomState { zoomStore.zoomState }
    var cameraState: CameraState { camera.state }
    var permission: CameraPermissionStatus { cameraState == .permissionDenied ? .denied : .granted }
    var ringLightLevel: Double { lighting.ringLightLevel }
    var ringLightWidth: CGFloat { CGFloat(lighting.config.ringLightWidth) }
    var ringLightSoftness: Double { lighting.config.ringLightSoftness }
    var filterColor: ManualColorChoice? { lighting.filterColor }
    var closeness: Double { lighting.closeness }

    func start() async {
        camera.start()
        zoom.start()
    }

    func refresh() {
        camera.start()
        zoom.start()
    }

    func stop() {
        lighting.setAuto(true)
        camera.stop()
        zoom.stop()
    }

    func retryCamera() { camera.retry() }

    func openSettings() { camera.openSettings() }

    func select(_ part: FacePart) {
        selectedPart = part
        zoom.select(part)
    }

    func setLightMode(_ mode: LightMode) {
        lightMode = mode
        lighting.setLightMode(mode)
    }

    func setViewSize(_ size: CGSize) { zoom.setViewSize(size) }

    func pinchChanged(_ magnification: CGFloat) { zoom.pinchChanged(magnification) }

    func pinchEnded() { zoom.pinchEnded() }

    func cameraStateDidChange(from old: CameraState, to new: CameraState) {
        if new == .running, old != .running {
            zoom.resetSession()
        }
    }
}
