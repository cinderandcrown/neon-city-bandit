// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import Foundation

public struct SimEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case jump, land, pounce, flop, stomp, shiny, bank, maskOn, hurt, win, fail(FailReason), checkpoint, dust, shake
        case crewFreed(crewID: String)
        case dash, grab, gadget
    }
    public var kind: Kind
    public var position: Vec2
}

public struct SimState: Equatable, Sendable {
    public var tick: Int
    public var elapsed: Double
    public var bandit: BanditState
    public var shinies: [ShinyPickup]
    public var mops: [MopEnemy]
    public var checkpoints: [Checkpoint]
    public var crewCages: [CrewCage]
    public var spawn: Vec2
    public var phase: RunPhase
    public var controlVariant: ControlVariant
    public var events: [SimEvent]
    public var bestCombo: Int
    /// Sticky: set only when feet land on the EXIT tile. Results UI must gate on this.
    public var vaultReached: Bool

    public var stateHash: UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        func mix(_ v: UInt64) { h ^= v; h &*= 0x100000001b3 }
        func mixD(_ d: Double) { mix(d.bitPattern) }
        mix(UInt64(tick))
        mixD(bandit.position.x); mixD(bandit.position.y)
        mixD(bandit.velocity.x); mixD(bandit.velocity.y)
        mix(UInt64(bandit.combo)); mix(UInt64(bandit.carriedShinies)); mix(UInt64(bandit.bankedShinies))
        mix(UInt64(bandit.hearts)); mix(bandit.maskMode ? 1 : 0)
        mix(vaultReached ? 1 : 0)
        for s in shinies { mix(UInt64(s.id)); mix(s.alive ? 1 : 0) }
        for m in mops { mix(UInt64(m.id)); mix(m.alive ? 1 : 0); mixD(m.position.x) }
        switch phase {
        case .title: mix(0)
        case .playing: mix(1)
        case .won: mix(2)
        case .failed(let r):
            mix(3)
            mix(r == .fellInWater ? 1 : (r == .spiked ? 2 : 3))
        }
        return h
    }
}

public struct Sim: Equatable, Sendable {
    public var tuning: Tuning
    public var map: TileMap
    public var state: SimState
    public var seed: UInt64

    private let halfW: Double = 10
    private let halfH: Double = 14

    public init(map: TileMap, tuning: Tuning = .default, seed: UInt64 = 1, variant: ControlVariant = .a) {
        self.tuning = tuning
        self.map = map
        self.seed = seed
        let tile = tuning.tileSize
        let start = map.findFirst(.start).map { map.worldCenter(ofX: $0.0, y: $0.1, tileSize: tile) }
            ?? Vec2(tile * 2, tile * 3)

        var shinies: [ShinyPickup] = []
        for (i, c) in map.findAll(.shinySpawn).enumerated() {
            shinies.append(ShinyPickup(id: i, position: map.worldCenter(ofX: c.0, y: c.1, tileSize: tile), alive: true))
        }
        var cps: [Checkpoint] = []
        for (i, c) in map.findAll(.checkpoint).enumerated() {
            cps.append(Checkpoint(id: i, position: map.worldCenter(ofX: c.0, y: c.1, tileSize: tile), activated: false))
        }
        var cages: [CrewCage] = []
        let crewIDs = ["scrapz", "glitch", "fizz", "pip"]
        for (i, c) in map.findAll(.crewCage).enumerated() {
            cages.append(CrewCage(
                id: i,
                position: map.worldCenter(ofX: c.0, y: c.1, tileSize: tile),
                freed: false,
                crewID: crewIDs[i % crewIDs.count]
            ))
        }
        var mops: [MopEnemy] = []
        var mopID = 0
        var rng = SeededRNG(seed: seed)
        for (i, c) in map.findAll(.mopSpawn).enumerated() {
            let p = map.worldStandOnDeckBelow(ofX: c.0, markerY: c.1, tileSize: tile)
            // Keep a short clear zone at spawn so the first hop isn't an instant bag —
            // but leave easy MOPs close (≈2.2 tiles) for first-minute wins.
            if abs(p.x - start.x) < tile * 2.2 { continue }
            if cps.contains(where: { abs(p.x - $0.position.x) < tile * 2.5 }) { continue }
            // Daily Heist seed can skip ~12% of far spawns so each day feels different
            // without rewriting the reachability-proven ASCII.
            if mopID >= 8, rng.nextDouble() < 0.12 { continue }
            // Opening pack: short readable patrol so hop-stomps chain into Mask fast.
            let span = tile * (mopID < 8 ? 0.7 : 2.2) * (0.85 + rng.nextDouble() * 0.3)
            // Wide phase desync so neighbors don't mirror-walk on top of each other.
            let phase = Double(mopID) * 1.7 + Double(i) * 0.37 + rng.nextDouble() * 2.4
            mops.append(MopEnemy(
                id: mopID, position: p, home: p, patrolSpan: span, phase: phase,
                alive: true, respawn: 0, anim: .walk, animHold: 0, facing: 1, stun: 0
            ))
            mopID += 1
        }
        // Full docks (and similar) get an easy hop-stomp pack + street shinies for the first minute.
        // Tiny unit-test maps must stay clean — don't inject extras into 10-tile harness levels.
        if map.width >= 40 {
            for k in 0..<3 {
                let p = Vec2(start.x + tile * (3.0 + Double(k) * 1.4), start.y)
                if mops.contains(where: { abs($0.home.x - p.x) < tile * 0.8 && abs($0.home.y - p.y) < tile }) {
                    continue
                }
                mops.append(MopEnemy(
                    id: mopID, position: p, home: p, patrolSpan: tile * 0.55,
                    phase: Double(k) * 2.1, alive: true, respawn: 0,
                    anim: .walk, animHold: 0, facing: 1, stun: 0
                ))
                mopID += 1
            }
            for k in 0..<4 {
                let p = Vec2(start.x + tile * (2.4 + Double(k) * 1.8), start.y + tile * 0.15)
                if shinies.contains(where: { abs($0.position.x - p.x) < tile * 0.7 }) { continue }
                shinies.append(ShinyPickup(id: shinies.count, position: p, alive: true))
            }
        }
        // Nudge spawn homes apart when markers land too close on the same deck.
        for i in mops.indices {
            for j in (i + 1)..<mops.count {
                guard abs(mops[i].home.y - mops[j].home.y) < tile * 0.8 else { continue }
                let dx = mops[j].home.x - mops[i].home.x
                let minSep = tile * 1.05
                if abs(dx) < minSep {
                    let push = (minSep - abs(dx)) * 0.5
                    let dir = dx >= 0 ? 1.0 : -1.0
                    mops[i].home.x -= dir * push
                    mops[j].home.x += dir * push
                    mops[i].position.x = mops[i].home.x
                    mops[j].position.x = mops[j].home.x
                }
            }
        }

        self.state = SimState(
            tick: 0,
            elapsed: 0,
            bandit: .spawn(at: start, hearts: tuning.hearts),
            shinies: shinies,
            mops: mops,
            checkpoints: cps,
            crewCages: cages,
            spawn: start,
            phase: .title,
            controlVariant: variant,
            events: [],
            bestCombo: 0,
            vaultReached: false
        )
    }

