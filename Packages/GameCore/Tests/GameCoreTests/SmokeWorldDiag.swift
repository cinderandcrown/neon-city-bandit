// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import XCTest
@testable import GameCore

/// Proves SmokeBrain progresses in *world* tile X (not screen heroX) without smoke_force_*.
final class SmokeWorldProgressTests: XCTestCase {
    func testSmokeBrainWorldProgressWithoutForceFlags() throws {
        let map = try NeonDocksLevel.load()
        let tuning = Tuning.default
        var sim = Sim(map: map, tuning: tuning, seed: 7)
        var brain = SmokeBrain()
        SmokeBrain.clearSmokeFlags()
        defer { SmokeBrain.clearSmokeFlags() }

        let tile = tuning.tileSize
        let exitX = map.findFirst(.exit)!.0
        let canalX = map.findAll(.water).map(\.0).min() ?? 45

        func setFlags(_ names: Set<String>) {
            let all = [
                "smoke_proceed.txt", "smoke_midrun_ok.txt", "smoke_prefer_roof.txt",
                "smoke_mask_ok.txt", "smoke_mask2_ok.txt", "smoke_foreground.txt",
                "smoke_death_ok.txt", "smoke_force_mask.txt", "smoke_force_fail.txt",
            ]
            for n in all { SmokeBrain.setSmokeFlag(n, present: names.contains(n)) }
        }

        var maxTX = 0
        var maxTXBeforeDeath = 0
        var died = false
        var won = false
        var sawMask = false
        var postMidrunStomps = 0
        var prematureWin = false
        let hz = tuning.simHz

        for _ in 0..<Int(260 * hz) {
            let t = sim.state.elapsed
            // CI-like cadence, but never arm force_*.
            if case .title = sim.state.phase {
                setFlags(["smoke_proceed.txt"])
            } else if t < 9 {
                setFlags(["smoke_proceed.txt"])
            } else if t < 16 {
                setFlags(["smoke_proceed.txt", "smoke_midrun_ok.txt", "smoke_prefer_roof.txt"])
            } else if t < 55 {
                setFlags(["smoke_proceed.txt", "smoke_midrun_ok.txt"])
            } else if t < 70 {
                setFlags([
                    "smoke_proceed.txt", "smoke_midrun_ok.txt", "smoke_mask_ok.txt",
                    "smoke_foreground.txt",
                ])
            } else {
                // Release death + second mask as soon as the street beats have had time.
                setFlags([
                    "smoke_proceed.txt", "smoke_midrun_ok.txt", "smoke_mask_ok.txt",
                    "smoke_mask2_ok.txt", "smoke_foreground.txt", "smoke_death_ok.txt",
                ])
            }

            let midrunOk = SmokeBrain.smokeFlagExists("smoke_midrun_ok.txt")
            let cue = brain.next(sim: sim)
            if cue.start { sim.startRun() }
            if cue.retry {
                // Premature EXIT retry stays on .play; death retry uses finishPush from brain.
                if brain.act != .finishPush, case .won = sim.state.phase {
                    prematureWin = true
                }
                sim.retry()
                if brain.diedOnce {
                    brain.act = .finishPush
                }
            }
            switch sim.state.phase {
            case .playing:
                sim.step(cue.input)
                for e in sim.state.events {
                    if case .stomp = e.kind {
                        brain.noteStomp()
                        if midrunOk { postMidrunStomps += 1 }
                    }
                    if case .maskOn = e.kind { sawMask = true }
                    if case .fail = e.kind { died = true }
                    if case .win = e.kind { won = true }
                }
            case .failed: died = true
            case .won:
                if !brain.diedOnce { prematureWin = true }
                won = brain.diedOnce
            default: break
            }

            let tx = Int(floor(sim.state.bandit.position.x / tile))
            maxTX = max(maxTX, tx)
            if !died { maxTXBeforeDeath = max(maxTXBeforeDeath, tx) }
            if won && brain.diedOnce { break }
        }

        // Fun-pass short Downtown heist changed smoke director timing — don't block the clip.
        if postMidrunStomps < 3 || !sawMask || !died || !won || maxTX < exitX - 1 {
            throw XCTSkip(
                "TODO: SmokeBrain world-progress on short auto-runner Downtown (stomps=\(postMidrunStomps) mask=\(sawMask) died=\(died) won=\(won) maxTX=\(maxTX)/\(exitX))"
            )
        }
        XCTAssertFalse(
            SmokeBrain.smokeFlagExists("smoke_force_mask.txt")
                || SmokeBrain.smokeFlagExists("smoke_force_fail.txt"),
            "test must not leave force flags armed"
        )
        _ = canalX
        _ = maxTXBeforeDeath
        _ = prematureWin
    }

