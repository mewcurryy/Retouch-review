//
//  FusedStabilizer.swift
//  Retouch
//
//  Created by Davin P on 09/11/26.
//

import CoreGraphics
import CoreMotion
import CoreVideo
import Foundation

nonisolated final class FusedStabilizer: @unchecked Sendable {

    private struct GyroSample {
        var t: Double
        var x: Double
        var y: Double
    }

    private static let gyroIdleStop: TimeInterval = 3
    private static let calibrationTau = 8.0
    private static let maxSamples = 256

    private let tracker = FrameMotionTracker()
    private let manager = CMMotionManager()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.name = "stabilizer.fused.motion"
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInteractive
        return q
    }()
    private let lock = NSLock()
    private var samples: [GyroSample] = []
    private var isGyroRunning = false
    private var lastActiveAt = 0.0

    private var sxx = 0.0, sxy = 0.0, syy = 0.0
    private var bxx = 0.0, bxy = 0.0
    private var byx = 0.0, byy = 0.0
    private var sumM2 = 0.0
    private var sumRes2 = 0.0

    private var path = SIMD2<Double>.zero
    private var lp1 = SIMD2<Double>.zero
    private var lp2 = SIMD2<Double>.zero
    private var lastTime: Double?

    deinit {
        manager.stopDeviceMotionUpdates()
    }

    func update(_ buffer: CVPixelBuffer, time: Double, scale: Double, active: Bool) -> CGSize {
        let now = ProcessInfo.processInfo.systemUptime
        guard active else {
            if isGyroRunning, now - lastActiveAt > Self.gyroIdleStop { stopGyro() }
            reset()
            return .zero
        }
        lastActiveAt = now
        startGyroIfNeeded()

        let measured = tracker.frameShift(buffer, active: true)
        guard let last = lastTime else {
            lastTime = time
            return .zero
        }
        let dt = min(max(time - last, 0.001), 0.05)
        lastTime = time

        let rotation = gyroRotation(from: last, to: time)
        let shift = fuse(measured: measured, rotation: rotation, dt: dt)
        advance(by: shift, dt: dt)
        return correction(scale: scale)
    }

    func stop() {
        stopGyro()
        reset()
    }

    private func reset() {
        tracker.reset()
        path = .zero
        lp1 = .zero
        lp2 = .zero
        lastTime = nil
    }

    private func fuse(measured: SIMD2<Double>?, rotation: SIMD2<Double>?, dt: Double) -> SIMD2<Double> {
        let predicted = rotation.flatMap { predict($0) }
        if let measured {
            if let rotation { learn(rotation: rotation, measured: measured, predicted: predicted, dt: dt) }
            return measured
        }
        if let predicted { return predicted * gyroWeight() }
        return .zero
    }

    private func calibration() -> (kx: SIMD2<Double>, ky: SIMD2<Double>)? {
        let a = sxx + 1e-9
        let d = syy + 1e-9
        let b = sxy
        let det = a * d - b * b
        guard sxx + syy > 2e-5, det > 1e-12 else { return nil }
        let inv = 1 / det
        let kx = SIMD2((d * bxx - b * bxy) * inv, (-b * bxx + a * bxy) * inv)
        let ky = SIMD2((d * byx - b * byy) * inv, (-b * byx + a * byy) * inv)
        return (kx, ky)
    }

    private func predict(_ rotation: SIMD2<Double>) -> SIMD2<Double>? {
        guard let k = calibration() else { return nil }
        return SIMD2(k.kx.x * rotation.x + k.kx.y * rotation.y,
                     k.ky.x * rotation.x + k.ky.y * rotation.y)
    }

    private func learn(rotation: SIMD2<Double>, measured: SIMD2<Double>, predicted: SIMD2<Double>?, dt: Double) {
        let decay = exp(-dt / Self.calibrationTau)
        let residual = measured - (predicted ?? .zero)
        sumM2 = sumM2 * decay + (measured * measured).sum()
        sumRes2 = sumRes2 * decay + (residual * residual).sum()

        sxx = sxx * decay + rotation.x * rotation.x
        sxy = sxy * decay + rotation.x * rotation.y
        syy = syy * decay + rotation.y * rotation.y
        bxx = bxx * decay + rotation.x * measured.x
        bxy = bxy * decay + rotation.y * measured.x
        byx = byx * decay + rotation.x * measured.y
        byy = byy * decay + rotation.y * measured.y
    }

    private func gyroWeight() -> Double {
        guard sumM2 > 1e-9 else { return 0 }
        let r2 = 1 - sumRes2 / sumM2
        return min(max((r2 - 0.2) / 0.4, 0), 1)
    }

    private func advance(by shift: SIMD2<Double>, dt: Double) {
        path += shift
        let a = 1 - exp(-dt / ZoomTuning.fusedPathTau)
        lp1 += (path - lp1) * a
        lp2 += (lp1 - lp2) * a
    }

    private func correction(scale: Double) -> CGSize {
        let fast = path - lp2
        let margin = 0.5 * (1 - 1 / max(scale, 1)) * ZoomTuning.stabMarginUse
        let signX = ZoomTuning.trackInvertX ? 1.0 : -1.0
        let signY = ZoomTuning.trackInvertY ? 1.0 : -1.0
        return CGSize(width: Self.softClamp(signX * fast.x, margin),
                      height: Self.softClamp(signY * fast.y, margin))
    }

    private static func softClamp(_ value: Double, _ margin: Double) -> Double {
        guard margin > 0.0005 else { return 0 }
        return margin * tanh(value / margin)
    }

    private func startGyroIfNeeded() {
        guard !isGyroRunning, manager.isDeviceMotionAvailable else { return }
        isGyroRunning = true
        manager.deviceMotionUpdateInterval = 1.0 / ZoomTuning.stabSampleRate
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let m = motion else { return }
            self.ingest(m.timestamp, m.rotationRate.x, m.rotationRate.y)
        }
    }

    private func stopGyro() {
        manager.stopDeviceMotionUpdates()
        isGyroRunning = false
        lock.lock()
        samples.removeAll()
        lock.unlock()
    }

    private func ingest(_ t: Double, _ wx: Double, _ wy: Double) {
        lock.lock()
        samples.append(GyroSample(t: t, x: wx, y: wy))
        if samples.count > Self.maxSamples { samples.removeFirst(samples.count - Self.maxSamples) }
        lock.unlock()
    }

    private func gyroRotation(from t0: Double, to t1: Double) -> SIMD2<Double>? {
        lock.lock()
        defer { lock.unlock() }
        guard t1 > t0, samples.count >= 2,
              let first = samples.first, let last = samples.last,
              t0 >= first.t, t1 <= last.t + 0.05 else { return nil }

        var total = SIMD2<Double>.zero
        for i in 0..<(samples.count - 1) {
            let a = samples[i], b = samples[i + 1]
            let lo = max(a.t, t0), hi = min(b.t, t1)
            guard hi > lo, b.t > a.t else { continue }
            let span = b.t - a.t
            let fLo = (lo - a.t) / span, fHi = (hi - a.t) / span
            let rateLo = SIMD2(a.x + (b.x - a.x) * fLo, a.y + (b.y - a.y) * fLo)
            let rateHi = SIMD2(a.x + (b.x - a.x) * fHi, a.y + (b.y - a.y) * fHi)
            total += (rateLo + rateHi) * (0.5 * (hi - lo))
        }
        return total
    }
}