    public mutating func startRun() {
        guard case .title = state.phase else { return }
        state.phase = .playing
        // Spawn safety: brief i-frames so the teaching stretch never bags on frame 1.
        state.bandit.invuln = max(state.bandit.invuln, 1.5)
        state.bandit.hearts = max(state.bandit.hearts, tuning.hearts)
    }

    public mutating func retry() {
        let variant = state.controlVariant
        let map = self.map
        let tuning = self.tuning
        let seed = self.seed &+ 1
        self = Sim(map: map, tuning: tuning, seed: seed, variant: variant)
        state.phase = .playing
        state.bandit.invuln = max(state.bandit.invuln, 1.5)
        state.bandit.hearts = tuning.hearts
    }

    public mutating func step(_ input: InputFrame) {
        state.events.removeAll(keepingCapacity: true)
        guard case .playing = state.phase else {
            state.tick += 1
            return
        }

        let dt = tuning.dt
        state.elapsed += dt
        var b = state.bandit

        if input.jumpPressed { b.jumpBuffer = tuning.jumpBufferSeconds }
        else if b.jumpBuffer > 0 { b.jumpBuffer = max(0, b.jumpBuffer - dt) }

        if b.invuln > 0 { b.invuln = max(0, b.invuln - dt) }
        // Brief post-stomp grace only while still airborne — grounded side hits must hurt.
        if b.combo > 0, b.comboTimer > 0, !b.onGround {
            b.invuln = max(b.invuln, 0.12)
        }
        if b.landCooldown > 0 { b.landCooldown = max(0, b.landCooldown - dt) }
        if b.dropThrough > 0 { b.dropThrough = max(0, b.dropThrough - dt) }
        if b.dashCooldown > 0 { b.dashCooldown = max(0, b.dashCooldown - dt) }
        if b.gadgetCooldown > 0 { b.gadgetCooldown = max(0, b.gadgetCooldown - dt) }
        if b.dashTimer > 0 {
            b.dashTimer = max(0, b.dashTimer - dt)
            if b.dashTimer <= 0, b.anim == .slide { b.anim = b.onGround ? .idle : .fall }
        }
        if b.animHold > 0 {
            b.animHold = max(0, b.animHold - dt)
            if b.animHold <= 0, b.anim == .hurt || b.anim == .pickUp {
                b.anim = .idle
            }
        }
        // Context GRAB target — loot / exit / latch / stash / crew within reach.
        b.interactTarget = nearestInteract(bandit: b)

        // Drop through one-ways: hold down while feet are ON a one-way deck.
        // Do NOT scan horizontal neighbors — a canal lip beside solid street used to
        // pin Bandit in a dropThrough stutter soft-lock when holding down / seeking death.
        if b.onGround, input.moveY < -0.45 {
            let tile = tuning.tileSize
            let feet = b.position.y - halfH - 1
            let tx = Int(floor(b.position.x / tile))
            let ty = Int(floor(feet / tile))
            let tyLo = Int(floor((feet - 2) / tile))
            let onOneWay = map.tile(atX: tx, y: ty) == .oneWay
                || map.tile(atX: tx, y: tyLo) == .oneWay
            if onOneWay {
                b.dropThrough = 0.28
                b.onGround = false
            }
        }

        // Airborne before integrate/collide — walking must not look like a stomp
        // just because gravity briefly pulls vy negative on solid ground.
        let wasAirborne = !b.onGround || b.flopping || b.pouncing || b.dropThrough > 0
        let groundedBefore = b.onGround
        integrate(input: input, bandit: &b, dt: dt)
        applyActionButtons(input: input, bandit: &b)
        // Capture fall speed before collide zeroes it on land — used for stomp vs hurt.
        let preCollideVy = b.velocity.y
        // Stomp window: falling, OR within a few frames of apex (Nick feel pass).
        let feel = tuning.feel
        let apexSpeed = feel.apexHangSpeed * tuning.tileSize / 2.2
        if wasAirborne, abs(b.velocity.y) <= apexSpeed {
            b.apexStompFrames = max(b.apexStompFrames, feel.stompApexFrames)
        } else if b.apexStompFrames > 0 {
            b.apexStompFrames -= 1
        }
        // Don't clear apex on the pre-collide grounded flag — land frame still stomps.
        if groundedBefore, !b.flopping, !b.pouncing { b.apexStompFrames = 0 }
        // Pounce / belly-flop: always safe while diving (drop-through → MOP).
        if b.pouncing || b.flopping {
            b.invuln = max(b.invuln, 0.2)
        }
        collide(bandit: &b)
        let justLanded = wasAirborne && b.onGround
        if justLanded {
            // ~6 frames after landing: overlap with a MOP still stomps, never side-bags.
            b.landStompGrace = max(b.landStompGrace, 6)
        } else if b.landStompGrace > 0 {
            b.landStompGrace -= 1
        }
        // Any downward / landed-from-air / pounce / drop-through contact can stomp.
        let stompFalling = b.flopping
            || b.pouncing
            || b.dropThrough > 0
            || b.landStompGrace > 0
            || (wasAirborne && (preCollideVy <= 0 || b.velocity.y <= 0 || b.apexStompFrames > 0))
        // Soft magnet: full pull on pounce/flop; short-range assist on normal falls.
        if b.pouncing || b.flopping {
            applyPounceMagnet(bandit: &b, reachMul: 1.0)
        } else if stompFalling {
            applyPounceMagnet(bandit: &b, reachMul: 0.55)
        }
        updateAnim(bandit: &b)
        collectShinies(bandit: &b)
        collectCrew(bandit: &b)
        updateCheckpoints(bandit: &b)
        bankAndExit(bandit: &b)
        updateMops(bandit: &b, dt: dt, stompFalling: stompFalling, jumpHeld: input.jumpHeld)
        updateCombo(bandit: &b, dt: dt)
        hazards(bandit: &b)

        state.bandit = b
        state.bestCombo = max(state.bestCombo, b.combo)
        state.tick += 1
    }

