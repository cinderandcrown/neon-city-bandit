// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import Foundation

/// Deterministic autoplay director for `-SmokeAutoplay`.
/// Timeline: title → run/jump/wall → MOP stomp → Mask Mode showcase → water death → retry → exit RESULTS.
public struct SmokeBrain: Equatable, Sendable {
    public enum Act: Equatable, Sendable {
        case idle
        case start
        case play
        case showcaseMask
        case seekDeath
        case waitRetry
        case finishPush
        case done
    }

    public var act: Act = .idle
    public var tick: Int = 0
    public var diedOnce: Bool = false
    public var sawMask: Bool = false
    public var sawStomp: Bool = false
    public var titleFrames: Int = 0
    public var failWait: Int = 0
    public var stompCount: Int = 0
    public var maskShowcaseFrames: Int = 0
    public var seekDeathFrames: Int = 0
    /// Frames spent on the same world tile during mask hunt / street run (unstick).
    public var huntIdleFrames: Int = 0
    public var huntIdleTX: Int = -1
    /// Live-play stall tracker (worldTX unchanged) — harness fails after ~8s.
    public var progressIdleFrames: Int = 0
    public var progressIdleTX: Int = -1
    public var progressStallSeconds: Double = 0

    public init() {}

    /// Smoke harness handshake files in the app Documents directory.
    public static func smokeFlagExists(_ name: String) -> Bool {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return FileManager.default.fileExists(atPath: docs.appendingPathComponent(name).path)
    }

