//
//  OneEuroFilter.swift
//  Retouch
//
//  Created by Davin P on 25/10/26.
//

import Foundation

nonisolated struct OneEuroFilter {
    var minCutoff = 1.2
    var beta = 2.0
    var dCutoff = 1.0
    private var xPrev: Double?
    private var dxPrev = 0.0
    private var tPrev: Double?

    mutating func reset() {
        xPrev = nil
        tPrev = nil
        dxPrev = 0
    }

    mutating func filter(_ x: Double, t: Double) -> Double {
        guard let xp = xPrev, let tp = tPrev else {
            xPrev = x
            tPrev = t
            return x
        }
        let dt = max(t - tp, 1e-3)
        let dx = (x - xp) / dt
        let aD = alpha(dCutoff, dt)
        let dxHat = aD * dx + (1 - aD) * dxPrev
        let a = alpha(minCutoff + beta * abs(dxHat), dt)
        let xHat = a * x + (1 - a) * xp
        xPrev = xHat
        dxPrev = dxHat
        tPrev = t
        return xHat
    }

    private func alpha(_ cutoff: Double, _ dt: Double) -> Double {
        let tau = 1.0 / (2.0 * Double.pi * cutoff)
        return 1.0 / (1.0 + tau / dt)
    }
}