    // MARK: - Physics

    private mutating func integrate(input: InputFrame, bandit: inout BanditState, dt: Double) {
        let feel = tuning.feel
        let move = max(-1, min(1, input.moveX))
        // Facing follows move intent when steering, else velocity.x.
        // Intent-first kills turnaround moonwalk (retreat→dash right): vx can lag
        // negative for several frames while the stick/brain already says go right.
        if abs(move) > feel.stickDeadZone {
            bandit.facing = move >= 0 ? 1 : -1
        } else if abs(bandit.velocity.x) > 0.01 {
            bandit.facing = bandit.velocity.x >= 0 ? 1 : -1
        }

        // Accel from time-to-speed: reach runPx in groundAccelTime; stop in groundStopTime.
        let walkPx = feel.walkSpeed * tuning.tileSize
        let runPx = feel.runSpeed * tuning.tileSize
        let groundAccel = runPx / max(0.04, feel.groundAccelTime)
        let groundDecel = runPx / max(0.04, feel.groundStopTime)
        let accelBase = bandit.onGround ? groundAccel : groundAccel * feel.airControlMul
        let mag = abs(move)
        let thresh = max(feel.stickDeadZone + 0.01, min(0.9, feel.walkRunStickThreshold))
        let speedPx: Double
        if mag <= feel.stickDeadZone {
            speedPx = 0
        } else if mag < thresh {
            let t = (mag - feel.stickDeadZone) / max(0.05, thresh - feel.stickDeadZone)
            speedPx = walkPx * min(1, t)
        } else {
            let u = (mag - thresh) / max(0.05, 1 - thresh)
            speedPx = walkPx + (runPx - walkPx) * min(1, u)
        }
        let targetVx = (move >= 0 ? 1.0 : -1.0) * speedPx
        // DASH owns horizontal velocity for its burst window (stick must not crush the i-frame dodge).
        if bandit.dashTimer <= 0 {
            if mag > feel.stickDeadZone {
                let reversing = bandit.velocity.x * targetVx < 0
                let accel = accelBase * (reversing ? feel.turnAccelMul : 1)
                if bandit.velocity.x < targetVx {
                    bandit.velocity.x = min(targetVx, bandit.velocity.x + accel * dt)
                } else if bandit.velocity.x > targetVx {
                    bandit.velocity.x = max(targetVx, bandit.velocity.x - accel * dt)
                }
            } else {
                // Release stick → bleed horizontal on ground and in air (no forever skate / knockback).
                let frMul = bandit.onGround ? 1.0 : feel.airControlMul * 0.85
                let fr = groundDecel * frMul * dt
                if bandit.velocity.x > 0 { bandit.velocity.x = max(0, bandit.velocity.x - fr) }
                else if bandit.velocity.x < 0 { bandit.velocity.x = min(0, bandit.velocity.x + fr) }
            }
        }

        // Jump — ground / coyote / wall, plus one mid-air double jump.
        // Air charge is armed only by a real takeoff (not by walking off a ledge).
        if bandit.onGround { bandit.airJumpsRemaining = 0 }
        let canCoyote = bandit.coyote > 0
        let canWall = (bandit.onWallLeft || bandit.onWallRight) && !bandit.onGround
        let canDouble = !bandit.onGround && !canCoyote && !canWall && bandit.airJumpsRemaining > 0
        if bandit.jumpBuffer > 0 && (bandit.onGround || canCoyote || canWall || canDouble) {
            if canWall && !bandit.onGround {
                let dir: Double = bandit.onWallLeft ? 1 : -1
                bandit.velocity.x = dir * feel.wallJumpVelocityX * tuning.tileSize / 2.2
                bandit.velocity.y = feel.wallJumpVelocityY * tuning.tileSize / 2.2
                bandit.facing = dir
                bandit.wallCling = 0
                bandit.airJumpsRemaining = 1
            } else if canDouble {
                bandit.airJumpsRemaining -= 1
                bandit.velocity.y = feel.jumpVelocity * tuning.tileSize / 2.2 * 0.92
            } else {
                bandit.velocity.y = feel.jumpVelocity * tuning.tileSize / 2.2
                bandit.airJumpsRemaining = 1
            }
            bandit.onGround = false
            bandit.coyote = 0
            bandit.jumpBuffer = 0
            bandit.pouncing = false
            bandit.flopping = false
            bandit.jumpCutArmed = true
            state.events.append(SimEvent(kind: .jump, position: bandit.position))
            state.events.append(SimEvent(kind: .dust, position: bandit.position))
        }

        // Variable jump: early release cuts upward velocity once by jumpCutFraction.
        if bandit.jumpCutArmed, !input.jumpHeld, bandit.velocity.y > 0 {
            bandit.velocity.y *= feel.jumpCutFraction
            bandit.jumpCutArmed = false
        }

        // Asymmetric gravity: rise → fall×1.8, apex hang when |vy| is small.
        let scale = tuning.tileSize / 2.2
        let riseG = feel.gravity * scale
        let fallG = feel.gravity * feel.fallGravityMul * scale
        let apexSpeed = feel.apexHangSpeed * scale
        let g: Double
        if abs(bandit.velocity.y) <= apexSpeed, !bandit.onGround {
            g = riseG * feel.apexHangMul
        } else if bandit.velocity.y > 0 {
            g = riseG
        } else {
            g = fallG
        }

        // Pounce (forward boost) / Belly Flop (fast fall) while airborne.
        // Only arm once per aerial — re-pressing must not keep boosting or we soft-float.
        if input.pouncePressed && !bandit.onGround && !bandit.pouncing && !bandit.flopping {
            bandit.pouncing = true
            bandit.velocity.x += bandit.facing * feel.pounceBoostX * tuning.tileSize / 2
            bandit.velocity.y += feel.pounceBoostY * tuning.tileSize / 3
            applyPounceMagnet(bandit: &bandit)
            state.events.append(SimEvent(kind: .pounce, position: bandit.position))
            state.events.append(SimEvent(kind: .shake, position: bandit.position))
            if bandit.velocity.y < 2 {
                bandit.flopping = true
                bandit.velocity.y = -feel.bellyFlopFallBoost * tuning.tileSize / 2.5
                state.events.append(SimEvent(kind: .flop, position: bandit.position))
            }
        } else if input.pouncePressed && !bandit.onGround && bandit.pouncing && !bandit.flopping && bandit.velocity.y < 2 {
            bandit.flopping = true
            bandit.velocity.y = -feel.bellyFlopFallBoost * tuning.tileSize / 2.5
            state.events.append(SimEvent(kind: .flop, position: bandit.position))
        } else if bandit.pouncing || bandit.flopping {
            applyPounceMagnet(bandit: &bandit)
        }

        // Wall slide
        if !bandit.onGround && (bandit.onWallLeft || bandit.onWallRight) && bandit.velocity.y < 0 {
            let slide = -feel.wallSlideSpeed * tuning.tileSize / 2
            if bandit.velocity.y < slide { bandit.velocity.y = slide }
            bandit.wallCling = feel.wallClingSeconds
        } else if bandit.wallCling > 0 {
            bandit.wallCling = max(0, bandit.wallCling - dt)
        }

        bandit.velocity.y -= g * dt
        let maxFall = -feel.maxFall * tuning.tileSize / 2.2
        if bandit.velocity.y < maxFall { bandit.velocity.y = maxFall }

        bandit.position.x += bandit.velocity.x * dt
        bandit.position.y += bandit.velocity.y * dt

        if bandit.onGround {
            bandit.coyote = feel.coyoteSeconds
            bandit.jumpCutArmed = false
        } else if bandit.coyote > 0 {
            bandit.coyote = max(0, bandit.coyote - dt)
        }
    }