    /// Unit-test helper: create/remove harness flags in Documents.
    public static func setSmokeFlag(_ name: String, present: Bool) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let url = docs.appendingPathComponent(name)
        if present {
            try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
            try? "ok".write(to: url, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }

    public static func clearSmokeFlags() {
        for name in [
            "smoke_proceed.txt", "smoke_midrun_ok.txt", "smoke_mask_ok.txt", "smoke_mask2_ok.txt",
            "smoke_death_ok.txt",
            "smoke_show_pause.txt", "smoke_pause_ok.txt",
            "smoke_background.txt", "smoke_foreground.txt",
            "smoke_show_map.txt", "smoke_map_ok.txt", "smoke_show_daily.txt", "smoke_daily_ok.txt",
            "smoke_prefer_roof.txt", "smoke_force_mask.txt", "smoke_force_fail.txt",
            "smoke_capture_mask.txt", "smoke_snap_status.txt",
        ] {
            setSmokeFlag(name, present: false)
        }
    }

    public mutating func next(sim: Sim) -> (input: InputFrame, start: Bool, retry: Bool) {
        tick += 1
        var input = InputFrame()
        var start = false
        var retry = false

        switch sim.state.phase {
        case .title:
            // Stay on title until harness writes `smoke_proceed.txt` (after 01-title shot).
            titleFrames += 1
            let proceed = Self.smokeFlagExists("smoke_proceed.txt")
            let fallback = titleFrames >= 3600 // ~60s @ 60Hz for manual runs
            if proceed || fallback {
                start = true
                act = .play
            }
            return (input, start, retry)

        case .failed:
            failWait += 1
            let deathOk = Self.smokeFlagExists("smoke_death_ok.txt")
            // Premature splash before Mask Mode itself: bounce back fast and forget.
            // Gate on `sawMask` (not the harness file) so unit tests can pre-arm flags
            // without skipping the stomp→Mask beats.
            if !sawMask {
                if failWait >= 45 {
                    retry = true
                    failWait = 0
                    diedOnce = false
                    sawMask = false
                    maskShowcaseFrames = 0
                    act = .play
                }
                return (input, start, retry)
            }
            // Canonical death beat after Mask: hold until harness snaps 05.
            // When the smoke harness is driving (mask_ok present), NEVER auto-retry on
            // failWait — a premature splash during pause/bg used to hit 3600 (~60s),
            // retry into finishPush, and race the death wait with phase=won.
            if !diedOnce { diedOnce = true }
            let harnessDriving = Self.smokeFlagExists("smoke_mask_ok.txt")
            let manualFallback = !harnessDriving && failWait >= 3600
            if deathOk || manualFallback {
                retry = true
                failWait = 0
                act = .finishPush
            }
            return (input, start, retry)

        case .won:
            // Before death: clear .won without a full sim.retry (HeistScene pre-vault clamp
            // should prevent this; if it fires, leave .won without showing results).
            if !diedOnce {
                retry = true
                act = .play
                maskShowcaseFrames = 0
                seekDeathFrames = 0
                if sawMask {
                    act = .seekDeath
                }
                return (input, start, retry)
            }
            act = .done
            return (input, start, retry)

        case .playing:
            failWait = 0
            // Defer Mask credit until midrun still is done — early alley stomps used to
            // flip act→showcaseMask, then freeze with maskOn=0 waiting for 04 forever.
            let midrunReady = Self.smokeFlagExists("smoke_midrun_ok.txt")
                || !Self.smokeFlagExists("smoke_proceed.txt")
            if sim.state.bandit.maskMode, midrunReady {
                sawMask = true
            }

            if diedOnce {
                act = .finishPush
            } else {
                switch act {
                case .play:
                    if sawMask {
                        act = .showcaseMask
                        maskShowcaseFrames = 0
                    } else if sim.state.elapsed > 120 {
                        // Ship Mask needs combo 3 on Neon Docks — give the hunt time.
                        act = .seekDeath
                    }
                case .showcaseMask:
                    maskShowcaseFrames += 1
                    // Hold until harness snaps 04 + 04b (second Mask) AND finishes pause/bg.
                    // Seeking death right after mask_ok races pause-resume (phase=failed
                    // while the script still waits for phase=playing).
                    // Do NOT abandon on a frame budget while smoke_proceed is set — the CI
                    // harness needs mask-off → 04b before seekDeath, and 3600 frames (~60s)
                    // expires long before 04 is even snapped.
                    let maskOk = Self.smokeFlagExists("smoke_mask_ok.txt")
                    let mask2Ok = Self.smokeFlagExists("smoke_mask2_ok.txt")
                    let pauseBgDone = Self.smokeFlagExists("smoke_foreground.txt")
                    let harnessDriving = Self.smokeFlagExists("smoke_proceed.txt")
                    if maskOk && mask2Ok && pauseBgDone {
                        act = .seekDeath
                    } else if !harnessDriving, maskShowcaseFrames >= 3600 {
                        act = .seekDeath
                    }
                default:
                    break
                }
            }

            input = decidePlaying(sim: sim)
            return (input, start, retry)
        }
    }

    public mutating func noteStomp() {
        sawStomp = true
        stompCount += 1
    }

    private mutating func decidePlaying(sim: Sim) -> InputFrame {
        let b = sim.state.bandit
        let tile = sim.tuning.tileSize
        let tx = Int(floor(b.position.x / tile))
        let ty = Int(floor(b.position.y / tile))

        let midrunOk = Self.smokeFlagExists("smoke_midrun_ok.txt")
        let captureMask = Self.smokeFlagExists("smoke_capture_mask.txt")
            || Self.smokeFlagExists("smoke_force_mask.txt")

        // No exit soft-hold: HeistScene clamps pre-death runs short of the vault.
        // Soft-holding at EXIT skipped the MOP pack after rooftop (stomps=0 forever).

        // Beat 1 — run the teaching runway forward until midrun still lands.
        if !midrunOk, sim.state.elapsed < 90, act != .seekDeath, act != .finishPush {
            return forwardRunInput(sim: sim, tx: tx, ty: ty, allowMask: false)
        }

        // Track live-play stalls for the harness 8s no-progress gate.
        // Stomp attempts on the same tile are not a soft-lock — keep the gate quiet.
        if let mop = nearestMop(sim: sim), abs(mop.position.x - b.position.x) < tile * 5 {
            progressIdleTX = tx
            progressIdleFrames = 0
            progressStallSeconds = 0
        } else {
            noteProgress(tx: tx, dt: sim.tuning.dt, playing: true)
        }

        // Past the vault lip / right wall with no death yet — drop into seekDeath so
        // the 8s no-progress gate doesn't kill a finished runway.
        let exitX = sim.map.findFirst(.exit)?.0 ?? (sim.map.width - 2)
        if act != .finishPush, !diedOnce, tx >= exitX - 1, progressStallSeconds > 2.5 {
            act = .seekDeath
            return seekDeathInput(sim: sim, tx: tx, ty: ty)
        }

        // Harness rooftop clip: climb while prefer_roof is set (even during showcaseMask).
        // After ~4s on the same latch column, bail to street so the video isn't dead air.
        // Never climb past living street MOPs — stomp first so CI chain can land.
        if Self.smokeFlagExists("smoke_prefer_roof.txt"),
           act != .seekDeath, act != .finishPush {
            if let mop = nearestMop(sim: sim), mop.position.x - b.position.x < tile * 8 {
                return forwardRunInput(sim: sim, tx: tx, ty: ty, allowMask: false)
            }
            if progressStallSeconds > 4.0 {
                return forwardRunInput(sim: sim, tx: tx, ty: ty, allowMask: false)
            }
            return preferRoofClimbInput(sim: sim, tx: tx, ty: ty)
        }

        if act == .seekDeath {
            seekDeathFrames += 1
            return seekDeathInput(sim: sim, tx: tx, ty: ty)
        }

        if act == .showcaseMask {
            let maskOk = Self.smokeFlagExists("smoke_mask_ok.txt")
            let mask2Ok = Self.smokeFlagExists("smoke_mask2_ok.txt")
            // Always run forward during Mask showcase — never moonwalk left.
            if !b.maskMode, (!maskOk || !mask2Ok) {
                return forwardRunInput(sim: sim, tx: tx, ty: ty, allowMask: captureMask)
            }
            return forwardRunInput(sim: sim, tx: tx, ty: ty, allowMask: false)
        }

        if act == .finishPush {
            return finishPushInput(sim: sim, tx: tx, ty: ty)
        }

        // Beat 2 — keep stomping forward until Mask capture is armed, then spend Mask.
        return forwardRunInput(sim: sim, tx: tx, ty: ty, allowMask: captureMask)
    }

    /// Near-exit soft hold only — never reverse (auto-runner faces right).
    private func steerFromExit(_ input: InputFrame, sim: Sim, tx: Int) -> InputFrame {
        guard act != .finishPush else { return input }
        guard let exitX = sim.map.findFirst(.exit)?.0 else { return input }
        if tx >= exitX - 8 {
            var held = input
            held.moveX = max(0.15, min(input.moveX, 0.35))
            return held
        }
        return input
    }

    /// Forward-biased auto-runner: jump gaps, pounce MOPs, optional Mask spend.
    /// Pre-midrun soft-holds on the teaching runway so the MOP pack stays ahead for stomp-chain.
    private func forwardRunInput(sim: Sim, tx: Int, ty: Int, allowMask: Bool) -> InputFrame {
        let b = sim.state.bandit
        let tile = sim.tuning.tileSize
        let halfH = 14.0
        let streetY = sim.map.findFirst(.start).map { Double($0.1) * tile } ?? b.position.y
        let elevated = b.position.y > streetY + tile * 1.0 || standingOnOneWay(sim: sim, halfH: halfH)
        let midrunOk = Self.smokeFlagExists("smoke_midrun_ok.txt")

        // Drop mid ledges / one-ways so Mask re-entry and stomps happen on the street deck.
        if elevated {
            var moveX: Double = 1.0
            if standingOnOneWay(sim: sim, halfH: halfH), b.onGround {
                return InputFrame(moveX: moveX, moveY: -1, jumpPressed: false, jumpHeld: false)
            }
            if !b.onGround {
                return InputFrame(moveX: moveX, moveY: -1, pouncePressed: !b.flopping && b.velocity.y < 20)
            }
            // Walk toward a ledge (prefer right) then fall.
            if floorSupport(sim: sim, tx: tx + 1, ty: ty) {
                moveX = 1.0
            } else if floorSupport(sim: sim, tx: tx - 1, ty: ty) {
                moveX = 1.0 // still forward; don't moonwalk off left
            }
            return InputFrame(moveX: moveX, moveY: -1, jumpPressed: false, jumpHeld: false)
        }

        // Teaching runway: hold before the first MOP so midrun stills snap with stomps=0
        // and the whole street pack remains ahead for the +3 stomp-chain gate.
        if !midrunOk, act != .seekDeath, act != .finishPush {
            let firstMopX = sim.map.findAll(.mopSpawn).map(\.0).min() ?? 28
            let rightCap = max(12, firstMopX - 4)
            let leftCap = 6
            var moveX: Double = 1.0
            var jumpPressed = false
            var jumpHeld = false
            if tx >= rightCap {
                moveX = tx > rightCap + 1 ? -0.55 : 0.2
            } else if tx <= leftCap {
                moveX = 1.0
            }
            if gapAhead(sim: sim, tx: tx, ty: ty) || hazardAhead(sim: sim, tx: tx, ty: ty, reach: 2) {
                jumpPressed = b.onGround || b.coyote > 0
                jumpHeld = true
                moveX = max(moveX, 0.85)
            }
            return InputFrame(moveX: moveX, jumpPressed: jumpPressed, jumpHeld: jumpHeld || jumpPressed)
        }

        var moveX: Double = 1.0
        var jumpPressed = false
        var jumpHeld = false
        var pouncePressed = false
        var dashPressed = false
        var maskPressed = false

        if gapAhead(sim: sim, tx: tx, ty: ty) || hazardAhead(sim: sim, tx: tx, ty: ty, reach: 3) {
            jumpPressed = b.onGround || b.coyote > 0
            jumpHeld = true
            if !b.onGround, !b.pouncing, !b.flopping, b.velocity.y < 30 {
                pouncePressed = true
            }
        }

        if let mop = nearestMop(sim: sim) {
            let dx = mop.position.x - b.position.x
            // Ease into the stomp window — full-speed overshoot used to burn the pack.
            if dx < -tile * 0.4, dx > -tile * 5.0 {
                moveX = -0.85
            } else if dx >= -tile * 0.4, dx < tile * 2.2 {
                moveX = 0.45
            } else if dx >= tile * 2.2, dx < tile * 7.0 {
                moveX = 0.85
            }
            // Stomp window: slightly behind → ahead. Always pounce while falling onto a mop.
            if dx > -tile * 1.5, dx < tile * 6.0 {
                if b.onGround || b.coyote > 0 {
                    jumpPressed = true
                    jumpHeld = true
                } else if !b.pouncing, !b.flopping, b.velocity.y < 80 {
                    pouncePressed = true
                }
            }
        }

        if b.dashCooldown <= 0, b.onGround, tick % 180 == 0 {
            dashPressed = true
        }

        if allowMask, !b.maskMode, b.maskCharges > 0, tick % 8 == 0 {
            maskPressed = true
        }

        if b.onWallRight || b.onWallLeft, !b.onGround {
            jumpPressed = true
            jumpHeld = true
            moveX = 1.0
        }

        // Stay off the vault until the death beat — premature won→retry hitch spikes maxFrameMs.
        // Keep the window tight so late street MOPs (exit-4) stay stompable.
        if midrunOk, !diedOnce, act != .seekDeath, act != .finishPush {
            let exitX = sim.map.findFirst(.exit)?.0 ?? (sim.map.width - 2)
            if tx >= exitX - 2 {
                moveX = -1.0
                jumpPressed = false
                jumpHeld = false
                pouncePressed = false
            } else if tx >= exitX - 5 {
                moveX = min(moveX, 0.35)
            }
        }

        return InputFrame(
            moveX: moveX,
            jumpPressed: jumpPressed,
            jumpHeld: jumpHeld || jumpPressed,
            pouncePressed: pouncePressed,
            dashPressed: dashPressed,
            maskPressed: maskPressed
        )
    }

    /// Clear Neon Docks after the death beat: stay on the street deck to EXIT.
    private func finishPushInput(sim: Sim, tx: Int, ty: Int) -> InputFrame {
        let b = sim.state.bandit
        let tile = sim.tuning.tileSize
        let exitTile = sim.map.findFirst(.exit)
        let exit = exitTile.map { sim.map.worldCenter(ofX: $0.0, y: $0.1, tileSize: tile) }
        let targetX = exit?.x ?? (Double(sim.map.width - 2) * tile)
        let targetY = exit?.y ?? b.position.y
        let dx = targetX - b.position.x
        let streetY = sim.map.findFirst(.start).map { Double($0.1) * tile } ?? targetY

        // If we overshot onto a roof after the high jump buff, drop back to street.
        if b.position.y > streetY + tile * 0.45 {
            let edgeR = !sim.map.isSolid(sim.map.tile(atX: tx + 1, y: ty - 1))
                || sim.map.tile(atX: tx + 1, y: ty - 1) == .oneWay
            if edgeR || !b.onGround {
                return InputFrame(moveX: 1, moveY: -1)
            }
            // Walk toward the nearest ledge (prefer right / exit).
            return InputFrame(moveX: 1, moveY: -1, jumpPressed: false, jumpHeld: false)
        }

        // Hard right on the main deck — auto-runner never turns around for the vault push.
        var moveX: Double = 1.0
        var jumpPressed = false
        var jumpHeld = false
        var pouncePressed = false
        let exitX = exitTile?.0 ?? (sim.map.width - 2)

        // Overshot the vault tile while airborne — walk back onto E (win needs feet on .exit).
        if tx > exitX {
            return InputFrame(
                moveX: -1.0,
                jumpPressed: false,
                jumpHeld: false,
                pouncePressed: false
            )
        }
        // Final approach: no hop — jumping the end canal used to clear past E without winning.
        if tx >= exitX - 3 {
            return InputFrame(
                moveX: 1.0,
                jumpPressed: false,
                jumpHeld: false,
                pouncePressed: false
            )
        }
        _ = dx
        _ = targetY

        let gapNear = gapAhead(sim: sim, tx: tx, ty: ty) || gapWithin(sim: sim, tx: tx, ty: ty, reach: 5)
        let hazard = hazardAhead(sim: sim, tx: tx, ty: ty, reach: 6)
        let solidAhead = sim.map.isSolid(sim.map.tile(atX: tx + 1, y: ty))

        // Hop crates / canal pit. Full hold through apex so we clear water, then cut so we stay low.
        if solidAhead || gapNear || hazard {
            jumpPressed = b.onGround || b.coyote > 0
            jumpHeld = !b.onGround && b.velocity.y > -2
            moveX = 1.0
        }
        if b.onWallLeft || b.onWallRight, !b.onGround {
            jumpPressed = true
            jumpHeld = true
            moveX = 1.0
        }

        // After the death beat, do NOT stomp-farm — bounce loops stall the EXIT run.
        // Hop over same-deck MOPs; ignore elevated ones.
        if let mop = nearestMop(sim: sim) {
            let mdx = mop.position.x - b.position.x
            let mdy = mop.position.y - b.position.y
            if mdx > 0, mdx < tile * 2.8, abs(mdy) < tile * 1.0, b.onGround {
                jumpPressed = true
                jumpHeld = false // short hop over, then keep running
            } else if mdy > tile * 0.8 {
                jumpPressed = false
                jumpHeld = false
            }
            _ = mdx
        }
        pouncePressed = false

        return InputFrame(
            moveX: moveX,
            jumpPressed: jumpPressed,
            jumpHeld: jumpHeld,
            pouncePressed: pouncePressed
        )
    }

    private func showcaseRunInput(sim: Sim, tx: Int, ty: Int, midrunOk: Bool) -> InputFrame {
        let b = sim.state.bandit
        let tile = sim.tuning.tileSize
        // Midrun beat: keep moving so the screenshot shows a running ship build (no wall-idle).
        // Cycle walk → run → hop every ~3.5s for sheet coverage.
        let phase = tick % 210
        var moveX: Double
        var jumpPressed = false
        var jumpHeld = false
        var pouncePressed = false
        var dashPressed = false
        var maskPressed = false
        var grabPressed = false
        // Explicit L/R reversals + brief releases so the smoke clip proves facing/stop.
        if phase < 50 {
            moveX = 1.0
        } else if phase < 70 {
            moveX = 0 // release
        } else if phase < 120 {
            moveX = -1.0
        } else if phase < 140 {
            moveX = 0 // release
        } else if phase < 180 {
            moveX = 1.0
            if b.onGround, phase == 150 || phase == 170 {
                jumpPressed = true
                jumpHeld = true
            } else if !b.onGround {
                jumpHeld = b.velocity.y > 0
            }
        } else {
            moveX = 0.85
            if b.onGround, phase == 190 {
                jumpPressed = true
                jumpHeld = true
            } else if !b.onGround {
                jumpHeld = b.velocity.y > 0
            }
        }

        // Pre-midrun: patrol the neon corridor (not the spawn lip) so midrun stills see
        // storefront magenta; leave MOPs alive; never race past the canal to EXIT.
        if !midrunOk {
            // Stay on the safe teaching runway (before first pit / MOP pack).
            let canalX = sim.map.findAll(.water).map(\.0).min() ?? 45
            let leftCap = 8
            let rightCap = max(leftCap + 8, min(canalX - 5, 26))
            if tx >= rightCap {
                moveX = -0.55
                jumpPressed = false
                jumpHeld = false
            } else if tx <= leftCap {
                moveX = 1.0
                jumpPressed = false
                jumpHeld = false
            } else {
                // Auto-runner showcase: keep pressing right so midrun stills show motion.
                moveX = 1.0
            }
        } else if let mop = nearestMop(sim: sim) {
            let dx = mop.position.x - b.position.x
            // Hunt: jump then pounce to stomp.
            if abs(dx) < tile * 5.0 {
                moveX = dx >= 0 ? 1.0 : -0.35
                if b.onGround || b.coyote > 0 {
                    jumpPressed = true
                    jumpHeld = true
                } else if !b.pouncing, !b.flopping, b.velocity.y < 40 {
                    pouncePressed = true
                }
            }
        }

        // Always jump gaps / pits — never walk into water.
        if gapAhead(sim: sim, tx: tx, ty: ty) || hazardAhead(sim: sim, tx: tx, ty: ty, reach: 3) {
            jumpPressed = b.onGround || b.coyote > 0
            jumpHeld = true
            moveX = max(moveX, 1.0)
            if !b.onGround, !b.pouncing, !b.flopping, b.velocity.y < 20 {
                pouncePressed = true
            }
        }
        if tx <= 5 {
            moveX = max(moveX, 0.9)
        }
        // Before midrun still: never climb latch towers — street magenta needs a ground camera.
        let latchNear = sim.map.tile(atX: tx, y: ty) == .latch
            || sim.map.tile(atX: tx + 1, y: ty) == .latch
            || sim.map.tile(atX: tx - 1, y: ty) == .latch
            || sim.map.tile(atX: tx, y: ty + 1) == .latch
        if !midrunOk, latchNear || ((b.onWallLeft || b.onWallRight) && latchNear) {
            let latchX = sim.map.findFirst(.latch).map(\.0) ?? (tx + 10)
            moveX = tx <= latchX ? -0.85 : 0.85
            return InputFrame(moveX: moveX, jumpPressed: false, jumpHeld: false)
        }
        if b.onWallLeft || b.onWallRight, !b.onGround {
            jumpPressed = tick % 20 == 0
            jumpHeld = true
            moveX = b.onWallRight ? -0.55 : 0.85
        }

        // First ~30s street beat: cycle the full right-thumb cluster for the smoke clip.
        let elapsed = sim.state.elapsed
        if elapsed < 32, act != .seekDeath, act != .finishPush {
            // DASH burst (~8s) — cooldown ring + i-frames through a MOP lane.
            if b.dashCooldown <= 0, b.onGround, phase == 100 || (elapsed > 7.5 && elapsed < 8.2 && tick % 8 == 0) {
                dashPressed = true
            }
            // Double jump (~12s): hop then mid-air JUMP again.
            if !b.onGround, b.airJumpsRemaining > 0, b.coyote <= 0,
               elapsed > 11.5, elapsed < 13.5, tick % 18 == 0 {
                jumpPressed = true
                jumpHeld = true
            }
            // POUNCE (~15s) while airborn near a MOP, else a short hop-pounce.
            if elapsed > 14.5, elapsed < 17.0, !b.pouncing, !b.flopping, tick % 22 == 0 {
                if !b.onGround {
                    pouncePressed = true
                } else {
                    jumpPressed = true
                    jumpHeld = true
                }
            }
            // GRAB when loot/vent/door is in reach (~18–22s).
            if b.interactTarget != .none, elapsed > 17.5, elapsed < 22.5, tick % 14 == 0 {
                grabPressed = true
            }
            // MASK button spend once the meter is full (fun-pass: stomps grant charges).
            if !b.maskMode, b.maskCharges > 0, tick % 12 == 0 {
                maskPressed = true
            }
        }

        return steerFromExit(
            InputFrame(
                moveX: moveX,
                jumpPressed: jumpPressed,
                jumpHeld: jumpHeld || jumpPressed,
                pouncePressed: pouncePressed,
                dashPressed: dashPressed,
                maskPressed: maskPressed,
                grabPressed: grabPressed
            ),
            sim: sim,
            tx: tx
        )
    }

    /// Drop from rooftops / mid ledges, then stomp-hunt street MOPs for Mask re-entry.
    private mutating func maskReentryHuntInput(sim: Sim, tx: Int, ty: Int) -> InputFrame {
        let b = sim.state.bandit
        let tile = sim.tuning.tileSize
        let halfH = 14.0
        let streetY = sim.map.findFirst(.start).map { Double($0.1) * tile } ?? b.position.y
        let feetY = b.position.y - halfH
        let elevated = feetY > streetY + tile * 0.35
        let onOneWay = standingOnOneWay(sim: sim, halfH: halfH)

        // Mask spend is gated by smoke_capture_mask / forwardRunInput — keep hunting stomps.
        let allowMask = Self.smokeFlagExists("smoke_capture_mask.txt")
            || Self.smokeFlagExists("smoke_force_mask.txt")
        if allowMask, !b.maskMode, b.maskCharges > 0 {
            return InputFrame(moveX: 1, jumpHeld: false, maskPressed: true)
        }

        // Never walk into pits while hunting.
        if gapAhead(sim: sim, tx: tx, ty: ty) || hazardAhead(sim: sim, tx: tx, ty: ty, reach: 3) {
            return InputFrame(
                moveX: 1,
                jumpPressed: b.onGround || b.coyote > 0,
                jumpHeld: true,
                pouncePressed: !b.onGround && !b.pouncing && !b.flopping
            )
        }

        // Prefer street-deck MOPs for the second Mask (opening pack / patrols).
        let streetMops = sim.state.mops.filter {
            $0.alive && abs($0.position.y - streetY) < tile * 2.5
        }
        let mop = streetMops.min(by: {
            $0.position.distance(to: b.position) < $1.position.distance(to: b.position)
        }) ?? nearestMop(sim: sim)

        // Still perched after the rooftop beat — drop one-ways / walk off solid ledges.
        // CI failure mode: Bandit stuck on latch-tower --- / short ==== above street MOPs.
        if elevated || onOneWay {
            var moveX: Double = 1.0
            if b.onWallRight { moveX = -1.0 }
            else if b.onWallLeft { moveX = 1.0 }
            else if let mop {
                let dx = mop.position.x - b.position.x
                // Prefer the nearer open ledge when a wall hems us in on a one-way.
                if floorSupport(sim: sim, tx: tx + 1, ty: ty) && !floorSupport(sim: sim, tx: tx - 1, ty: ty) {
                    moveX = -1.0
                } else if !floorSupport(sim: sim, tx: tx + 1, ty: ty) {
                    moveX = 1.0
                } else if dx < -tile {
                    moveX = -0.85
                }
            } else if !floorSupport(sim: sim, tx: tx + 1, ty: ty) {
                moveX = 1.0
            } else if !floorSupport(sim: sim, tx: tx - 1, ty: ty) {
                moveX = -1.0
            }

            // Against a latch wall on a one-way: hold down + nudge (no jump) so Sim dropThrough fires.
            if onOneWay, b.onGround {
                return InputFrame(moveX: moveX, moveY: -1, jumpPressed: false, jumpHeld: false)
            }
            if !b.onGround {
                return InputFrame(moveX: moveX, moveY: -1, pouncePressed: !b.flopping)
            }
            // Solid mid ledge: walk toward open air; hop only when both sides are blocked.
            let blockedBoth = floorSupport(sim: sim, tx: tx + 1, ty: ty)
                && floorSupport(sim: sim, tx: tx - 1, ty: ty)
                && (b.onWallLeft || b.onWallRight
                    || sim.map.isSolid(sim.map.tile(atX: tx + 1, y: ty))
                    || sim.map.isSolid(sim.map.tile(atX: tx - 1, y: ty)))
            if blockedBoth {
                return InputFrame(moveX: moveX, moveY: -1, jumpPressed: true, jumpHeld: true)
            }
            return InputFrame(moveX: moveX, moveY: -1, jumpPressed: false, jumpHeld: false)
        }

        let exitX = sim.map.findFirst(.exit)?.0 ?? (sim.map.width - 2)
        let nearExit = tx >= exitX - 15

        // Unstick: same tile + low speed for ~0.75s → hop away from EXIT (never into it).
        if tx == huntIdleTX, abs(b.velocity.x) < 4 {
            huntIdleFrames += 1
        } else {
            huntIdleTX = tx
            huntIdleFrames = 0
        }
        if huntIdleFrames > 45 {
            huntIdleFrames = 0
            let away: Double = nearExit ? -1.0 : 1.0
            return InputFrame(
                moveX: away,
                jumpPressed: b.onGround || b.coyote > 0,
                jumpHeld: true,
                pouncePressed: !b.onGround && !b.flopping
            )
        }

        // Camped on the EXIT lip with no stomps — retreat to mid-docks mop packs.
        if nearExit || progressStallSeconds > 3.5 {
            return InputFrame(
                moveX: -1.0,
                jumpPressed: (b.onGround || b.coyote > 0) && (gapAhead(sim: sim, tx: tx, ty: ty) || tick % 18 == 0),
                jumpHeld: !b.onGround && b.velocity.y > 0,
                pouncePressed: !b.onGround && !b.flopping && b.velocity.y < 0
            )
        }

        guard let mop else {
            // No living street MOP — patrol mid docks (never sprint into EXIT).
            let mid = max(28, min(55, exitX / 2))
            let moveX: Double = tx > mid ? -0.95 : 1.0
            return InputFrame(
                moveX: moveX,
                jumpPressed: (b.onGround || b.coyote > 0) && (gapAhead(sim: sim, tx: tx, ty: ty) || tick % 24 == 0),
                jumpHeld: !b.onGround && b.velocity.y > 0
            )
        }
        let dx = mop.position.x - b.position.x
        // Chase hard toward the mop (left or right) — mild -0.55 left used to strand past packs.
        var moveX: Double
        if dx < -tile * 1.0 {
            moveX = -1.0
        } else if dx > tile * 1.0 {
            moveX = 1.0
        } else {
            moveX = dx >= 0 ? 0.85 : -0.85
        }
        var jumpPressed = false
        var jumpHeld = false
        var pouncePressed = false
        if b.onGround || b.coyote > 0 {
            if abs(dx) < tile * 5.5 { jumpPressed = true; jumpHeld = true }
        } else if b.velocity.y > 0 {
            jumpHeld = true
        } else if !b.flopping {
            pouncePressed = true
            jumpHeld = true
        }
        if tx <= 5 { moveX = max(moveX, 0.85) }
        return InputFrame(
            moveX: moveX,
            jumpPressed: jumpPressed,
            jumpHeld: jumpHeld || jumpPressed,
            pouncePressed: pouncePressed
        )
    }

    private func standingOnOneWay(sim: Sim, halfH: Double) -> Bool {
        let b = sim.state.bandit
        let tile = sim.tuning.tileSize
        let feet = b.position.y - halfH - 1
        let tx = Int(floor(b.position.x / tile))
        let ty = Int(floor(feet / tile))
        if sim.map.tile(atX: tx, y: ty) == .oneWay { return true }
        // Foot sample a hair lower for tile-seam stands — do NOT scan horizontal
        // neighbors (canal lip one-ways beside street solids false-trigger "elevated").
        let tyLo = Int(floor((feet - 2) / tile))
        return sim.map.tile(atX: tx, y: tyLo) == .oneWay
    }

    /// True when the cell under (tx, ty-1) can be stood on (solid or one-way).
    private func floorSupport(sim: Sim, tx: Int, ty: Int) -> Bool {
        let below = sim.map.tile(atX: tx, y: ty - 1)
        return sim.map.isStandable(below)
    }

    private mutating func noteProgress(tx: Int, dt: Double, playing: Bool) {
        guard playing else { return }
        if tx == progressIdleTX {
            progressIdleFrames += 1
            progressStallSeconds = Double(progressIdleFrames) * dt
        } else {
            progressIdleTX = tx
            progressIdleFrames = 0
            progressStallSeconds = 0
        }
    }

    /// Drive toward latch / one-way climb for the rooftop-route smoke still + clip.
    private func preferRoofClimbInput(sim: Sim, tx: Int, ty: Int) -> InputFrame {
        let b = sim.state.bandit
        let tile = sim.tuning.tileSize
        let streetY = sim.map.findFirst(.start).map { Double($0.1) * tile } ?? b.position.y
        // Already high enough — strafe right along the roof deck.
        if b.position.y > streetY + tile * 2.2 {
            var jumpHeld = !b.onGround && b.velocity.y > 0
            var jumpPressed = false
            if gapAhead(sim: sim, tx: tx, ty: ty) {
                jumpPressed = b.onGround || b.coyote > 0
                jumpHeld = true
            }
            return InputFrame(moveX: 1.0, jumpPressed: jumpPressed, jumpHeld: jumpHeld)
        }
        let above = sim.map.tile(atX: tx, y: ty + 1)
        let latchNear = sim.map.tile(atX: tx, y: ty) == .latch
            || sim.map.tile(atX: tx + 1, y: ty) == .latch
            || sim.map.tile(atX: tx - 1, y: ty) == .latch
            || sim.map.tile(atX: tx + 1, y: ty + 1) == .latch
        let oneWayAbove = above == .oneWay
            || sim.map.tile(atX: tx, y: ty + 2) == .oneWay
            || sim.map.tile(atX: tx + 1, y: ty + 1) == .oneWay
        var moveX: Double = 1.0
        var jumpPressed = false
        var jumpHeld = false
        if latchNear || oneWayAbove || b.onWallLeft || b.onWallRight {
            jumpPressed = b.onGround || b.coyote > 0 || b.onWallLeft || b.onWallRight || tick % 12 == 0
            jumpHeld = true
            moveX = b.onWallRight ? -0.25 : 0.75
        } else if b.onGround || b.coyote > 0 {
            // Climb the nearest floating deck ahead — never race past the street MOP pack to EXIT.
            let latchX = sim.map.findFirst(.latch).map(\.0)
            let roofTarget = latchX ?? min(tx + 8, (sim.map.findFirst(.exit)?.0 ?? tx + 12) - 12)
            jumpPressed = tick % 18 == 0 || sim.map.isSolid(sim.map.tile(atX: tx + 1, y: ty))
            jumpHeld = jumpPressed || (!b.onGround && b.velocity.y > 0)
            if tx < roofTarget { moveX = 1.0 }
            else { moveX = 0.55 }
        } else {
            jumpHeld = b.velocity.y > 0
            if b.velocity.y < 0, !b.flopping {
                return InputFrame(moveX: 0.85, jumpHeld: true, pouncePressed: false)
            }
        }
        if tx <= 5 { moveX = max(moveX, 0.9) }
        // Rooftop clip must not walk into EXIT (latch is mid-map; EXIT is far right).
        return steerFromExit(
            InputFrame(moveX: moveX, jumpPressed: jumpPressed, jumpHeld: jumpHeld || jumpPressed),
            sim: sim,
            tx: tx
        )
    }

    private func seekDeathInput(sim: Sim, tx: Int, ty: Int) -> InputFrame {
        let b = sim.state.bandit
        let tile = sim.tuning.tileSize
        let halfH = 14.0
        let streetY = sim.map.findFirst(.start).map { Double($0.1) * tile } ?? b.position.y
        let feetY = b.position.y - halfH
        let elevated = feetY > streetY + tile * 0.35 || standingOnOneWay(sim: sim, halfH: halfH)
        // Get down to the street first — drop one-ways / walk off solid mid ledges.
        if elevated {
            var moveX: Double = 1.0
            if b.onWallRight { moveX = -1.0 }
            else if b.onWallLeft { moveX = 1.0 }
            else if !floorSupport(sim: sim, tx: tx + 1, ty: ty) {
                moveX = 1.0
            } else if !floorSupport(sim: sim, tx: tx - 1, ty: ty) {
                moveX = -1.0
            }
            if standingOnOneWay(sim: sim, halfH: halfH), b.onGround {
                return InputFrame(moveX: moveX, moveY: -1, jumpPressed: false, jumpHeld: false)
            }
            if !b.onGround {
                return InputFrame(moveX: moveX, moveY: -1, pouncePressed: !b.flopping)
            }
            if b.onWallLeft || b.onWallRight {
                return InputFrame(moveX: moveX, moveY: -1, jumpPressed: true, jumpHeld: true)
            }
            return InputFrame(moveX: moveX, moveY: -1, jumpPressed: false, jumpHeld: false)
        }
        // Street: bee-line into the canal pit center and walk off (no jump).
        // Aim past the left water column — targeting the tile edge made toward flip
        // at the lip and oscillate forever (CI death hang at heroX≈canal).
        let waters = sim.map.findAll(.water)
        let waterX: Double
        if waters.isEmpty {
            waterX = Double(tx + 20) * tile
        } else {
            let avgX = waters.map { Double($0.0) }.reduce(0, +) / Double(waters.count)
            waterX = (avgX + 0.5) * tile
        }
        let toward = waterX >= b.position.x ? 1.0 : -1.0
        let step = toward > 0 ? 1 : -1
        let underFoot = sim.map.tile(atX: tx, y: Int(floor((b.position.y - halfH - 1) / tile)))
        let under = sim.map.tile(atX: tx + step, y: ty - 1)
        let ahead = sim.map.tile(atX: tx + step, y: ty)
        let underHere = sim.map.tile(atX: tx, y: ty - 1)
        // Open canal / empty floor underfoot or ahead — commit into the pit.
        let overGap = underHere == .empty || underHere == .water || underHere == .spike || underHere == .oneWay
        let lipIsHazard = overGap
            || under == .water || under == .spike || under == .empty || under == .oneWay
            || ahead == .water || ahead == .spike || ahead == .empty
            || underFoot == .oneWay
            || sim.map.tile(atX: tx + step, y: ty - 2) == .water
        if underFoot == .oneWay || overGap {
            return InputFrame(moveX: toward, moveY: -1)
        }
        if lipIsHazard || seekDeathFrames > 180 {
            return InputFrame(moveX: toward, moveY: under == .oneWay ? -1 : 0)
        }
        if b.onWallRight || b.onWallLeft || sim.map.isSolid(ahead) {
            return InputFrame(
                moveX: toward,
                jumpPressed: b.onGround || b.coyote > 0,
                jumpHeld: true
            )
        }
        return InputFrame(moveX: toward)
    }

    private func nearestMop(sim: Sim) -> MopEnemy? {
        let b = sim.state.bandit.position
        let tile = sim.tuning.tileSize
        let alive = sim.state.mops.filter(\.alive)
        // Prefer same-deck targets (small |dy|) so hunt doesn't climb away from the opening pack.
        let sameDeck = alive.filter { abs($0.position.y - b.y) < tile * 1.6 }
        let pool = sameDeck.isEmpty ? alive : sameDeck
        return pool.min(by: { $0.position.distance(to: b) < $1.position.distance(to: b) })
    }

    private func nearestHazardX(sim: Sim) -> Int? {
        var best: Int?
        var bestDist = Int.max
        let bx = Int(floor(sim.state.bandit.position.x / sim.tuning.tileSize))
        for y in 0..<sim.map.height {
            for x in 0..<sim.map.width {
                let t = sim.map.tile(atX: x, y: y)
                if t == .water || t == .spike {
                    let d = abs(x - bx)
                    if d < bestDist {
                        bestDist = d
                        best = x
                    }
                }
            }
        }
        return best
    }

    private func hazardAhead(sim: Sim, tx: Int, ty: Int, reach: Int) -> Bool {
        for d in 1...reach {
            let here = sim.map.tile(atX: tx + d, y: ty)
            let under = sim.map.tile(atX: tx + d, y: ty - 1)
            if here == .water || here == .spike || under == .water || under == .spike { return true }
        }
        return false
    }

    private func gapAhead(sim: Sim, tx: Int, ty: Int) -> Bool {
        let under1 = sim.map.tile(atX: tx + 1, y: ty - 1)
        let under2 = sim.map.tile(atX: tx + 2, y: ty - 1)
        let solid1 = sim.map.isSolid(under1)
        let solid2 = sim.map.isSolid(under2)
        return !solid1 && (solid2 || under1 == .water || under1 == .empty)
    }

    /// True when a non-solid floor cell exists within `reach` tiles ahead (canal approach).
    private func gapWithin(sim: Sim, tx: Int, ty: Int, reach: Int) -> Bool {
        for d in 1...reach {
            let under = sim.map.tile(atX: tx + d, y: ty - 1)
            if !sim.map.isSolid(under) || under == .water { return true }
        }
        return false
    }
}