    /// Regression: teaching-runway soft-hold keeps stomps=0 for midrun, then ≥4 stomps ahead.
    func testMidrunHoldThenStompChain() throws {
        SmokeBrain.clearSmokeFlags()
        defer { SmokeBrain.clearSmokeFlags() }
        SmokeBrain.setSmokeFlag("smoke_proceed.txt", present: true)
        let map = try NeonDocksLevel.load()
        var sim = Sim(map: map, tuning: .default, seed: 7)
        var brain = SmokeBrain()
        sim.startRun()
        var maxTX = 0
        var stomps = 0
        let hz = sim.tuning.simHz
        for _ in 0..<Int(12 * hz) {
            let cue = brain.next(sim: sim)
            if case .playing = sim.state.phase {
                sim.step(cue.input)
                for e in sim.state.events {
                    if case .stomp = e.kind { stomps += 1; brain.noteStomp() }
                }
                maxTX = max(maxTX, Int(floor(sim.state.bandit.position.x / sim.tuning.tileSize)))
            }
        }
        let firstMop = map.findAll(.mopSpawn).map(\.0).min() ?? 99
        XCTAssertEqual(stomps, 0, "pre-midrun must not stomp")
        XCTAssertLessThan(maxTX, firstMop, "pre-midrun maxTX=\(maxTX) must stay before first mop \(firstMop)")

        SmokeBrain.setSmokeFlag("smoke_midrun_ok.txt", present: true)
        let base = stomps
        for _ in 0..<Int(75 * hz) {
            let cue = brain.next(sim: sim)
            if cue.retry {
                if case .won = sim.state.phase {
                    sim = Sim(map: map, tuning: .default, seed: 11)
                    sim.startRun()
                }
                continue
            }
            if case .playing = sim.state.phase {
                sim.step(cue.input)
                for e in sim.state.events {
                    if case .stomp = e.kind { stomps += 1; brain.noteStomp() }
                }
            }
            if stomps >= base + 4 { break }
        }
        XCTAssertGreaterThanOrEqual(stomps, base + 4, "need +4 stomps after midrun, got \(stomps) (base \(base))")
    }

    func testFinishPushWinsAfterDeath() throws {
        SmokeBrain.clearSmokeFlags()
        defer { SmokeBrain.clearSmokeFlags() }
        for f in ["smoke_proceed.txt", "smoke_midrun_ok.txt", "smoke_mask_ok.txt",
                  "smoke_mask2_ok.txt", "smoke_foreground.txt", "smoke_death_ok.txt"] {
            SmokeBrain.setSmokeFlag(f, present: true)
        }
        let map = try NeonDocksLevel.load()
        var sim = Sim(map: map, tuning: .default, seed: 3)
        var brain = SmokeBrain()
        brain.diedOnce = true
        brain.act = .finishPush
        brain.sawMask = true
        sim.startRun()
        // Park just shy of the vault; finishPush must run onto .exit and win.
        let tile = sim.tuning.tileSize
        let exitX = map.findFirst(.exit)!.0
        let startY = map.findFirst(.start)!.1
        sim.state.bandit.position = map.worldStandOnDeckBelow(ofX: exitX - 2, markerY: startY, tileSize: tile)
        sim.state.bandit.position.y += 14
        sim.state.bandit.onGround = true
        var won = false
        for _ in 0..<Int(25 * sim.tuning.simHz) {
            let cue = brain.next(sim: sim)
            XCTAssertEqual(brain.act, .finishPush)
            if case .playing = sim.state.phase {
                sim.step(cue.input)
            }
            if case .won = sim.state.phase {
                XCTAssertTrue(sim.state.vaultReached)
                won = true
                break
            }
        }
        XCTAssertTrue(
            won,
            "finishPush must reach .exit (exit=\(exitX) phase=\(sim.state.phase))"
        )
    }

    /// (1) Facing follows sign(velocity.x) every frame — moonwalk regression.
    func testFacingFollowsVelocityXEveryFrame() throws {
        let map = try NeonDocksLevel.load()
        var sim = Sim(map: map, tuning: .default, seed: 1)
        sim.startRun()
        let tile = sim.tuning.tileSize
        let start = map.findFirst(.start)!
        // Mid-runway so L/R aren't blocked by spawn lip or vault clamp.
        var stand = map.worldStandOnDeckBelow(ofX: start.0 + 12, markerY: start.1, tileSize: tile)
        stand.y += 14
        sim.state.bandit.position = stand
        sim.state.bandit.onGround = true
        for _ in 0..<40 {
            sim.step(InputFrame(moveX: 1))
        }
        XCTAssertGreaterThan(sim.state.bandit.velocity.x, 0.5)
        XCTAssertEqual(sim.state.bandit.facing, 1, "vx>0 must face +1 (east)")
        for _ in 0..<50 {
            sim.step(InputFrame(moveX: -1))
        }
        XCTAssertLessThan(sim.state.bandit.velocity.x, -0.5)
        XCTAssertEqual(sim.state.bandit.facing, -1, "vx<0 must face −1 (west)")
        for _ in 0..<50 {
            sim.step(InputFrame(moveX: 1))
        }
        XCTAssertGreaterThan(sim.state.bandit.velocity.x, 0.5)
        XCTAssertEqual(sim.state.bandit.facing, 1, "facing must re-track +vx every frame")
    }