    /// Soft homing toward the nearest MOP within reach while falling / pouncing.
    private mutating func applyPounceMagnet(bandit: inout BanditState, reachMul: Double = 1.0) {
        let feel = tuning.feel
        let reach = feel.pounceMagnetTiles * tuning.tileSize * max(0.2, reachMul)
        var best: (idx: Int, dist: Double)?
        for (i, mop) in state.mops.enumerated() where mop.alive {
            let dx = mop.position.x - bandit.position.x
            let dy = mop.position.y - bandit.position.y
            // Prefer ahead, but allow a little behind so turnarounds still connect.
            if dx * bandit.facing < -reach * 0.35 { continue }
            if dy > halfH * 1.2 { continue }
            let d = hypot(dx, dy)
            if d > reach { continue }
            if best == nil || d < best!.dist { best = (i, d) }
        }
        guard let best else { return }
        let mop = state.mops[best.idx]
        let dx = mop.position.x - bandit.position.x
        let dy = mop.position.y - bandit.position.y
        let d = max(1, hypot(dx, dy))
        let pull = feel.pounceMagnetAccel * tuning.tileSize * tuning.dt * max(0.35, reachMul)
        bandit.velocity.x += (dx / d) * pull
        bandit.velocity.y += (dy / d) * pull * 0.75
    }

