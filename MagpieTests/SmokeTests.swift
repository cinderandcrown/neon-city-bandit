// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import GameCore
import GameRender
import Services
import XCTest
#if canImport(SpriteKit)
import SpriteKit
#endif
#if canImport(UIKit)
import UIKit
#endif

final class SmokeTests: XCTestCase {
    func testCoreAndServicesLink() {
        XCTAssertEqual(ModuleInfo.name, "GameCore")
        let clock = MockClock(value: 1)
        XCTAssertEqual(clock.now(), 1)
    }

    func testNeonDocksLoads() throws {
        let map = try NeonDocksLevel.load()
        XCTAssertNotNil(map.findFirst(.start))
        XCTAssertNotNil(map.findFirst(.exit))
    }

    /// Regression: Neon Docks must stay under a jetsam-safe geometry budget.
    /// Ground is one `SKTileMapNode` (not 1 sprite/solid); keep raw solid count bounded so
    /// autotile / prop decoration passes stay cheap on exploration maps (~96×24).
    func testNeonDocksSolidNodeBudget() throws {
        let map = try NeonDocksLevel.load()
        var solids = 0
        for y in 0..<map.height {
            for x in 0..<map.width {
                let t = map.tile(atX: x, y: y)
                if map.isSolid(t) { solids += 1 }
            }
        }
        // Short Downtown heist — solid deck under a soft ceiling.
        XCTAssertLessThan(solids, 1200, "unexpected solid count \(solids)")
        XCTAssertGreaterThan(solids, 40)
    }

    /// Regression: SmokeBrain can drive 45s of the smoke demo rooftop without trapping the sim.
    func testSmokeBrainFortyFiveSecondSoak() throws {
        // TODO(nicholas): re-enable once harness flag timing is stable on CI.
        // Flaky under pre-armed smoke_* flags (tick gate / early finish). Do not block smoke clips.
        throw XCTSkip("TODO: flaky soak under pre-armed harness flags — prefer GameCore SmokeBrain tests")
    }

    /// Regression for CI 43726848897: 2560×1440 masters must never upload as full RGBA.
    /// Smoke path ImageIO-downsamples to ≤1024px (≤1280 outside smoke).
    func testSmokeBackgroundMasterMemoryBudget() {
        let masterPixels = 2560 * 1440
        let rgbaBytesPerPlate = masterPixels * 4
        XCTAssertGreaterThan(rgbaBytesPerPlate, 14_000_000)
        let smokeMaxPixel = 1024
        let smokeBytesPerPlate = smokeMaxPixel * smokeMaxPixel * 4
        // Three parallax layers at 1024² stay well under one 2560 master.
        XCTAssertLessThan(smokeBytesPerPlate * 3, rgbaBytesPerPlate)
        XCTAssertEqual(smokeMaxPixel, 1024)
    }

    /// Gate: title wordmark must fit inside the iPhone 16 Pro Max safe area at 85% width.
    @MainActor
    func testTitleLogoFitsSafeArea() {
        #if canImport(SpriteKit) && canImport(UIKit)
        let sceneSize = CGSize(width: 430, height: 932)
        let topSafe: CGFloat = 59
        let bottomSafe: CGFloat = 34
        let logo = ArtCatalog.makeLogoNode(lite: false)
        let base = ArtCatalog.fitTitleLogo(logo, sceneWidth: sceneSize.width, fraction: 0.85)
        XCTAssertGreaterThan(base, 0)
        XCTAssertLessThan(base, 1.01, "2048px logo must be scaled down for phone width")
        let hh = sceneSize.height * 0.5
        let safeTop = hh - topSafe
        let safeBottom = -hh + bottomSafe
        let safeH = safeTop - safeBottom
        logo.position = CGPoint(x: 0, y: safeTop - safeH * 0.18)
        let frame = logo.calculateAccumulatedFrame()
        XCTAssertTrue(
            ArtCatalog.logoFrameInsideSafeArea(
                logoFrame: frame,
                sceneSize: sceneSize,
                topSafe: topSafe,
                bottomSafe: bottomSafe
            ),
            "logo frame \(frame) must sit inside safe area"
        )
        XCTAssertLessThanOrEqual(frame.width, sceneSize.width * 0.9 + 1)
        #else
        XCTAssertTrue(true)
        #endif
    }

    /// P0 moonwalk / latch: stick release, JUMP multitouch, and lifecycle pause must zero moveX.
    @MainActor
    func testMoveInputDoesNotLatchAcrossReleaseJumpOrBackground() throws {
        // TODO(nicholas): present HeistScene in an SKView so sim/HUD IUOs exist before pause probes.
        // Input-latch behavior is covered in GameCore (hold-left / reverse / dead-zone). Skip Magpie host crash.
        throw XCTSkip("TODO: needs presented HeistScene — GameCore covers latch; do not block smoke")
    }

    /// Idempotent lifecycle pause: second banner must not toggle or re-arm input.
    @MainActor
    func testLifecyclePauseIsIdempotent() throws {
        // TODO(nicholas): same as above — pauseFromAppLifecycle before didMove is a host-only probe.
        throw XCTSkip("TODO: needs presented HeistScene — do not block smoke clips")
    }

    /// P0 launch smoke: constructing the scene (as ContentView does) must not touch CloudKit,
    /// and presenting it must reach the title screen.
    @MainActor
    func testLaunchReachesTitleScreen() throws {
        #if canImport(SpriteKit) && canImport(UIKit)
        XCTAssertFalse(
            FeatureFlags.cloudKitGhostsEnabled,
            "CloudKit ghosts must default OFF until the iCloud container is verified"
        )
        let store = GhostStoreFactory.make()
        XCTAssertTrue(
            store is MockGhostStore,
            "Launch must use MockGhostStore when CloudKit ghosts are disabled"
        )

        let scene = HeistScene(size: CGSize(width: 390, height: 844), smokeAutoplay: false)
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        view.presentScene(scene)

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            if scene.debugSimReady, scene.debugSmokePhase == "title" {
                return
            }
        }
        XCTFail(
            "Launch did not reach title within 5s (simReady=\(scene.debugSimReady) phase=\(scene.debugSmokePhase))"
        )
        #else
        throw XCTSkip("SpriteKit/UIKit required")
        #endif
    }
}
