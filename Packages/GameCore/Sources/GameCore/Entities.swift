// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import Foundation

public enum BanditAnim: Equatable, Hashable, Sendable {
    case idle, walk, run, jump, apex, fall, pounce, wallSlide, hurt, death, pickUp, slide
}

public enum InteractKind: Equatable, Sendable {
    case none
    case shiny
    case exit
    case latch
    case stash
    case crew
}

public struct BanditState: Equatable, Sendable {
    public var position: Vec2
    public var velocity: Vec2
    public var facing: Double // −1 or 1
    public var onGround: Bool
    public var onWallLeft: Bool
    public var onWallRight: Bool
    public var coyote: Double
    public var jumpBuffer: Double
    public var wallCling: Double
    public var pouncing: Bool
    public var flopping: Bool
    public var combo: Int
    public var comboTimer: Double
    public var maskMode: Bool
    /// Remaining Mask Mode duration (independent of combo grace).
    public var maskTimer: Double
    /// MASK button charges (HUD "MASK ×N"). Earned by combo, spent to activate.
    public var maskCharges: Int
    public var hearts: Int
    public var invuln: Double
    public var carriedShinies: Int
    public var bankedShinies: Int
    public var anim: BanditAnim
    /// While > 0, `anim` stays locked (hurt / death / pickUp one-shots).
    public var animHold: Double
    /// Suppress duplicate land events (pounce whoosh → land → land).
    public var landCooldown: Double
    /// Armed after jump until early release cuts upward vy (or we land).
    public var jumpCutArmed: Bool
    /// Frames remaining where near-apex still counts as a stomp window.
    public var apexStompFrames: Int
    /// Frames after an airborne landing where overlapping a MOP still stomps (not hurts).
    public var landStompGrace: Int
    /// While > 0, one-way platforms do not collide (drop-through).
    public var dropThrough: Double
    /// Remaining dash/slide burst time.
    public var dashTimer: Double
    /// Cooldown before next dash.
    public var dashCooldown: Double
    /// Cooldown before next gadget throw.
    public var gadgetCooldown: Double
    /// Mid-air jumps remaining (1 = double jump). Refills on ground / wall jump.
    public var airJumpsRemaining: Int
    /// Nearest context interact (loot / door / vent) for the GRAB button.
    public var interactTarget: InteractKind

    public static func spawn(at position: Vec2, hearts: Int) -> BanditState {
        BanditState(
            position: position,
            velocity: .zero,
            facing: 1,
            onGround: false,
            onWallLeft: false,
            onWallRight: false,
            coyote: 0,
            jumpBuffer: 0,
            wallCling: 0,
            pouncing: false,
            flopping: false,
            combo: 0,
            comboTimer: 0,
            maskMode: false,
            maskTimer: 0,
            maskCharges: 0,
            hearts: hearts,
            invuln: 1.5,
            carriedShinies: 0,
            bankedShinies: 0,
            anim: .idle,
            animHold: 0,
            landCooldown: 0,
            jumpCutArmed: false,
            apexStompFrames: 0,
            landStompGrace: 0,
            dropThrough: 0,
            dashTimer: 0,
            dashCooldown: 0,
            gadgetCooldown: 0,
            airJumpsRemaining: 0,
            interactTarget: .none
        )
    }
}

public struct CrewCage: Equatable, Sendable, Identifiable {
    public var id: Int
    public var position: Vec2
    public var freed: Bool
    public var crewID: String
}

public struct ShinyPickup: Equatable, Sendable, Identifiable {
    public var id: Int
    public var position: Vec2
    public var alive: Bool
}

public enum MopAnim: Equatable, Sendable {
    case walk, attack, hurt, death
}

public struct MopEnemy: Equatable, Sendable, Identifiable {
    public var id: Int
    public var position: Vec2
    public var home: Vec2
    public var patrolSpan: Double
    public var phase: Double
    public var alive: Bool
    public var respawn: Double
    public var anim: MopAnim
    public var animHold: Double
    public var facing: Double
    /// While > 0, patrol freezes (post-hurt separation).
    public var stun: Double
}

public struct Checkpoint: Equatable, Sendable, Identifiable {
    public var id: Int
    public var position: Vec2
    public var activated: Bool
}

public enum RunPhase: Equatable, Sendable {
    case title
    case playing
    case won(seconds: Double, shinies: Int, combo: Int)
    case failed(FailReason)
}

public enum FailReason: Equatable, Sendable {
    case fellInWater
    case spiked
    case bagged
}