    private mutating func collide(bandit: inout BanditState) {
        let tile = tuning.tileSize
        // Capture before the probe reset — otherwise every grounded step looks like a landing.
        let wasGrounded = bandit.onGround
        bandit.onGround = false
        bandit.onWallLeft = false
        bandit.onWallRight = false

        // Full solids block sides / head. One-ways only block feet when falling (and not dropping).
        func solidAt(_ wx: Double, _ wy: Double) -> Bool {
            let tx = Int(floor(wx / tile))
            let ty = Int(floor(wy / tile))
            return map.isSolid(map.tile(atX: tx, y: ty))
        }
        func landableAt(_ wx: Double, _ wy: Double) -> Bool {
            let tx = Int(floor(wx / tile))
            let ty = Int(floor(wy / tile))
            let kind = map.tile(atX: tx, y: ty)
            if map.isSolid(kind) { return true }
            if kind == .oneWay {
                if bandit.dropThrough > 0 { return false }
                // Only when approaching from above the platform top.
                let top = Double(ty + 1) * tile
                return bandit.velocity.y <= 0 && (bandit.position.y - halfH) <= top + 2
            }
            return false
        }

        // Horizontal
        if bandit.velocity.x > 0 {
            let right = bandit.position.x + halfW
            if solidAt(right, bandit.position.y + halfH * 0.6) || solidAt(right, bandit.position.y - halfH * 0.6) {
                let tx = Int(floor(right / tile))
                bandit.position.x = Double(tx) * tile - halfW - 0.01
                bandit.velocity.x = 0
                bandit.onWallRight = true
            }
        } else if bandit.velocity.x < 0 {
            let left = bandit.position.x - halfW
            if solidAt(left, bandit.position.y + halfH * 0.6) || solidAt(left, bandit.position.y - halfH * 0.6) {
                let tx = Int(floor(left / tile))
                bandit.position.x = Double(tx + 1) * tile + halfW + 0.01
                bandit.velocity.x = 0
                bandit.onWallLeft = true
            }
        }

        // Vertical
        let corner = tuning.feel.cornerCorrectPx
        if bandit.velocity.y <= 0 {
            let feet = bandit.position.y - halfH
            let footL = landableAt(bandit.position.x - halfW * 0.6, feet)
            let footR = landableAt(bandit.position.x + halfW * 0.6, feet)
            if footL || footR {
                // Near-miss landing: only one foot catches a ledge — nudge onto the solid.
                // Only while landing from air. Applying this while grounded pulls Bandit
                // back onto every walk-off (canal soft-lock at the lip).
                if footL != footR, corner > 0, !wasGrounded {
                    let dir: Double = footR ? 1 : -1
                    for step in stride(from: 1.0, through: corner, by: 1.0) {
                        let nx = bandit.position.x + dir * step
                        if landableAt(nx - halfW * 0.6, feet), landableAt(nx + halfW * 0.6, feet) {
                            bandit.position.x = nx
                            break
                        }
                    }
                }
                let ty = Int(floor(feet / tile))
                bandit.position.y = Double(ty + 1) * tile + halfH
                // Fire land/dust only on the air → ground transition, with a short cooldown
                // so pounce whoosh → land → land (20–67 ms) collapses to one event.
                if !wasGrounded, bandit.landCooldown <= 0 {
                    state.events.append(SimEvent(kind: .land, position: bandit.position))
                    state.events.append(SimEvent(kind: .dust, position: bandit.position))
                    if bandit.velocity.y < -40 {
                        state.events.append(SimEvent(kind: .shake, position: bandit.position))
                    }
                    // ≥0.22s sim so CI wall-clock "sim land" pairs stay ≥100ms apart even
                    // when smoke catch-up steps run at 2× display (0.22/2 ≈ 0.11s wall).
                    bandit.landCooldown = 0.22
                }
                bandit.velocity.y = 0
                bandit.onGround = true
                bandit.pouncing = false
                bandit.flopping = false
                bandit.jumpCutArmed = false
                // Landing during a combo keeps brief i-frames so the next hop isn't a side-bag.
                if bandit.combo > 0, bandit.comboTimer > 0 {
                    bandit.invuln = max(bandit.invuln, 0.45)
                }
            }
        } else {
            let head = bandit.position.y + halfH
            let headHit = solidAt(bandit.position.x - halfW * 0.5, head) || solidAt(bandit.position.x + halfW * 0.5, head)
            if headHit {
                // Corner correction: nudge sideways up to cornerCorrectPx to slip past a ledge lip.
                var cleared = false
                if corner > 0 {
                    for step in stride(from: 1.0, through: corner, by: 1.0) {
                        for dir: Double in [1, -1] {
                            let nx = bandit.position.x + dir * step
                            if !solidAt(nx - halfW * 0.5, head), !solidAt(nx + halfW * 0.5, head) {
                                bandit.position.x = nx
                                cleared = true
                                break
                            }
                        }
                        if cleared { break }
                    }
                }
                if !cleared {
                    let ty = Int(floor(head / tile))
                    bandit.position.y = Double(ty) * tile - halfH - 0.01
                    bandit.velocity.y = 0
                }
            }
        }

        // Wall probes when falling beside walls
        if !bandit.onGround {
            if solidAt(bandit.position.x + halfW + 2, bandit.position.y) { bandit.onWallRight = true }
            if solidAt(bandit.position.x - halfW - 2, bandit.position.y) { bandit.onWallLeft = true }
        }

        // Clamp to map — never run past the vault door (no tile-repeat / overshoot).
        let minX = halfW
        var maxX = Double(map.width) * tile - halfW
        if let e = map.findFirst(.exit) {
            // Feet stay on/at the EXIT tile center so bankAndExit can fire; solid wall past E.
            maxX = min(maxX, Double(e.0) * tile + tile * 0.55)
        }
        let minY = halfH
        bandit.position.x = min(max(bandit.position.x, minX), maxX)
        if bandit.position.y < minY - tile * 2 {
            fail(.fellInWater, at: bandit.position)
        }
    }

    private func updateAnim(bandit: inout BanditState) {
        // Hurt / death / pick-up are sticky until animHold expires.
        if bandit.animHold > 0 { return }
        if bandit.dashTimer > 0 {
            bandit.anim = .slide
            return
        }
        if bandit.onGround {
            let speed = abs(bandit.velocity.x)
            let walkPx = tuning.walkSpeed * tuning.tileSize
            // Low idle threshold so any real stick input shows walk legs (not an idle glide).
            if speed <= 8 {
                bandit.anim = .idle
            } else if speed < walkPx * 0.85 {
                bandit.anim = .walk
            } else {
                bandit.anim = .run
            }
        } else if bandit.onWallLeft || bandit.onWallRight {
            bandit.anim = .wallSlide
        } else if bandit.pouncing || bandit.flopping {
            bandit.anim = .pounce
        } else if bandit.velocity.y > 60 {
            bandit.anim = .jump
        } else if bandit.velocity.y > -50 {
            bandit.anim = .apex
        } else {
            bandit.anim = .fall
        }
    }

