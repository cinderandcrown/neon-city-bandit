// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import Foundation

/// Level / meta tuning. Movement & combat *feel* live in `GameFeel` (`feel`).
public struct Tuning: Equatable, Sendable {
    public var tileSize: Double = 32
    public var simHz: Double = 60

    /// All movement / stomp / stick / button feel numbers.
    public var feel: GameFeel = .default

    // Combat / meta (not pure “feel”, but shared with sim)
    /// Window to chain stomps into Mask. Nicholas APPROVED 2026-11-17: **12 s**
    /// (replaces the old 4.5 s / 0.4 s ground-break window).
    public var comboGroundGrace: Double = 12.0
    public var comboCap: Int = 10
    /// Stomps to trigger Mask. Nicholas APPROVED 2026-11-17: **3** (replaces 5).
    public var maskModeAtCombo: Int = 3
    /// Mask Mode smash window when the player spends a full meter charge.
    public var maskDuration: Double = 5
    public var hearts: Int = 3
    public var shiniesToHint: Int = 12

    // Camera (consumed by render; mirrored here for tests)
    public var cameraLeadTiles: Double = 2.2
    public var cameraSmooth: Double = 0.14

    public var dt: Double { 1.0 / simHz }

    // MARK: - Feel passthroughs (keep call sites + DEBUG menu keypaths short)

    public var walkSpeed: Double {
        get { feel.walkSpeed }
        set { feel.walkSpeed = newValue }
    }
    public var runSpeed: Double {
        get { feel.runSpeed }
        set { feel.runSpeed = newValue }
    }
    public var walkRunStickThreshold: Double {
        get { feel.walkRunStickThreshold }
        set { feel.walkRunStickThreshold = newValue }
    }
    public var maxFall: Double {
        get { feel.maxFall }
        set { feel.maxFall = newValue }
    }
    public var gravity: Double {
        get { feel.gravity }
        set { feel.gravity = newValue }
    }
    public var jumpVelocity: Double {
        get { feel.jumpVelocity }
        set { feel.jumpVelocity = newValue }
    }
    public var coyoteSeconds: Double {
        get { feel.coyoteSeconds }
        set { feel.coyoteSeconds = newValue }
    }
    public var jumpBufferSeconds: Double {
        get { feel.jumpBufferSeconds }
        set { feel.jumpBufferSeconds = newValue }
    }
    public var wallSlideSpeed: Double {
        get { feel.wallSlideSpeed }
        set { feel.wallSlideSpeed = newValue }
    }
    public var wallJumpVelocityX: Double {
        get { feel.wallJumpVelocityX }
        set { feel.wallJumpVelocityX = newValue }
    }
    public var wallJumpVelocityY: Double {
        get { feel.wallJumpVelocityY }
        set { feel.wallJumpVelocityY = newValue }
    }
    public var wallClingSeconds: Double {
        get { feel.wallClingSeconds }
        set { feel.wallClingSeconds = newValue }
    }
    public var pounceBoostX: Double {
        get { feel.pounceBoostX }
        set { feel.pounceBoostX = newValue }
    }
    public var pounceBoostY: Double {
        get { feel.pounceBoostY }
        set { feel.pounceBoostY = newValue }
    }
    public var bellyFlopFallBoost: Double {
        get { feel.bellyFlopFallBoost }
        set { feel.bellyFlopFallBoost = newValue }
    }
    public var stompBounceVelocity: Double {
        get { feel.stompBounceVelocity }
        set { feel.stompBounceVelocity = newValue }
    }
    public var invulnSeconds: Double {
        get { feel.invulnSeconds }
        set { feel.invulnSeconds = newValue }
    }

    public static let `default` = Tuning()
}
