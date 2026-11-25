//
//  LyricClock.swift
//  Celestify
//
//  Frame-steered, rate-learning, monotonic smoothstep-gliding playhead clock.
//  Adapted from BitChord (https://github.com/kushagrasinghx/BitChord, GPL-3.0-or-later)
//  and Myspoti (LyricClock.kt, GPL-3.0).
//
//  Three invariants:
//    1. Player readings are stamped by when they were sampled, never by when a busy UI frame saw them.
//    2. Words never move backwards unless an explicit seek/skip discontinuity is announced.
//    3. Readings steer rather than snap: small drift closes via slew (+25% / -50%), larger forward
//       steps glide over 260ms smoothstep, and playback speed (0.25x..4.0x) is learned continuously.
//

import Foundation

public final class LyricClock {
    public private(set) var displayedMs: Double

    private var lastNowMs: Double = .nan
    private var lastReportMs: Int64 = .min
    private var lastSampledAtMs: Double = .nan
    private var heldAtMs: Double = -.infinity

    private var lastDiscontinuity: Int64?
    private var jumpPending: Bool = false

    private var anchorAtMs: Double = .nan
    private var anchorMs: Double = 0.0
    public private(set) var learnedRate: Double = 1.0

    private var historyAt = [Double](repeating: 0, count: LyricClock.historyCapacity)
    private var historyMs = [Double](repeating: 0, count: LyricClock.historyCapacity)
    private var historySize: Int = 0
    private var rateSettled: Bool = false

    private var suspectAtMs: Double = .nan
    private var suspectMs: Int64 = 0
    private var rejections: Int = 0

    private var glideStartMs: Double = .nan
    private var glideOffsetMs: Double = 0.0

    // Constants matching Android LyricClock.kt
    private static let outlierMs: Double = 250.0
    private static let rateSlack: Double = 0.20
    private static let unsettledRateSlack: Double = 0.75
    private static let maxRejections: Int = 2
    private static let minRateSpanMs: Double = 900.0
    private static let rateWindowMs: Double = 4_000.0
    private static let historyCapacity: Int = 16
    private static let minPairSpanMs: Double = 300.0
    private static let pairLearning: Double = 0.50
    private static let minRate: Double = 0.25
    private static let maxRate: Double = 4.00
    private static let correctionMs: Double = 600.0
    private static let maxSlew: Double = 0.25
    private static let maxSlow: Double = 0.50
    private static let glideFromMs: Double = 300.0
    private static let glideMs: Double = 260.0
    private static let glideMaxMs: Double = 2_000.0
    private static let lostMs: Double = 3_000.0

    public init(startMs: Int64 = 0) {
        self.displayedMs = Double(startMs)
    }

    public func restart() {
        lastNowMs = .nan
        jumpPending = false
        glideStartMs = .nan
        clearSuspect()
    }

    public func hold(positionMs: Int64, nowMs: Double) {
        restart()
        displayedMs = Double(positionMs)
        heldAtMs = nowMs
    }

    public func frame(
        nowMs: Double,
        reportedMs: Int64,
        sampledAtMs: Double = .nan,
        discontinuity: Int64 = 0
    ) -> Int64 {
        let firstOfRun = lastNowMs.isNaN
        if discontinuity != lastDiscontinuity {
            if lastDiscontinuity != nil && !firstOfRun {
                jumpPending = true
            }
            lastDiscontinuity = discontinuity
        }

        let isNew = reportedMs != lastReportMs || (!sampledAtMs.isNaN && sampledAtMs != lastSampledAtMs)
        lastReportMs = reportedMs
        lastSampledAtMs = sampledAtMs

        if firstOfRun {
            lastNowMs = nowMs
            let takenAt: Double = {
                if sampledAtMs.isNaN || sampledAtMs <= heldAtMs { return nowMs }
                return min(sampledAtMs, nowMs)
            }()
            anchor(atMs: takenAt, positionMs: reportedMs)
            displayedMs = target(atMs: nowMs)
            return Int64(displayedMs.rounded())
        }

        let dt = max(0.0, nowMs - lastNowMs)
        lastNowMs = nowMs
        advance(nowMs: nowMs, dt: dt)

        if isNew {
            let takenAt = sampledAtMs.isNaN ? nowMs : min(sampledAtMs, nowMs)
            if takenAt >= anchorAtMs || jumpPending {
                take(nowMs: nowMs, takenAt: takenAt, reportedMs: reportedMs)
            }
        }
        return Int64(max(0.0, displayedMs).rounded())
    }

    // MARK: - Internal Clock Mechanics