    /// DASH / MASK / GRAB / GADGET — thumb-cluster actions.
    private mutating func applyActionButtons(input: InputFrame, bandit: inout BanditState) {
        let feel = tuning.feel
        let tile = tuning.tileSize

        if input.dashPressed, bandit.dashCooldown <= 0, bandit.animHold <= 0 || bandit.anim == .pickUp {
            bandit.dashTimer = feel.dashDuration
            bandit.dashCooldown = feel.dashCooldown
            bandit.velocity.x = bandit.facing * feel.dashSpeed * tile / 2.2
            if bandit.onGround {
                bandit.velocity.y = min(bandit.velocity.y, 0)
                bandit.anim = .slide
            } else {
                bandit.velocity.y = max(bandit.velocity.y, -feel.dashSpeed * tile * 0.15)
                bandit.anim = .slide
            }
            bandit.invuln = max(bandit.invuln, feel.dashInvuln)
            bandit.pouncing = false
            bandit.flopping = false
            state.events.append(SimEvent(kind: .dash, position: bandit.position))
            state.events.append(SimEvent(kind: .dust, position: bandit.position))
        }

        if input.maskPressed, !bandit.maskMode, bandit.maskCharges > 0 {
            bandit.maskCharges -= 1
            bandit.maskMode = true
            bandit.maskTimer = tuning.maskDuration
            state.events.append(SimEvent(kind: .maskOn, position: bandit.position))
        }

        if input.grabPressed, bandit.interactTarget != .none, bandit.animHold <= 0 {
            switch bandit.interactTarget {
            case .shiny:
                // Force a nearby shiny collect via the normal radius after a pick-up pose.
                bandit.anim = .pickUp
                bandit.animHold = 0.35
                // Nudge toward nearest shiny so collectShinies hits this frame.
                if let shiny = state.shinies.first(where: {
                    $0.alive && $0.position.distance(to: bandit.position) <= feel.grabReachTiles * tile * 1.4
                }) {
                    let dx = shiny.position.x - bandit.position.x
                    bandit.position.x += max(-tile * 0.35, min(tile * 0.35, dx))
                }
                collectShinies(bandit: &bandit)
                state.events.append(SimEvent(kind: .grab, position: bandit.position))
            case .exit:
                bandit.anim = .pickUp
                bandit.animHold = 0.25
                bankAndExit(bandit: &bandit)
                state.events.append(SimEvent(kind: .grab, position: bandit.position))
            case .crew:
                bandit.anim = .pickUp
                bandit.animHold = 0.35
                collectCrew(bandit: &bandit)
                state.events.append(SimEvent(kind: .grab, position: bandit.position))
            case .latch, .stash:
                bandit.anim = .pickUp
                bandit.animHold = 0.28
                state.events.append(SimEvent(kind: .grab, position: bandit.position))
                state.events.append(SimEvent(kind: .dust, position: bandit.position))
            case .none:
                break
            }
        }

        if input.gadgetPressed, bandit.gadgetCooldown <= 0 {
            bandit.gadgetCooldown = feel.gadgetCooldown
            let reach = feel.gadgetStunTiles * tile
            for i in state.mops.indices where state.mops[i].alive {
                if state.mops[i].position.distance(to: bandit.position) <= reach {
                    state.mops[i].stun = max(state.mops[i].stun, feel.gadgetStunSeconds)
                    state.mops[i].anim = .hurt
                    state.mops[i].animHold = 0.4
                }
            }
            state.events.append(SimEvent(kind: .gadget, position: bandit.position))
            state.events.append(SimEvent(kind: .shake, position: bandit.position))
        }
    }

    private func nearestInteract(bandit: BanditState) -> InteractKind {
        let tile = tuning.tileSize
        let reach = tuning.feel.grabReachTiles * tile
        var best: (InteractKind, Double) = (.none, reach + 1)
        for s in state.shinies where s.alive {
            let d = s.position.distance(to: bandit.position)
            if d <= reach, d < best.1 { best = (.shiny, d) }
        }
        for c in state.crewCages where !c.freed {
            let d = c.position.distance(to: bandit.position)
            if d <= reach * 1.1, d < best.1 { best = (.crew, d) }
        }
        let tx = Int(floor(bandit.position.x / tile))
        let ty = Int(floor(bandit.position.y / tile))
        for oy in -1...1 {
            for ox in -1...1 {
                let t = map.tile(atX: tx + ox, y: ty + oy)
                let d = hypot(Double(ox), Double(oy)) * tile
                if t == .exit, d <= reach * 1.2, d < best.1 { best = (.exit, d) }
                if t == .latch, d <= reach, d < best.1 { best = (.latch, d) }
                if t == .stash, d <= reach, d < best.1 { best = (.stash, d) }
            }
        }
        return best.0
    }

    private mutating func collectShinies(bandit: inout BanditState) {
        // Auto-pickup reach (GRAB folded in) — generous so loot arcs read as rewards.
        let r = tuning.tileSize * 1.15
        for i in state.shinies.indices where state.shinies[i].alive {
            if state.shinies[i].position.distance(to: bandit.position) <= r {
                state.shinies[i].alive = false
                let gain = bandit.maskMode ? 2 : 1
                bandit.carriedShinies += gain
                // Brief pose only — don't lock the auto-runner.
                if bandit.animHold <= 0 {
                    bandit.anim = .pickUp
                    bandit.animHold = 0.12
                }
                state.events.append(SimEvent(kind: .shiny, position: state.shinies[i].position))
            }
        }
    }

    private mutating func collectCrew(bandit: inout BanditState) {
        let r = tuning.tileSize * 0.85
        for i in state.crewCages.indices where !state.crewCages[i].freed {
            if state.crewCages[i].position.distance(to: bandit.position) <= r {
                state.crewCages[i].freed = true
                bandit.anim = .pickUp
                bandit.animHold = 0.55
                state.events.append(SimEvent(
                    kind: .crewFreed(crewID: state.crewCages[i].crewID),
                    position: state.crewCages[i].position
                ))
            }
        }
    }

    private mutating func updateCheckpoints(bandit: inout BanditState) {
        for i in state.checkpoints.indices where !state.checkpoints[i].activated {
            if state.checkpoints[i].position.distance(to: bandit.position) < tuning.tileSize {
                state.checkpoints[i].activated = true
                state.spawn = state.checkpoints[i].position
                state.events.append(SimEvent(kind: .checkpoint, position: state.checkpoints[i].position))
            }
        }
    }