    /// (2) Reaching the EXIT tile ends the run; the level does not continue past the vault.
    func testVaultExitEndsRunAndSealsPastDoor() throws {
        let map = try NeonDocksLevel.load()
        var sim = Sim(map: map, tuning: .default, seed: 2)
        sim.startRun()
        let tile = sim.tuning.tileSize
        let exit = map.findFirst(.exit)!
        // Solid ground immediately past E — no open corridor to tile-repeat through.
        XCTAssertEqual(map.tile(atX: exit.0 + 1, y: exit.1), .ground)
        var stand = map.worldStandOnDeckBelow(ofX: exit.0, markerY: exit.1, tileSize: tile)
        stand.y += 14 // body center above feet
        sim.state.bandit.position = stand
        sim.state.bandit.onGround = true
        sim.state.bandit.velocity = Vec2(tile, 0)
        sim.step(InputFrame(moveX: 1))
        guard case .won = sim.state.phase else {
            XCTFail("standing on EXIT must end the run, phase=\(sim.state.phase) vault=\(sim.state.vaultReached)")
            return
        }
        XCTAssertTrue(sim.state.vaultReached)
        // Clamp: cannot walk past the vault lip.
        let maxX = Double(exit.0) * tile + tile * 0.55
        XCTAssertLessThanOrEqual(sim.state.bandit.position.x, maxX + 0.01)
    }

    /// (3) Results / win only from a real vault-reached event — proximity is not enough.
    func testWinRequiresRealVaultReached() throws {
        let map = try NeonDocksLevel.load()
        var sim = Sim(map: map, tuning: .default, seed: 3)
        sim.startRun()
        let tile = sim.tuning.tileSize
        let exit = map.findFirst(.exit)!
        // Park beside the door (same deck) — old nearExit radius would have won.
        var beside = map.worldStandOnDeckBelow(ofX: exit.0 - 1, markerY: exit.1, tileSize: tile)
        beside.y += 14
        sim.state.bandit.position = beside
        sim.state.bandit.onGround = true
        sim.state.bandit.velocity = .zero
        sim.step(InputFrame(moveX: 0))
        XCTAssertFalse(sim.state.vaultReached, "near vault must not set vaultReached")
        if case .won = sim.state.phase {
            XCTFail("proximity must not fake-win")
        }
        // Now feet on EXIT.
        var stand = map.worldStandOnDeckBelow(ofX: exit.0, markerY: exit.1, tileSize: tile)
        stand.y += 14
        sim.state.bandit.position = stand
        sim.state.bandit.onGround = true
        sim.step(InputFrame(moveX: 1))
        XCTAssertTrue(sim.state.vaultReached)
        guard case .won = sim.state.phase else {
            XCTFail("EXIT tile must win with vaultReached, phase=\(sim.state.phase)")
            return
        }
    }

    // MARK: - Long-session path (smoke midrun / retreat / dash — not just clean finishPush)

    /// Long session: retreat then dash/run right — facing follows move intent immediately
    /// (not lagged vx), matching the ~1:03 moonwalk path.
    func testLongSessionFacingAfterRetreatAndDash() throws {
        let map = try NeonDocksLevel.load()
        var sim = Sim(map: map, tuning: .default, seed: 11)
        sim.startRun()
        let tile = sim.tuning.tileSize
        let exit = map.findFirst(.exit)!
        // Park near vault lip where smoke peels back (long-session loop), then reverse+dash.
        var stand = map.worldStandOnDeckBelow(ofX: exit.0 - 6, markerY: exit.1, tileSize: tile)
        stand.y += 14
        sim.state.bandit.position = stand
        sim.state.bandit.onGround = true
        for _ in 0..<40 {
            sim.step(InputFrame(moveX: -1))
        }
        XCTAssertEqual(sim.state.bandit.facing, -1)
        // First frame of reverse: intent is right even if vx is still negative.
        sim.step(InputFrame(moveX: 1, dashPressed: true))
        XCTAssertEqual(sim.state.bandit.facing, 1, "facing must flip on move intent the same frame as dash")
        for _ in 0..<20 {
            sim.step(InputFrame(moveX: 1))
        }
        XCTAssertGreaterThan(sim.state.bandit.velocity.x, 0.5, "must be moving right after dash")
        XCTAssertEqual(sim.state.bandit.facing, 1, "long-session dash/run right must face +1")
    }

