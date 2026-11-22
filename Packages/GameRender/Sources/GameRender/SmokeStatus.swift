// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import Foundation

/// Written to the app Documents directory so `simulator_smoke.sh` can assert aliveness / FPS / milestones.
public struct SmokeStatus: Equatable, Sendable {
    public var phase: String
    /// `loading` while atlases warm; `ident` during publisher splash; `ready` once title chrome is on screen.
    public var boot: String
    public var fpsAvg: Double
    public var fpsSamples: Int
    /// Longest raw frame gap in milliseconds (freeze detector).
    public var maxFrameMs: Double
    public var stomps: Int
    public var shinies: Int
    /// Sticky: Mask Mode has been entered at least once (milestone).
    public var mask: Bool
    /// Live: bandit is currently in Mask Mode (for 04 capture handshake).
    public var maskOn: Bool
    public var died: Bool
    public var won: Bool
    public var elapsed: Double
    /// Monotonic wall-clock seconds since first `beginPlay` (survives death/retry).
    public var wallElapsed: Double
    /// Count of banned debug/placeholder SKLabel texts currently in the scene tree.
    /// CI fails if this is ever > 0 during smoke.
    public var debugLabels: Int
    public var combo: Int
    public var medals: Int
    public var map: Bool
    public var daily: Bool
    /// Pause sheet visible (manual or system).
    public var paused: Bool
    /// Current hero screen-x as a fraction of scene width (0 = left edge).
    /// NOTE: with right-facing look-ahead this settles near ~0.32 — it is NOT world progress.
    public var heroX: Double
    /// Min/max heroX sampled during live play (framing gate).
    public var heroXMin: Double
    public var heroXMax: Double
    /// Bandit world tile X (map column) — use this for soft-lock / progress, not heroX.
    public var worldTX: Int
    /// Bandit world tile Y (map row).
    public var worldTY: Int
    /// Max worldTX reached during the run (sticky).
    public var worldTXMax: Int
    /// Title chrome layout OK: logo in safe area + no overlapping button frames.
    public var titleOk: Bool
    /// Bandit is on the rooftop route (above street deck).
    public var roof: Bool
    /// Seconds of live play with unchanged worldTX (soft-lock detector).
    public var stallSec: Double
    /// 1 when titleRoot is hidden (live playfield on screen) — layout shots must require this.
    public var titleHidden: Bool

    public init(
        phase: String = "title",
        boot: String = "loading",
        fpsAvg: Double = 0,
        fpsSamples: Int = 0,
        maxFrameMs: Double = 0,
        stomps: Int = 0,
        shinies: Int = 0,
        mask: Bool = false,
        maskOn: Bool = false,
        died: Bool = false,
        won: Bool = false,
        elapsed: Double = 0,
        wallElapsed: Double = 0,
        debugLabels: Int = 0,
        combo: Int = 0,
        medals: Int = 0,
        map: Bool = false,
        daily: Bool = false,
        paused: Bool = false,
        heroX: Double = 0.5,
        heroXMin: Double = 1,
        heroXMax: Double = 0,
        worldTX: Int = 0,
        worldTY: Int = 0,
        worldTXMax: Int = 0,
        titleOk: Bool = false,
        roof: Bool = false,
        stallSec: Double = 0,
        titleHidden: Bool = false
    ) {
        self.phase = phase
        self.boot = boot
        self.fpsAvg = fpsAvg
        self.fpsSamples = fpsSamples
        self.maxFrameMs = maxFrameMs
        self.stomps = stomps
        self.shinies = shinies
        self.mask = mask
        self.maskOn = maskOn
        self.died = died
        self.won = won
        self.elapsed = elapsed
        self.wallElapsed = wallElapsed
        self.debugLabels = debugLabels
        self.combo = combo
        self.medals = medals
        self.map = map
        self.daily = daily
        self.paused = paused
        self.heroX = heroX
        self.heroXMin = heroXMin
        self.heroXMax = heroXMax
        self.worldTX = worldTX
        self.worldTY = worldTY
        self.worldTXMax = worldTXMax
        self.titleOk = titleOk
        self.roof = roof
        self.stallSec = stallSec
        self.titleHidden = titleHidden
    }

    public var line: String {
        String(
            format: "phase=%@ boot=%@ fps=%.1f samples=%d maxFrameMs=%.0f stomps=%d shinies=%d mask=%d maskOn=%d died=%d won=%d elapsed=%.1f wallElapsed=%.1f debugLabels=%d combo=%d medals=%d map=%d daily=%d paused=%d heroX=%.3f heroXMin=%.3f heroXMax=%.3f worldTX=%d worldTY=%d worldTXMax=%d titleOk=%d roof=%d stallSec=%.1f titleHidden=%d",
            phase, boot, fpsAvg, fpsSamples, maxFrameMs, stomps, shinies,
            mask ? 1 : 0, maskOn ? 1 : 0, died ? 1 : 0, won ? 1 : 0, elapsed, wallElapsed, debugLabels,
            combo, medals, map ? 1 : 0, daily ? 1 : 0, paused ? 1 : 0,
            heroX, heroXMin, heroXMax, worldTX, worldTY, worldTXMax, titleOk ? 1 : 0, roof ? 1 : 0, stallSec,
            titleHidden ? 1 : 0
        )
    }

    public static var docsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }

    public static var fileURL: URL {
        docsURL.appendingPathComponent("smoke_status.txt")
    }

    /// Append-only timer samples for CI monotonicity check.
    public static var timerLogURL: URL {
        docsURL.appendingPathComponent("smoke_timer_log.txt")
    }

    public func write() {
        try? line.write(to: Self.fileURL, atomically: true, encoding: .utf8)
        if wallElapsed > 0 {
            let sample = String(format: "%.2f\n", wallElapsed)
            if let data = sample.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: Self.timerLogURL.path),
                   let handle = try? FileHandle(forWritingTo: Self.timerLogURL) {
                    defer { try? handle.close() }
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                } else {
                    try? sample.write(to: Self.timerLogURL, atomically: true, encoding: .utf8)
                }
            }
        }
    }

    /// Exact-match ban list for on-screen SKLabel text (case-insensitive).
    public static let bannedDebugTexts: Set<String> = [
        "STOMP",
        "MASK MODE",
        "MASK MODE STOMP",
        "CHECK",
        "NECK",
        "TUNING",
        "DEBUG",
        "BANK",
        "HIT",
        "TODO",
        "PLACEHOLDER",
        "TUNING MENU",
    ]
}