    private mutating func bankAndExit(bandit: inout BanditState) {
        let tile = tuning.tileSize
        let tx = Int(floor(bandit.position.x / tile))
        let ty = Int(floor(bandit.position.y / tile))
        let t = map.tile(atX: tx, y: ty)
        if t == .stash, bandit.carriedShinies > 0, bandit.onGround {
            bandit.bankedShinies += bandit.carriedShinies
            bandit.carriedShinies = 0
            state.events.append(SimEvent(kind: .bank, position: bandit.position))
        }
        // Vault clear: overlapping the EXIT door on the vault deck (street or lower pit route).
        // Door visual is ~1.2 tiles wide — win when feet enter that volume, not only the
        // exact EXIT glyph, so a green VAULT pass always ends the run.
        guard bandit.onGround else { return }
        guard let e = map.findFirst(.exit) else { return }
        let exitCenterX = Double(e.0) * tile + tile * 0.5
        let onDeck = abs(bandit.position.y - Double(e.1) * tile) < tile * 1.6
        let overlapsDoor = abs(bandit.position.x - exitCenterX) <= tile * 0.75
        let onExit = onDeck && (t == .exit || overlapsDoor || tx == e.0)
        guard onExit else { return }
        state.vaultReached = true
        let total = bandit.bankedShinies + bandit.carriedShinies
        bandit.bankedShinies = total
        bandit.carriedShinies = 0
        state.phase = .won(seconds: state.elapsed, shinies: bandit.bankedShinies, combo: state.bestCombo)
        state.events.append(SimEvent(kind: .win, position: bandit.position))
    }

    private mutating func updateMops(bandit: inout BanditState, dt: Double, stompFalling: Bool, jumpHeld: Bool) {
        let feel = tuning.feel
        let mopW = feel.mopSpriteWidthTiles * tuning.tileSize
        let stompHalfW = mopW * feel.stompWidthMul * 0.5
        let hurtHalfW = mopW * feel.hurtWidthMul * 0.5
        let mopHalfH = halfH

        // Respawn + stun clocks before combat so a just-revived MOP can be stomped.
        for i in state.mops.indices {
            if !state.mops[i].alive {
                state.mops[i].respawn -= dt
                if state.mops[i].respawn <= 0 {
                    state.mops[i].alive = true
                    state.mops[i].position = state.mops[i].home
                }
                continue
            }
            if state.mops[i].animHold > 0 {
                state.mops[i].animHold = max(0, state.mops[i].animHold - dt)
            }
            if state.mops[i].stun > 0 {
                state.mops[i].stun = max(0, state.mops[i].stun - dt)
            }
        }

        // Stomp / hurt against the pre-patrol pose so the MOP doesn't slide out from
        // under the feet on the same frame (patrol used to break chains after combo 3).
        // Stomp ALWAYS runs before hurt when stompFalling (incl. drop-through / land grace).
        var didStomp = false
        if stompFalling {
            for i in state.mops.indices where state.mops[i].alive {
                let dx = abs(bandit.position.x - state.mops[i].position.x)
                let feetY = bandit.position.y - halfH
                let mopTop = state.mops[i].position.y + mopHalfH * 1.45
                let mopBottom = state.mops[i].position.y - mopHalfH
                // Any downward / land-frame overlap: feet at or above mop bottom, body overlapping top.
                let fromAbove = feetY <= mopTop + 22
                    && bandit.position.y >= mopBottom - 8
                    && feetY >= mopBottom - 20
                guard fromAbove, dx <= stompHalfW else { continue }

                state.mops[i].alive = false
                // Longer respawn while chaining so the pack doesn't pop back underfoot.
                state.mops[i].respawn = bandit.combo >= 2 ? 5.5 : 3.5
                state.mops[i].anim = .death
                state.mops[i].animHold = 0.8
                var bounce = feel.stompBounceVelocity * tuning.tileSize / 2.2
                if jumpHeld { bounce *= feel.stompBounceHoldMul }
                bandit.velocity.y = bounce
                bandit.flopping = false
                bandit.pouncing = false
                bandit.onGround = false
                bandit.landStompGrace = 0
                bandit.jumpCutArmed = jumpHeld
                // Stomp frames are always safe — no bagging on contact.
                bandit.invuln = max(bandit.invuln, max(1.0, feel.invulnSeconds))
                bandit.combo = min(tuning.comboCap, bandit.combo + 1)
                bandit.comboTimer = tuning.comboGroundGrace
                // Fill Mask meter (charges). Player presses MASK when the button appears.
                if bandit.combo >= tuning.maskModeAtCombo {
                    let cap = tuning.feel.maskMaxCharges
                    if bandit.maskCharges < cap {
                        bandit.maskCharges = min(cap, bandit.maskCharges + 1)
                    }
                }
                if bandit.maskMode {
                    bandit.maskTimer = max(bandit.maskTimer, tuning.maskDuration * 0.55)
                }
                state.events.append(SimEvent(kind: .stomp, position: state.mops[i].position))
                state.events.append(SimEvent(kind: .shake, position: state.mops[i].position))
                didStomp = true
                break // one stomp per frame keeps bounce/combo readable
            }
        }

        // Patrol after combat so sin-phase motion doesn't dodge the stomp frame.
        let tile = tuning.tileSize
        for i in state.mops.indices where state.mops[i].alive {
            if state.mops[i].stun <= 0 {
                let prevX = state.mops[i].position.x
                state.mops[i].phase += dt
                let ox = sin(state.mops[i].phase) * state.mops[i].patrolSpan
                state.mops[i].position.x = state.mops[i].home.x + ox
                state.mops[i].position.y = state.mops[i].home.y
                // Quiet-street seek only — if a combo is already rolling, stay on patrol
                // so Mask can expire and the player isn't farmed by a magnet pack.
                let dy = abs(state.mops[i].position.y - bandit.position.y)
                let toBandit = bandit.position.x - state.mops[i].position.x
                let streetQuiet = bandit.combo <= 0 || bandit.comboTimer < 2.2
                if streetQuiet,
                   dy < tile * 1.35,
                   abs(toBandit) > tile * 1.6,
                   abs(toBandit) < tile * 8
                {
                    let step = min(abs(toBandit), tile * 1.4) * dt
                    state.mops[i].position.x += (toBandit > 0 ? 1 : -1) * step
                }
                let dx = state.mops[i].position.x - prevX
                if abs(dx) > 0.01 { state.mops[i].facing = dx >= 0 ? 1 : -1 }
            } else {
                state.mops[i].position.y = state.mops[i].home.y
            }
            if state.mops[i].animHold <= 0 {
                state.mops[i].anim = .walk
            }
        }
        // Soft de-clump: same-deck MOPs push apart so packs don't read as one white blob.
        for i in state.mops.indices where state.mops[i].alive {
            for j in (i + 1)..<state.mops.count where state.mops[j].alive {
                guard abs(state.mops[i].position.y - state.mops[j].position.y) < tile * 0.85 else { continue }
                let dx = state.mops[j].position.x - state.mops[i].position.x
                let minSep = tile * 0.9
                if abs(dx) < minSep {
                    let push = (minSep - abs(dx)) * 0.5
                    let dir = dx >= 0 ? 1.0 : -1.0
                    state.mops[i].position.x -= dir * push
                    state.mops[j].position.x += dir * push
                    // Ease homes apart so the next patrol frame doesn't snap them back together.
                    state.mops[i].home.x -= dir * push * 0.35
                    state.mops[j].home.x += dir * push * 0.35
                }
            }
        }

        if didStomp { return }

        // DASH / Mask break through MOPs — shake only (not a stomp) so objective/smoke counts stay honest.
        if bandit.dashTimer > 0 || bandit.maskMode {
            for i in state.mops.indices where state.mops[i].alive {
                let dx = abs(bandit.position.x - state.mops[i].position.x)
                let dy = abs(bandit.position.y - state.mops[i].position.y)
                if dx <= stompHalfW * 0.85, dy <= mopHalfH * 1.5 {
                    state.mops[i].alive = false
                    state.mops[i].respawn = 4.0
                    state.mops[i].anim = .death
                    state.mops[i].animHold = 0.8
                    bandit.combo = min(tuning.comboCap, bandit.combo + 1)
                    bandit.comboTimer = tuning.comboGroundGrace
                    state.events.append(SimEvent(kind: .shake, position: state.mops[i].position))
                    state.events.append(SimEvent(kind: .dust, position: state.mops[i].position))
                }
            }
            return
        }

        // Side hits hurt unless stomping / pouncing / i-frames.
        // One heart per contact, then knockback + invuln — never multi-hit the same frame.
        if bandit.flopping || bandit.pouncing || bandit.dropThrough > 0 {
            return
        }
        if bandit.invuln > 0 || bandit.anim == .hurt {
            return
        }

        for i in state.mops.indices where state.mops[i].alive {
            let dx = abs(bandit.position.x - state.mops[i].position.x)
            let dy = abs(bandit.position.y - state.mops[i].position.y)
            // Hurt box stays smaller than the MOP sprite; grounded / rising beside them.
            if dx <= hurtHalfW, dy <= mopHalfH * 1.35 {
                bandit.hearts = max(0, bandit.hearts - 1)
                bandit.invuln = max(feel.invulnSeconds, 1.0)
                bandit.combo = 0
                bandit.comboTimer = 0
                var away = bandit.position.x >= state.mops[i].position.x ? 1.0 : -1.0
                let tile = tuning.tileSize
                let minSafe = tile * 2
                let maxSafe = Double(map.width) * tile - tile * 2
                var nx = bandit.position.x + away * tile * 1.35
                if nx < minSafe {
                    away = 1
                    nx = minSafe
                } else if nx > maxSafe {
                    away = -1
                    nx = maxSafe
                }
                bandit.position.x = nx
                bandit.velocity.y = feel.jumpVelocity * tile / 3
                bandit.velocity.x = away * feel.runSpeed * tile * 0.85
                // Face the knockback so the hurt pose never moonwalks away from the MOP.
                bandit.facing = away
                state.mops[i].position.x -= away * tile * 0.5
                state.mops[i].home.x = state.mops[i].position.x
                state.mops[i].stun = 0.5
                bandit.anim = .hurt
                bandit.animHold = 0.35
                state.mops[i].anim = .attack
                state.mops[i].animHold = 0.5
                state.events.append(SimEvent(kind: .hurt, position: bandit.position))
                if bandit.hearts <= 0 {
                    bandit.anim = .death
                    bandit.animHold = 1.35
                    bandit.invuln = 0
                    fail(.bagged, at: bandit.position)
                }
                break
            }
        }
    }