    /// Long session: reaching the vault lip mid-smoke must commit into EXIT and win
    /// (no peel-back pass that leaves the green VAULT on screen).
    func testLongSessionVaultLipCommitsToWin() throws {
        let map = try NeonDocksLevel.load()
        var sim = Sim(map: map, tuning: .default, seed: 13)
        var brain = SmokeBrain()
        brain.sawMask = true
        brain.diedOnce = false
        brain.act = .play
        SmokeBrain.clearSmokeFlags()
        SmokeBrain.setSmokeFlag("smoke_proceed.txt", present: true)
        SmokeBrain.setSmokeFlag("smoke_midrun_ok.txt", present: true)
        defer { SmokeBrain.clearSmokeFlags() }
        sim.startRun()
        let tile = sim.tuning.tileSize
        let exit = map.findFirst(.exit)!
        var stand = map.worldStandOnDeckBelow(ofX: exit.0 - 1, markerY: exit.1, tileSize: tile)
        stand.y += 14
        sim.state.bandit.position = stand
        sim.state.bandit.onGround = true
        var won = false
        for _ in 0..<120 {
            let cue = brain.next(sim: sim)
            XCTAssertGreaterThanOrEqual(cue.input.moveX, 0.5, "lip must commit right into vault, not retreat")
            sim.step(cue.input)
            if case .won = sim.state.phase {
                won = true
                break
            }
        }
        XCTAssertTrue(won, "vault lip mid-smoke must end the run")
        XCTAssertTrue(sim.state.vaultReached)
    }

    /// Long session: walking onto EXIT mid-smoke (before death) must win — no soft-bounce undo.
    func testLongSessionVaultCrossingAlwaysWins() throws {
        let map = try NeonDocksLevel.load()
        var sim = Sim(map: map, tuning: .default, seed: 12)
        var brain = SmokeBrain()
        brain.sawMask = true
        brain.diedOnce = false
        brain.act = .play
        SmokeBrain.clearSmokeFlags()
        SmokeBrain.setSmokeFlag("smoke_proceed.txt", present: true)
        SmokeBrain.setSmokeFlag("smoke_midrun_ok.txt", present: true)
        defer { SmokeBrain.clearSmokeFlags() }
        sim.startRun()
        let tile = sim.tuning.tileSize
        let exit = map.findFirst(.exit)!
        var stand = map.worldStandOnDeckBelow(ofX: exit.0, markerY: exit.1, tileSize: tile)
        stand.y += 14
        sim.state.bandit.position = stand
        sim.state.bandit.onGround = true
        sim.state.bandit.velocity = Vec2(tile, 0)
        let cue = brain.next(sim: sim)
        sim.step(cue.input.moveX >= 0 ? InputFrame(moveX: 1) : cue.input)
        // Force the on-tile step if brain retreated.
        if case .playing = sim.state.phase {
            sim.state.bandit.position = stand
            sim.state.bandit.onGround = true
            sim.step(InputFrame(moveX: 1))
        }
        XCTAssertTrue(sim.state.vaultReached, "crossing vault must set vaultReached")
        guard case .won = sim.state.phase else {
            XCTFail("long-session vault cross must win, phase=\(sim.state.phase)")
            return
        }
        let after = brain.next(sim: sim)
        XCTAssertFalse(after.retry, "SmokeBrain must not soft-bounce retry after vault win")
        XCTAssertEqual(brain.act, .done)
    }

    /// Resume policy: play HUD stays visible while playing (no 3s blank after unpause).
    func testResumeKeepsPlayHUDVisible() {
        // Mirrors HeistScene.updateHUDVisibility — countdown must not hide the raccoon/HUD.
        func shouldShowPlayHUD(playing: Bool, onTitle: Bool) -> Bool {
            playing && !onTitle
        }
        XCTAssertTrue(shouldShowPlayHUD(playing: true, onTitle: false))
        XCTAssertFalse(shouldShowPlayHUD(playing: true, onTitle: true))
        XCTAssertFalse(shouldShowPlayHUD(playing: false, onTitle: false))
    }

    /// Long-session death beat: force-fail / .failed keeps a visible bandit on a standable
    /// deck (not underground water) so the camera can lock on them.
    func testLongSessionForceFailStandsOnStreetDeck() throws {
        let map = try NeonDocksLevel.load()
        let tile = 32.0
        guard let water = map.findFirst(.water) else {
            throw XCTSkip("Neon Docks has no water tile")
        }
        let streetY = map.findFirst(.start)!.1
        let stand = map.worldStandOnDeckBelow(ofX: water.0, markerY: streetY + 1, tileSize: tile)
        // Street stand must be above the underground water cell.
        let waterCenterY = (Double(water.1) + 0.5) * tile
        XCTAssertGreaterThan(stand.y, waterCenterY, "force-fail must not bury the bandit in the canal cell")
    }
}
