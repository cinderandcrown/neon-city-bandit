// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import GameCore
import XCTest
@testable import GameRender

final class GameRenderTests: XCTestCase {
    func testRenderDependsOnCore() {
        XCTAssertEqual(RenderInfo.dependsOnCore, ModuleInfo.name)
    }

    func testRenderModuleName() {
        XCTAssertEqual(RenderInfo.name, "GameRender")
    }

    #if canImport(SpriteKit) && canImport(UIKit)
    /// Glow is baked into PNGs; solids stay one visual node (SKTileMap / atlas).
    func testBakedGlowNodeBudget() {
        XCTAssertEqual(ArtCatalog.expectedNodesPerSolidTile, 1)
        XCTAssertGreaterThan(ArtCatalog.paletteMagenta.r, 0.8)
        XCTAssertGreaterThan(ArtCatalog.paletteTeal.b, 0.8)
    }

    func testTitleArtIsNeonCityBandit() {
        XCTAssertFalse(TitleArt.logoCandidates.isEmpty)
        XCTAssertEqual(TitleArt.logoCandidates.first, "ui/logo_b1_holo_glass@1024")
        XCTAssertTrue(TitleArt.compactLogoCandidates.contains("ui/logo_b1_holo_glass_compact"))
        XCTAssertTrue(TitleArt.titleKeyArtCandidates.contains("ui/title_leap@1024"))
        XCTAssertEqual(TitleArt.displayTitle, "The Neon City Bandit")
        XCTAssertTrue(TitleArt.fallbackWordmark.contains("BANDIT"))
        XCTAssertFalse(TitleArt.displayTitle.localizedCaseInsensitiveContains("Trash Panda"))
        XCTAssertFalse(TitleArt.displayTitle.localizedCaseInsensitiveContains("Magpie"))
        XCTAssertTrue(TitleArt.assetCredits.contains("Spriterrific"))
        XCTAssertTrue(TitleArt.assetCredits.localizedCaseInsensitiveContains("Cinder"))
    }

    func testPublisherIdentCopy() {
        XCTAssertEqual(PublisherIdent.presentsLine, "Cinder & Crown Creative Presents")
        XCTAssertTrue(PublisherIdent.logoCredit.contains("used by permission"))
        XCTAssertFalse(PublisherIdent.presentsLine.contains("Asset"))
        // Trash Stack parity — fixed 168 pt mute mark, never stretched to scene.
        XCTAssertEqual(PublisherIdent.logoPointSize, 168, accuracy: 0.1)
        XCTAssertEqual(PublisherIdent.titleFontSize, 17, accuracy: 0.1)
        XCTAssertEqual(PublisherIdent.titleTracking, 3.2, accuracy: 0.01)
    }

    /// West-facing source sheets: body.xScale = −sign(facing) so muzzle leads travel.
    func testBanditBodyXScaleFollowsVelocitySign() {
        XCTAssertEqual(BanditVisual.bodyXScale(facingSign: 1, sheetsFaceWest: true), -1)
        XCTAssertEqual(BanditVisual.bodyXScale(facingSign: -1, sheetsFaceWest: true), 1)
        XCTAssertEqual(BanditVisual.bodyXScale(facingSign: 1, sheetsFaceWest: false), 1)
        XCTAssertEqual(BanditVisual.bodyXScale(facingSign: -1, sheetsFaceWest: false), -1)
    }

    func testTitleButtonFramesNonOverlappingHelper() {
        let a = CGRect(x: 0, y: 0, width: 40, height: 20)
        let b = CGRect(x: 50, y: 0, width: 40, height: 20)
        let c = CGRect(x: 30, y: 0, width: 40, height: 20)
        XCTAssertTrue(ArtCatalog.framesNonOverlapping([a, b], gap: 4))
        XCTAssertFalse(ArtCatalog.framesNonOverlapping([a, c], gap: 4))
        // Title bar layout: 140pt buttons at 0.68 scale, centers spaced by width+14.
        let btnW: CGFloat = 140 * 0.68
        let spacing = btnW + 14
        let map = CGRect(x: -spacing - btnW * 0.5, y: -14, width: btnW, height: 28)
        let mute = CGRect(x: -btnW * 0.5, y: -14, width: btnW, height: 28)
        let daily = CGRect(x: spacing - btnW * 0.5, y: -14, width: btnW, height: 28)
        XCTAssertTrue(ArtCatalog.framesNonOverlapping([map, mute, daily], gap: 2))
    }
    #endif
}