    private mutating func updateCombo(bandit: inout BanditState, dt: Double) {
        if bandit.combo > 0 {
            bandit.comboTimer -= dt
            if bandit.comboTimer <= 0 {
                bandit.combo = 0
            }
        }
        if bandit.maskMode {
            bandit.maskTimer = max(0, bandit.maskTimer - dt)
            if bandit.maskTimer <= 0 {
                bandit.maskMode = false
            }
        }
    }

    private mutating func hazards(bandit: inout BanditState) {
        let tile = tuning.tileSize
        let tx = Int(floor(bandit.position.x / tile))
        let ty = Int(floor((bandit.position.y - halfH * 0.8) / tile))
        let t = map.tile(atX: tx, y: ty)
        if t == .water {
            fail(.fellInWater, at: bandit.position)
        } else if t == .spike && bandit.invuln <= 0 {
            fail(.spiked, at: bandit.position)
        }
        // Kill plane: fell off the world / through the floor past the map.
        if bandit.position.y < -tile * 2 {
            fail(.fellInWater, at: bandit.position)
        } else if tx < -2 || tx > map.width + 2 {
            fail(.fellInWater, at: bandit.position)
        }
    }

    private mutating func fail(_ reason: FailReason, at pos: Vec2) {
        guard case .playing = state.phase else { return }
        state.bandit.anim = .death
        state.bandit.animHold = 1.35
        state.bandit.invuln = 0
        state.phase = .failed(reason)
        state.events.append(SimEvent(kind: .fail(reason), position: pos))
    }
}

public struct ReplayRecorder: Equatable, Sendable {
    public var inputs: [InputFrame] = []
    public init() {}
    public mutating func record(_ input: InputFrame) { inputs.append(input) }
}

public enum ReplayPlayer {
    public static func play(map: TileMap, tuning: Tuning, seed: UInt64, inputs: [InputFrame], variant: ControlVariant = .a) -> SimState {
        var sim = Sim(map: map, tuning: tuning, seed: seed, variant: variant)
        sim.state.phase = .playing
        for input in inputs { sim.step(input) }
        return sim.state
    }
}