    private func take(nowMs: Double, takenAt: Double, reportedMs: Int64) {
        if jumpPending {
            jumpPending = false
            clearSuspect()
            anchor(atMs: takenAt, positionMs: reportedMs)
            jumpTo(nowMs: nowMs)
            return
        }

        let elapsed = takenAt - anchorAtMs
        if abs(Double(reportedMs) - (anchorMs + elapsed * learnedRate)) <= tolerance(elapsedMs: elapsed) {
            clearSuspect()
            anchor(atMs: takenAt, positionMs: reportedMs, continues: true)
            return
        }

        let sinceSuspect = takenAt - suspectAtMs
        let agrees = !suspectAtMs.isNaN && sinceSuspect >= 0 &&
            abs(Double(reportedMs) - (Double(suspectMs) + sinceSuspect * learnedRate)) <= tolerance(elapsedMs: sinceSuspect)
        rejections += 1

        if agrees {
            let firstAt = suspectAtMs
            let first = suspectMs
            clearSuspect()
            anchor(atMs: firstAt, positionMs: first)
            anchor(atMs: takenAt, positionMs: reportedMs, continues: true)
        } else if rejections > Self.maxRejections {
            clearSuspect()
            anchor(atMs: takenAt, positionMs: reportedMs)
        } else {
            suspectAtMs = takenAt
            suspectMs = reportedMs
        }
    }

    private func tolerance(elapsedMs: Double) -> Double {
        Self.outlierMs + abs(elapsedMs) * (rateSettled ? Self.rateSlack : Self.unsettledRateSlack)
    }

    private func anchor(atMs: Double, positionMs: Int64, continues: Bool = false) {
        anchorAtMs = atMs
        anchorMs = Double(positionMs)
        if !continues { historySize = 0 }
        if historySize == Self.historyCapacity {
            for idx in 0..<(Self.historyCapacity - 1) {
                historyAt[idx] = historyAt[idx + 1]
                historyMs[idx] = historyMs[idx + 1]
            }
            historySize -= 1
        }
        historyAt[historySize] = atMs
        historyMs[historySize] = anchorMs
        historySize += 1
        learnRate()
    }

    private func learnRate() {
        let newest = historySize - 1
        guard newest >= 1 else { return }
        var oldest = 0
        while oldest < newest && (historyAt[newest] - historyAt[oldest]) > Self.rateWindowMs {
            oldest += 1
        }
        let span = historyAt[newest] - historyAt[oldest]
        if span >= Self.minRateSpanMs {
            let raw = (historyMs[newest] - historyMs[oldest]) / span
            learnedRate = min(max(raw, Self.minRate), Self.maxRate)
            rateSettled = true
            return
        }
        let pairSpan = historyAt[newest] - historyAt[newest - 1]
        if !rateSettled && pairSpan >= Self.minPairSpanMs {
            let measured = min(max((historyMs[newest] - historyMs[newest - 1]) / pairSpan, Self.minRate), Self.maxRate)
            learnedRate += (measured - learnedRate) * Self.pairLearning
        }
    }

    private func clearSuspect() {
        suspectAtMs = .nan
        rejections = 0
    }

    private func advance(nowMs: Double, dt: Double) {
        let tgt = target(atMs: nowMs)
        let step = dt * learnedRate
        let error = tgt - (displayedMs + step)

        if !glideStartMs.isNaN {
            let progress = (nowMs - glideStartMs) / Self.glideMs
            if progress >= 1.0 {
                displayedMs = tgt
                glideStartMs = .nan
            } else {
                displayedMs = tgt + glideOffsetMs * (1.0 - Self.smoothstep(progress))
            }
        } else if error <= -Self.lostMs || error >= Self.lostMs {
            displayedMs = tgt
        } else if error >= Self.glideFromMs {
            startGlide(startMs: nowMs - dt, offsetMs: displayedMs - (tgt - step))
            displayedMs = tgt + glideOffsetMs * (1.0 - Self.smoothstep(dt / Self.glideMs))
        } else {
            let closing = error * (dt / (dt + Self.correctionMs))
            let clamped = min(max(closing, -Self.maxSlow * step), Self.maxSlew * step)
            displayedMs += step + clamped
        }
    }

    private func jumpTo(nowMs: Double) {
        let tgt = target(atMs: nowMs)
        let offset = displayedMs - tgt
        if abs(offset) > Self.glideMaxMs {
            displayedMs = tgt
            glideStartMs = .nan
        } else {
            startGlide(startMs: nowMs, offsetMs: offset)
        }
    }

    private func startGlide(startMs: Double, offsetMs: Double) {
        glideStartMs = startMs
        glideOffsetMs = offsetMs
    }

    private func target(atMs: Double) -> Double {
        anchorMs + (atMs - anchorAtMs) * learnedRate
    }

    private static func smoothstep(_ fraction: Double) -> Double {
        let t = min(max(fraction, 0.0), 1.0)
        return t * t * (3.0 - 2.0 * t)
    }
}
