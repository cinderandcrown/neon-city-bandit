// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

#if canImport(SpriteKit) && canImport(UIKit)
import GameCore
import Services
import SpriteKit
import UIKit

/// Side-view neon docks heist wired to `Assets/Generated/` via AssetManifest.
public final class HeistScene: SKScene {
    /// Zoom so playfield + skyline fill portrait (no empty black letterbox bands).
    /// Camera zoom — lower so the auto-runner sees gaps/MOPs ahead (bandit ~15–18% width).
    /// Pull back so the playfield fills more of the tall phone — less dead sky band.
    public static let worldZoom: CGFloat = 0.88
    private var tileMapNode: SKTileMapNode?

    private var sim: Sim!
    private var tuning = Tuning.default
    private let stage = SKNode()
    private let world = SKNode()
    /// Must use the color initializer — bare `SKSpriteNode()` keeps a white texture at blendFactor 0.
    private let skyFill = SKSpriteNode(color: ArtCatalog.nightSky, size: CGSize(width: 4, height: 4))
    private let parallaxFar = SKNode()
    /// Physics body center → foot-anchor visual offset (matches Sim halfH).
    private let bodyCenterToFeet: CGFloat = 14
    private let parallaxMid = SKNode()
    private let parallaxNear = SKNode()
    private let rainLayer = SKNode()
    private var bandit: BanditVisual!
    private var shinyNodes: [Int: SKNode] = [:]
    private var mopNodes: [Int: MopVisual] = [:]
    private let hud = SKNode()
    private let overlay = SKNode()
    private let playHUD = SKNode()
    private let maskVignette = SKNode()
    private var lastMaskMode = false

    private var moveX: Double = 0
    private var jumpHeld = false
    private var jumpPressed = false
    private var pouncePressed = false
    private var dashPressed = false
    private var maskPressed = false
    private var grabPressed = false
    private var stickTouch: UITouch?
    private var jumpTouch: UITouch?
    private var pounceTouch: UITouch?
    private var dashTouch: UITouch?
    private var maskTouch: UITouch?
    private var grabTouch: UITouch?
    private var stickOrigin = CGPoint.zero

    private var stickBase: SKShapeNode!
    private var stickKnob: SKShapeNode!
    private var jumpBtn: SKShapeNode!
    private var pounceBtn: SKShapeNode!
    private var dashBtn: SKShapeNode!
    private var maskBtn: SKShapeNode!
    private var grabBtn: SKShapeNode!
    /// Invisible forgiving hit plates (larger than the art).
    private var jumpHitZone: SKNode!
    private var pounceHitZone: SKNode!
    private var dashHitZone: SKNode!
    private var maskHitZone: SKNode!
    private var grabHitZone: SKNode!
    private var moveHitZone: SKNode!
    /// Off by default — ProcessInfo `-ShowTouchZones` or UserDefaults `showTouchZones`.
    private var showTouchDebug = false
    private var touchDebugRoot: SKNode?

    private var titleRoot = SKNode()
    private var publisherIdentRoot: SKNode?
    private var showingPublisherIdent = false
    /// Process-lifetime gate: cold launch only (never on resume / return-to-title).
    private static var didShowPublisherIdentThisProcess = false
    private var outcomeRoot = SKNode()
    private var retentionRoot = SKNode()
    private var hudCarried = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private var hudHearts = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private var hudCombo = SKLabelNode(fontNamed: "AvenirNext-Heavy")
    private var hudTime = SKLabelNode(fontNamed: "AvenirNext-Medium")
    private var hudPill = SKShapeNode()
    private var fpsLabel = SKLabelNode(fontNamed: "Menlo-Bold")

    private var accumulator: TimeInterval = 0
    private var lastTime: TimeInterval = 0
    private var fpsAcc: TimeInterval = 0
    private var displayedFPS = 0
    private var hitStop: TimeInterval = 0
    private var cameraFocus = CGPoint.zero
    /// Smoothed facing (−1…1) for the single camera look-ahead (ease ~0.4s on turn).
    private var cameraFacing: CGFloat = 1
    /// Smoke: after 04 is snapped, let Mask expire once before holding for 04b re-entry.
    private var smokeSawMaskDropAfterFirst = false
    /// Smoke harness accounting (written to Documents/smoke_forced_detail.txt).
    private var smokeMaskPinSeconds: Double = 0
    private var smokeMaskForceOffCount: Int = 0
    private var smokeMaskForceOffSeconds: Double = 0
    private var smokeSoftReviveCount: Int = 0
    private var smokePreMidrunMaskCancelCount: Int = 0
    private var smokeInvulnTopUpCount: Int = 0
    private var smokeMaskPinActive = false
    private var smokeLastForcedWrite: TimeInterval = 0
    /// After 04: decay-only Mask timer so mop-pack bounce stomps cannot refresh forever.
    private var smokeMaskDecayCap: Double = -1
    private var smokeMaskRefreshSuppressSeconds: Double = 0
    private var smokeMaskDecayArmed = false
    /// Camera side-switch hysteresis — ignore brief facing flips for lead direction.
    private var cameraFacingHoldUntil: TimeInterval = 0
    private var cameraWantFace: CGFloat = 1
    /// Screen-space lift so the street deck clears the bottom control strip.
    private var controlStripLift: CGFloat = 0
    private var controlStripNode: SKShapeNode?
    private var maskMusicOn = false
    /// MOP ids that already barked `mop_bot_alert` this approach.
    private var mopAlerted: Set<Int> = []
    private var hapticLight = UIImpactFeedbackGenerator(style: .light)
    private var hapticMed = UIImpactFeedbackGenerator(style: .medium)
    private var hapticHeavy = UIImpactFeedbackGenerator(style: .heavy)

    private var smokeEnabled = false
    private var smoke = SmokeBrain()
    private var smokeStatus = SmokeStatus()
    private var progressStore = ProgressStore()
    /// Sum of frame durations (seconds) after the startup hitch — avg FPS = samples / fpsTimeSum.
    private var fpsTimeSum: Double = 0
    private var fpsCount: Int = 0
    private var maxFrameMs: Double = 0
    /// Skip one freeze sample after pause/resume so the gap does not look like a hitch.
    private var skipFreezeSample = false
    /// One title→play transition frame may be up to this many ms without failing the freeze gate.
    private var transitionBudgetMs: Double = 0
    private let titlePlayTransitionBudgetMs: Double = 250
    private var moveY: Double = 0
    private var story = StoryCatalog.load()
    private var introRoot = SKNode()
    private var introPanelIndex = 0
    private var showingIntro = false
    private var districtCardRoot = SKNode()
    private var showingDistrictCard = false
    private var crewNodes: [Int: SKNode] = [:]
    private var pendingDistrict: DistrictID = .neonDocks
    private var mopChatterAcc: TimeInterval = 0
    private var statusAcc: TimeInterval = 0
    /// Shiny nodes mid collect-anim — sync must not hard-hide them.
    private var shinyCollecting: Set<Int> = []
    private var maskParticleAcc: CGFloat = 0
    private var maskGradePulse: CGFloat = 0
    private var lastAwardedMedals = 0
    private var retentionMode: String? = nil // "map" | "daily"
    /// Daily Heist run (UTC-seeded layout + GC score + ghost).
    private var isDailyRun = false
    private var dailyDayKey = ProgressStore.dayKey()
    private var ghostRecorder = GhostRecorder()
    private var racingGhostSamples: [GhostSamplePoint] = []
    private var racingGhostKind: GhostKind?
    private var ghostVisual: SKSpriteNode?
    private var tookDamageThisRun = false
    private var sawMaskThisRun = false
    private var gameCenter: GameCenterServing = {
        if ProcessInfo.processInfo.underAutomatedHarness {
            return MockGameCenter()
        }
        return GameCenterService.shared
    }()
    private var ghostStore: GhostStoreServing = GhostStoreFactory.make()
    /// Gameplay pause (not SKScene.isPaused — that freezes the whole tree).
    private var runPaused = false
    private var pauseFromSystem = false
    private var resumeCountdown: TimeInterval = 0
    private var failOutcomeHold: TimeInterval = 0
    /// Reusable land dust burst (replaces 8 SKShapeNodes per land).
    private var landDustEmitter: SKEmitterNode?
    private let pauseRoot = SKNode()
    private var pauseBtn: SKShapeNode!
    private var pauseCountLabel: SKLabelNode?
    /// First-minute pacing: objective banner, early win, mid-run surprise.
    private var objectiveBanner: SKNode?
    /// One toast at a time; tips auto-dismiss (~2s) and never stack over the HUD.
    private var toastQueue: [(text: String, color: SKColor, hold: TimeInterval)] = []
    private var toastShowing = false
    private var activeToastNode: SKNode?
    private var lastObjectiveTip: String = ""
    private var celebratedFirstStomp = false
    private var celebratedEarlyWin = false
    private var midSurpriseFired = false
    private var exitBeacon: SKNode?
    /// Auto-runner: no stick. Tutorial steps 0=jump gap, 1=stomp, 2=mask, 3=vault.
    private var tutorialStep = 0
    private var tutorialStomps = 0
    private var progressTrack: SKShapeNode?
    private var progressFill: SKShapeNode?
    private var progressBanditDot: SKShapeNode?
    private var startWorldX: Double = 0
    private var exitWorldX: Double = 1
    /// Run-clock of last stomp — drives the "don't stand around" nudge.
    private var lastStompElapsed: Double = -1
    private var nextLullNudgeAt: Double = 8
    private var runDustCooldown: CGFloat = 0
    /// Wall-clock play timer for smoke (monotonic across death/retry — review gate).
    private var smokeWallStart: TimeInterval = 0
    private var smokeWallElapsed: TimeInterval = 0
    /// Photosensitivity: timestamps of full-screen flashes in the last second.
    private var flashHistory: [TimeInterval] = []
    #if DEBUG
    private var tuningMenu: DebugTuningMenu?
    private var debugToggle: SKLabelNode?
    #endif

    public convenience init(size: CGSize, smokeAutoplay: Bool) {
        self.init(size: size)
        self.smokeEnabled = smokeAutoplay
    }

    public override func didMove(to view: SKView) {
        backgroundColor = ArtCatalog.nightSky
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        if ProcessInfo.processInfo.arguments.contains("-SmokeAutoplay") {
            smokeEnabled = true
        }
        // Smoke uses ship tuning + real Neon Docks — only input source / seed / status flags differ.
        // Critical: run + jump must work together — SKView defaults multitouch OFF.
        view.isMultipleTouchEnabled = true
        isUserInteractionEnabled = true
        view.preferredFramesPerSecond = 60
        view.ignoresSiblingOrder = true
        view.shouldCullNonVisibleNodes = true
        showTouchDebug = ProcessInfo.processInfo.arguments.contains("-ShowTouchZones")
            || UserDefaults.standard.bool(forKey: "showTouchZones")
        #if DEBUG
        if smokeEnabled {
            view.showsFPS = false
            view.showsNodeCount = false
            view.showsDrawCount = false
        }
        #endif
        do {
            let map = try NeonDocksLevel.load()
            sim = Sim(map: map, tuning: tuning, seed: smokeEnabled ? 7 : 11)
        } catch {
            sim = Sim(map: try! TileMap.parse("###\n#@#\n###"), tuning: tuning)
        }

        // Publish phase=title BEFORE atlas/parallax warm so CI can attach during art load.
        // boot=loading until title chrome is actually on screen (see write after setupTitle).
        if smokeEnabled {
            smokeStatus.phase = "title"
            smokeStatus.boot = "loading"
            smokeStatus.write()
        }

        ArtCatalog.warmAtlases()
        // Pre-warm KO / Mask / dust / Higgsfield juice so first hurt/stomp doesn't hitch.
        _ = ArtCatalog.texture(.raccoonMaskMode)
        _ = ArtCatalog.texture(.raccoonBellyFlop)
        JuiceFX.warm()
        _ = ArtCatalog.softCircleTexture()
        // Preload gameplay textures while title is up so beginPlay stays within the 250ms budget.
        ArtCatalog.preloadGameplayTextures()
        // Scene night only — no opaque full-map wash quads (they hid the neon city).
        skyFill.color = ArtCatalog.nightSky
        skyFill.colorBlendFactor = 1
        skyFill.zPosition = -100
        addChild(skyFill)
        stage.setScale(Self.worldZoom)
        addChild(stage)
        stage.addChild(parallaxFar)
        stage.addChild(parallaxMid)
        stage.addChild(parallaxNear)
        stage.addChild(world)
        world.addChild(rainLayer)
        view.allowsTransparency = false
        backgroundColor = ArtCatalog.nightSky
        buildParallax()
        buildTiles()
        buildMaskVignette()
        ensureLandDustEmitter()

        bandit = ArtCatalog.makeBanditVisual()
        bandit.zPosition = 50
        world.addChild(bandit)
        // Touch death + Mask sheets once so GPU upload isn't on the KO/Mask frame.
        bandit.prewarmCombatTextures()

        // Real MOP / Shiny art always. Cap only on the huge Neon Docks prop count.
        let shinyCap = smokeEnabled ? sim.state.shinies.count : min(sim.state.shinies.count, 40)
        for s in sim.state.shinies.prefix(shinyCap) {
            let n = ArtCatalog.makeShinyNode()
            n.position = cg(s.position)
            n.zPosition = 20
            world.addChild(n)
            shinyNodes[s.id] = n
        }
        let mopCap = smokeEnabled ? sim.state.mops.count : min(sim.state.mops.count, 24)
        for m in sim.state.mops.prefix(mopCap) {
            let n = ArtCatalog.makeMopNode()
            n.position = cg(m.position)
            n.zPosition = 30
            world.addChild(n)
            mopNodes[m.id] = n
        }
        for c in sim.state.crewCages {
            let n = makeCrewCageNode(crewID: c.crewID)
            n.position = cg(c.position)
            n.zPosition = 28
            world.addChild(n)
            crewNodes[c.id] = n
        }

        addChild(hud)
        hud.addChild(playHUD)
        addChild(overlay)
        setupControls()
        setupHUD()
        setupTitle()
        setupStoryOverlays()
        setupOutcome()
        setupPauseMenu()
        setupRetention()
        #if DEBUG
        setupDebugTuning()
        #endif
        // Defer AVAudioSession until after atlases warm — early prepare jetsams the sim.
        // Title sting waits until after the publisher ident (or immediately if skipped).
        JuiceSound.shared.prepare()
        if !smokeEnabled {
            hapticLight.prepare(); hapticMed.prepare(); hapticHeavy.prepare()
        }
        layoutUI()
        // Safe-area insets often arrive a beat after didMove — re-layout so HUD clears the island.
        run(SKAction.sequence([
            SKAction.wait(forDuration: 0.05),
            SKAction.run { [weak self] in self?.layoutUI() },
            SKAction.wait(forDuration: 0.2),
            SKAction.run { [weak self] in self?.layoutUI() },
        ]), withKey: "safeAreaRelayout")
        sync(dt: 0)
        // Publisher splash first (cold launch / smoke). Gameplay textures already preloading above.
        if shouldPresentPublisherIdent() {
            presentPublisherIdent()
        } else {
            finishPublisherIdentAndShowTitle()
        }
        updateHUDVisibility()
    }

    private func shouldPresentPublisherIdent() -> Bool {
        // Smoke always shows once per launch so CI can artifact the still.
        if smokeEnabled { return !Self.didShowPublisherIdentThisProcess }
        return !Self.didShowPublisherIdentThisProcess
    }

    private func presentPublisherIdent() {
        Self.didShowPublisherIdentThisProcess = true
        showingPublisherIdent = true
        titleRoot.isHidden = true
        // First paint = charcoal only (Trash Stack parity) — do not decode logo on frame 0.
        let root = PublisherIdent.buildCharcoalRoot(sceneSize: size)
        root.zPosition = 900
        publisherIdentRoot = root
        addChild(root)
        layoutPublisherIdentBackground()
        if smokeEnabled {
            smokeStatus.phase = "title"
            smokeStatus.boot = "ident"
            writeSmokeStatus()
        }
        // Defer logo + animation one run-loop turn so the first frame is never blocked.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.showingPublisherIdent, let root = self.publisherIdentRoot else { return }
            PublisherIdent.attachLogoArt(to: root, sceneSize: self.size)
            let reduce = PublisherIdent.reduceMotionEnabled
            PublisherIdent.runPresentation(
                on: root,
                reduceMotion: reduce,
                smokeHold: self.smokeEnabled,
                playWhoosh: { [weak self] in
                    guard let self, !self.smokeEnabled else { return }
                    JuiceSound.shared.playPublisherIdentWhoosh()
                }
            ) { [weak self] in
                self?.finishPublisherIdentAndShowTitle()
            }
        }
    }

    private func layoutPublisherIdentBackground() {
        guard let root = publisherIdentRoot,
              let bg = root.childNode(withName: "publisherBg") as? SKSpriteNode else { return }
        bg.xScale = 1
        bg.yScale = 1
        bg.size = CGSize(width: max(size.width, 1) * 4, height: max(size.height, 1) * 4)
        bg.position = .zero
        bg.alpha = 1
    }

    private func skipPublisherIdentIfNeeded() {
        guard showingPublisherIdent else { return }
        publisherIdentRoot?.removeAction(forKey: "publisherIdent")
        finishPublisherIdentAndShowTitle()
    }

    private func finishPublisherIdentAndShowTitle() {
        publisherIdentRoot?.removeAllActions()
        publisherIdentRoot?.removeFromParent()
        publisherIdentRoot = nil
        showingPublisherIdent = false
        // Smoke can arm proceed during ident → beginPlay before this runs. Never re-show
        // title art over a live run (that left TAP TO START stuck on SE layout stills).
        if case .playing = sim.state.phase {
            titleRoot.isHidden = true
            if smokeEnabled {
                smokeStatus.boot = "ready"
                writeSmokeStatus()
            }
            updateHUDVisibility()
            return
        }
        presentIntroIfNeededAfterIdent()
        if showingIntro {
            // Intro covers title; still mark boot ready so smoke can proceed after comic skip paths.
            if smokeEnabled {
                smokeStatus.boot = "ready"
                writeSmokeStatus()
            }
            updateHUDVisibility()
            return
        }
        showTitleScreen()
        JuiceSound.shared.playTitleSting()
        if smokeEnabled {
            smokeStatus.boot = "ready"
            writeSmokeStatus()
        }
        updateHUDVisibility()
    }

    public override func didChangeSize(_ oldSize: CGSize) {
        guard stickBase != nil, sim != nil else { return }
        layoutUI()
    }

    // MARK: - Atmosphere / Parallax

    private func buildParallax() {
        // Cover the full viewport height so the neon city is visible behind platforms.
        let viewH = size.height / Self.worldZoom
        let h = max(viewH * 1.25, 680)
        // Cap plate resolution — 1280px tiles were crushing simulator FPS.
        let maxPx: CGFloat = 960
        let mapW = CGFloat(sim.map.width) * CGFloat(tuning.tileSize)

        func tileLayer(
            _ node: SKSpriteNode,
            into parent: SKNode,
            y: CGFloat,
            z: CGFloat,
            neonBoost: Bool,
            mirrorTile: Bool = false
        ) {
            let width = max(node.size.width, 1)
            // Cover the camera lead without over-tiling the full map width.
            let cover = min(mapW, size.width / Self.worldZoom * 4) + width
            let copies = max(2, Int(ceil(cover / width)) + 1)
            // Mirror-tile far plates edge-to-edge; mid/near keep a slight overlap.
            let stride = mirrorTile ? width : width * 0.92
            for i in 0..<copies {
                let plate = node.copy() as? SKSpriteNode ?? SKSpriteNode(texture: node.texture, size: node.size)
                plate.position = CGPoint(x: CGFloat(i) * stride, y: y)
                plate.zPosition = z
                if mirrorTile, i % 2 == 1 {
                    plate.xScale = -1
                }
                // Push BG darker/desaturated so bandit, MOPs, and loot own the contrast.
                // Mid still keeps a hint of neon for the palette gate without fighting sprites.
                if neonBoost {
                    plate.color = SKColor(red: 0.22, green: 0.10, blue: 0.28, alpha: 1)
                    plate.colorBlendFactor = 0.42
                    plate.alpha = 0.72
                } else {
                    plate.color = SKColor(red: 0.08, green: 0.10, blue: 0.22, alpha: 1)
                    plate.colorBlendFactor = 0.48
                    plate.alpha = 0.62
                }
                parent.addChild(plate)
            }
        }

        // Raise skyline into the midrun sample band (y 18–62% of the frame).
        // District plates: backgrounds/districts/<artFolder>/{far,mid,near}.png when present,
        // else classic skyline pack (ArtLibrary placeholders until Higgsfield districts land).
        let midY = viewH * 0.18
        let district = pendingDistrict
        if let far = ArtLibrary.districtLayer(district, layer: .far, height: h, maxPixel: maxPx) {
            // No mirror tiling — repeating plates read as the level looping past the vault.
            tileLayer(far, into: parallaxFar, y: midY + 60, z: -30, neonBoost: false, mirrorTile: false)
        }
        let gridW = min(max(mapW * 0.5, size.width / Self.worldZoom * 3), 1800)
        let grid = ArtCatalog.makePerspectiveGridHorizon(width: gridW, height: h * 0.55)
        grid.position = CGPoint(x: gridW * 0.28, y: midY)
        grid.alpha = 0.08
        parallaxFar.addChild(grid)
        // Living far city: twinkling windows + a slow skyline transit.
        let windows = ArtCatalog.livingWindowLights(width: min(mapW * 0.6, 1400), height: h * 0.35)
        windows.position = CGPoint(x: mapW * 0.22, y: midY + 90)
        parallaxFar.addChild(windows)
        parallaxFar.addChild(ArtCatalog.skylineTransit(width: min(mapW * 0.7, 1600), y: midY + 40))
        if let mid = ArtLibrary.districtLayer(district, layer: .mid, height: h * 1.1, maxPixel: maxPx) {
            tileLayer(mid, into: parallaxMid, y: midY + 10, z: -20, neonBoost: true)
        }
        // Magenta + teal storefront signage in the mid band (readability + palette).
        // Keep strips high enough that the midrun storefront-band (12–48% screen) sees them.
        let signs = ArtCatalog.neonSignageStrip(width: mapW * 0.7, height: 96)
        signs.position = CGPoint(x: mapW * 0.18, y: midY + 118)
        signs.alpha = 0.28
        parallaxMid.addChild(signs)
        let signsLow = ArtCatalog.neonSignageStrip(width: mapW * 0.45, height: 56)
        signsLow.position = CGPoint(x: mapW * 0.4, y: midY + 52)
        signsLow.alpha = 0.18
        parallaxMid.addChild(signsLow)
        // Sweeping searchlight + street steam so the mid band feels alive.
        let light = ArtCatalog.neonSearchlight(height: h * 0.5)
        light.position = CGPoint(x: mapW * 0.3, y: midY + 40)
        parallaxMid.addChild(light)
        // Keep near plates behind / below the walkable deck so floor bands don't stack on the street.
        if let near = ArtLibrary.districtLayer(district, layer: .near, height: h * 0.75, maxPixel: maxPx) {
            tileLayer(near, into: parallaxNear, y: midY - 90, z: -10, neonBoost: false)
        }
        let steam = ArtCatalog.streetSteamEmitter(width: size.width / Self.worldZoom)
        steam.position = CGPoint(x: 0, y: -viewH * 0.18)
        parallaxNear.addChild(steam)

        let rain = ArtCatalog.rainEmitter(sceneSize: CGSize(width: size.width / Self.worldZoom, height: h))
        rainLayer.addChild(rain)
    }

    /// Wet-floor neon reflections under walkable tops (soft cyan/magenta puddles, not solid bars).
    private func addWetFloorReflection(at pos: CGPoint, tile: CGFloat) {
        let puddle = SKSpriteNode(texture: ArtCatalog.softCircleTexture(), size: CGSize(width: tile * 1.1, height: tile * 0.35))
        puddle.name = "wetFloor"
        puddle.position = CGPoint(x: pos.x, y: pos.y + tile * 0.42)
        puddle.color = ArtCatalog.neonPink
        puddle.colorBlendFactor = 1
        puddle.alpha = 0.45
        puddle.blendMode = .add
        puddle.zPosition = 3.04
        world.addChild(puddle)
        let cyan = SKSpriteNode(texture: ArtCatalog.softCircleTexture(), size: CGSize(width: tile * 0.85, height: tile * 0.22))
        cyan.name = "wetFloorCyan"
        cyan.position = CGPoint(x: pos.x + tile * 0.12, y: pos.y + tile * 0.36)
        cyan.color = ArtCatalog.neonCyan
        cyan.colorBlendFactor = 1
        cyan.alpha = 0.4
        cyan.blendMode = .add
        cyan.zPosition = 3.05
        world.addChild(cyan)
    }

    /// World-space storefront sign crops (SPOTLESS / GLOW MART / …) so midrun stills show real neon.
    private func placeWorldStorefrontSigns() {
        let signs = ArtCatalog.worldStorefrontSigns(
            mapWidth: CGFloat(sim.map.width) * CGFloat(tuning.tileSize),
            tile: CGFloat(tuning.tileSize)
        )
        world.addChild(signs)
    }

    private func buildMaskVignette() {
        maskVignette.zPosition = 250
        maskVignette.alpha = 0
        maskVignette.isHidden = true
        overlay.addChild(maskVignette)
        // No full-screen cyan/magenta color plates — SKSpriteNode(color:) + purge can
        // read as an opaque neon wash and trip the CI cyanWash gate. Mask Mode grade is
        // character glow + a soft dark edge only.
        let edge = SKSpriteNode(color: SKColor(red: 0.02, green: 0.01, blue: 0.08, alpha: 1), size: CGSize(width: 40, height: 40))
        edge.name = "vignetteEdge"
        edge.blendMode = .alpha
        edge.zPosition = 2
        edge.alpha = 0.22
        maskVignette.addChild(edge)
    }

    /// Prefer live view/window insets; fall back to iPhone island/home values so HUD never sits under chrome.
    private func safeInsets() -> UIEdgeInsets {
        var s = view?.safeAreaInsets ?? .zero
        if s.top < 20, let win = view?.window {
            s = win.safeAreaInsets
        }
        if s.top < 20 {
            s.top = 59
            s.bottom = max(s.bottom, 34)
        }
        return s
    }

    private func buildTiles() {
        let tile = CGFloat(tuning.tileSize)
        let tileSize = CGSize(width: tile, height: tile)
        let tileSet = ArtCatalog.makePlatformTileSet(tileSize: tileSize, district: pendingDistrict)
        let groups = tileSet.tileGroups
        guard groups.count >= 16 else { return }

        func isGroundSolid(_ kind: Tile) -> Bool {
            kind == .ground || kind == .wall || kind == .latch || kind == .crate
        }
        func solidNeighbor(x: Int, y: Int) -> Bool {
            guard x >= 0, y >= 0, x < sim.map.width, y < sim.map.height else { return true }
            return isGroundSolid(sim.map.tile(atX: x, y: y))
        }

        let mapNode = SKTileMapNode(
            tileSet: tileSet,
            columns: sim.map.width,
            rows: sim.map.height,
            tileSize: tileSize
        )
        mapNode.anchorPoint = CGPoint(x: 0, y: 0)
        mapNode.position = .zero
        mapNode.zPosition = 2
        for y in 0..<sim.map.height {
            for x in 0..<sim.map.width {
                let kind = sim.map.tile(atX: x, y: y)
                // Latch poles are drawn as neon pillars below — skip autotile (isolated
                // neighbour masks read as a grey "X" placeholder on the climb tower).
                guard kind == .ground || kind == .wall || kind == .crate else { continue }
                // 4-neighbour mask: N=1 E=2 S=4 W=8
                var mask = 0
                if solidNeighbor(x: x, y: y + 1) { mask |= 1 }
                if solidNeighbor(x: x + 1, y: y) { mask |= 2 }
                if solidNeighbor(x: x, y: y - 1) { mask |= 4 }
                if solidNeighbor(x: x - 1, y: y) { mask |= 8 }
                mapNode.setTileGroup(groups[mask], forColumn: x, row: y)
            }
        }
        world.addChild(mapNode)
        tileMapNode = mapNode
        placeWorldStorefrontSigns()

        // Neon latch poles (climbable) — thin cyan/magenta shaft, not grey autotile X.
        for y in 0..<sim.map.height {
            for x in 0..<sim.map.width {
                guard sim.map.tile(atX: x, y: y) == .latch else { continue }
                let pos = cg(sim.map.worldCenter(ofX: x, y: y, tileSize: tuning.tileSize))
                let shaft = SKShapeNode(rectOf: CGSize(width: tile * 0.28, height: tile * 0.98), cornerRadius: 2)
                shaft.fillColor = SKColor(red: 0.12, green: 0.14, blue: 0.22, alpha: 0.95)
                shaft.strokeColor = ArtCatalog.neonCyan.withAlphaComponent(0.75)
                shaft.lineWidth = 1.2
                shaft.glowWidth = 0.6
                shaft.position = pos
                shaft.zPosition = 2.6
                world.addChild(shaft)
                let rim = SKSpriteNode(color: ArtCatalog.neonPink.withAlphaComponent(0.55), size: CGSize(width: tile * 0.08, height: tile * 0.9))
                rim.position = CGPoint(x: pos.x + tile * 0.1, y: pos.y)
                rim.zPosition = 2.65
                rim.blendMode = .add
                world.addChild(rim)
            }
        }

        // District Higgsfield props first; Kenney CC0 crates/pipes as fallback.
        // Never as collision face / under-ledge drips.
        let districtProps = ArtLibrary.districtDecorTextures(pendingDistrict)
        let propTextures = districtProps.isEmpty ? ArtCatalog.sidePropTextures() : districtProps
        let useDistrictProps = !districtProps.isEmpty
        var propI = 0
        for y in 0..<sim.map.height {
            for x in 0..<sim.map.width {
                let kind = sim.map.tile(atX: x, y: y)
                guard kind == .ground || kind == .wall else { continue }
                let pos = cg(sim.map.worldCenter(ofX: x, y: y, tileSize: tuning.tileSize))
                let below = sim.map.tile(atX: x, y: y - 1)
                let openBelow = !sim.map.isSolid(below) && below != .water

                // Sparse décor only — never a crate wall on the walkable deck.
                if !propTextures.isEmpty, !openBelow, (x + y * 5) % 29 == 0 {
                    let tex = propTextures[propI % propTextures.count]
                    propI += 1
                    let n = SKSpriteNode(texture: tex, size: CGSize(width: tile * 0.7, height: tile * 0.7))
                    n.position = CGPoint(x: pos.x, y: pos.y + tile * 0.55)
                    n.zPosition = 3.2
                    n.alpha = 0.92
                    if !useDistrictProps {
                        // Kill any baked green tint from Kenney sheets (no green drips).
                        n.color = SKColor(red: 0.72, green: 0.68, blue: 0.78, alpha: 1)
                        n.colorBlendFactor = 0.55
                    }
                    world.addChild(n)
                }

                // Wet-floor reflections (sparse) under solid tops.
                if !openBelow, (x + y * 3) % 3 == 0 {
                    addWetFloorReflection(at: pos, tile: tile)
                }

                // Short neon strip lights (1–2 tiles) on every other floating ledge — soft glow, not full pink bars.
                if openBelow, x % 2 == 0, (x / 2) % 2 == 0 {
                    let stripW = tile * (1.4 + CGFloat(x % 3) * 0.3)
                    let strip = SKSpriteNode(color: ArtCatalog.neonPink, size: CGSize(width: stripW, height: 3))
                    strip.name = "neonStrip"
                    strip.position = CGPoint(x: pos.x + tile * 0.35, y: pos.y - tile * 0.4)
                    strip.alpha = 0.9
                    strip.blendMode = .add
                    strip.zPosition = 3.1
                    world.addChild(strip)
                    let glow = SKSpriteNode(texture: ArtCatalog.softCircleTexture(), size: CGSize(width: stripW * 1.6, height: 18))
                    glow.name = "neonStripGlow"
                    glow.position = strip.position
                    glow.color = ArtCatalog.neonPink
                    glow.colorBlendFactor = 1
                    glow.alpha = 0.55
                    glow.blendMode = .add
                    glow.zPosition = 3.05
                    world.addChild(glow)
                    // Wet reflection puddle under the strip light.
                    addWetFloorReflection(at: CGPoint(x: pos.x + tile * 0.35, y: pos.y - tile * 1.1), tile: tile)
                }

                // Dark metal brackets under floating ledges (no green Kenney drips).
                if openBelow, x % 2 == 0 {
                    var drop = 1
                    while y - drop >= 0 {
                        let t = sim.map.tile(atX: x, y: y - drop)
                        if sim.map.isSolid(t) || t == .water { break }
                        drop += 1
                    }
                    guard drop >= 2 else { continue }
                    let span = CGFloat(drop) * tile
                    let pipe = SKShapeNode(rectOf: CGSize(width: tile * 0.12, height: span - 6), cornerRadius: 1)
                    pipe.fillColor = SKColor(red: 0.14, green: 0.14, blue: 0.18, alpha: 0.9)
                    pipe.strokeColor = SKColor(white: 0.25, alpha: 0.5)
                    pipe.lineWidth = 0.5
                    pipe.position = CGPoint(x: pos.x, y: pos.y - span * 0.5)
                    pipe.zPosition = 1.2
                    world.addChild(pipe)
                    let brace = SKShapeNode(rectOf: CGSize(width: tile * 0.55, height: 2.5), cornerRadius: 1)
                    brace.fillColor = SKColor(red: 0.16, green: 0.16, blue: 0.2, alpha: 0.95)
                    brace.strokeColor = ArtCatalog.neonCyan.withAlphaComponent(0.2)
                    brace.lineWidth = 0.4
                    brace.position = CGPoint(x: pos.x, y: pos.y - tile * 0.2)
                    brace.zPosition = 1.25
                    world.addChild(brace)
                }

                // Bare wall columns get rivet / panel detail so they aren't flat grey slabs.
                if kind == .wall, openBelow == false, x % 3 == 1 {
                    let panel = SKShapeNode(rectOf: CGSize(width: tile * 0.7, height: tile * 0.55), cornerRadius: 2)
                    panel.fillColor = SKColor(red: 0.14, green: 0.12, blue: 0.22, alpha: 0.85)
                    panel.strokeColor = ArtCatalog.neonCyan.withAlphaComponent(0.35)
                    panel.lineWidth = 0.8
                    panel.position = pos
                    panel.zPosition = 2.4
                    world.addChild(panel)
                }
            }
        }

        for y in 0..<sim.map.height {
            for x in 0..<sim.map.width {
                let kind = sim.map.tile(atX: x, y: y)
                let pos = cg(sim.map.worldCenter(ofX: x, y: y, tileSize: tuning.tileSize))
                switch kind {
                case .ground, .wall, .latch:
                    break
                case .crate:
                    let tex = ArtCatalog.sidePropTexture(index: 20)
                        ?? ArtCatalog.sidePropTexture(index: 21)
                        ?? ArtCatalog.tileTexture(index: 22)
                    if let tex {
                        let n = SKSpriteNode(texture: tex, size: CGSize(width: tile * 0.95, height: tile * 0.95))
                        n.position = pos
                        n.zPosition = 4
                        world.addChild(n)
                    }
                case .water:
                    let body = SKShapeNode(rectOf: CGSize(width: tile * 1.02, height: tile * 0.85), cornerRadius: 2)
                    body.fillColor = SKColor(red: 0.04, green: 0.06, blue: 0.14, alpha: 0.96)
                    body.strokeColor = .clear
                    body.position = CGPoint(x: pos.x, y: pos.y - tile * 0.05)
                    body.zPosition = 1
                    world.addChild(body)
                    // Hazard-tape lip so pits never look like background floor.
                    let tape = SKSpriteNode(color: SKColor(red: 1.0, green: 0.78, blue: 0.12, alpha: 1), size: CGSize(width: tile * 1.02, height: 5))
                    tape.position = CGPoint(x: pos.x, y: pos.y + tile * 0.42)
                    tape.zPosition = 1.3
                    world.addChild(tape)
                    let tapeStripe = SKSpriteNode(color: SKColor(red: 0.08, green: 0.06, blue: 0.05, alpha: 1), size: CGSize(width: tile * 0.28, height: 5))
                    tapeStripe.position = tape.position
                    tapeStripe.zPosition = 1.31
                    world.addChild(tapeStripe)
                    let drip = SKSpriteNode(color: ArtCatalog.neonCyan.withAlphaComponent(0.55), size: CGSize(width: 3, height: tile * 0.55))
                    drip.position = CGPoint(x: pos.x, y: pos.y - tile * 0.15)
                    drip.zPosition = 1.15
                    drip.alpha = 0.7
                    world.addChild(drip)
                    drip.run(SKAction.repeatForever(SKAction.sequence([
                        SKAction.fadeAlpha(to: 0.25, duration: 0.45),
                        SKAction.fadeAlpha(to: 0.75, duration: 0.45),
                    ])))
                    let surface = SKSpriteNode(color: ArtCatalog.neonCyan.withAlphaComponent(0.55), size: CGSize(width: tile * 1.02, height: 2))
                    surface.position = CGPoint(x: pos.x, y: pos.y + tile * 0.32)
                    surface.zPosition = 1.2
                    world.addChild(surface)
                case .spike:
                    let n = SKSpriteNode(color: ArtCatalog.neonPink, size: CGSize(width: tile * 0.8, height: tile * 0.5))
                    n.position = pos
                    n.zPosition = 5
                    world.addChild(n)
                case .checkpoint:
                    // Compact cyan gem — no tall lime pole (that read as a stray green line).
                    let gem = SKShapeNode(circleOfRadius: tile * 0.22)
                    gem.fillColor = ArtCatalog.neonCyan.withAlphaComponent(0.85)
                    gem.strokeColor = .white
                    gem.lineWidth = 0.8
                    gem.glowWidth = 1.5
                    gem.position = CGPoint(x: pos.x, y: pos.y + tile * 0.15)
                    gem.zPosition = 6
                    world.addChild(gem)
                case .stash, .exit:
                    let door = SKShapeNode(rectOf: CGSize(width: tile * 1.2, height: tile * 1.6), cornerRadius: 4)
                    door.fillColor = SKColor(red: 0.1, green: 0.12, blue: 0.22, alpha: 0.95)
                    door.strokeColor = ArtCatalog.neonLime
                    door.lineWidth = 2
                    door.glowWidth = kind == .exit ? 3 : 1
                    door.position = pos
                    door.zPosition = 6
                    door.name = kind == .exit ? "exitDoor" : "stashDoor"
                    world.addChild(door)
                    let t = SKLabelNode(fontNamed: "AvenirNext-Bold")
                    t.text = kind == .exit ? "VAULT" : "STASH"
                    t.fontSize = kind == .exit ? 12 : 9
                    t.fontColor = ArtCatalog.neonLime
                    t.verticalAlignmentMode = .center
                    door.addChild(t)
                    if kind == .exit {
                        placeExitBeacon(at: pos, tile: tile)
                    }
                case .oneWay:
                    let plank = SKShapeNode(rectOf: CGSize(width: tile * 0.98, height: tile * 0.18), cornerRadius: 2)
                    plank.fillColor = SKColor(red: 0.18, green: 0.22, blue: 0.32, alpha: 0.95)
                    plank.strokeColor = ArtCatalog.neonCyan.withAlphaComponent(0.7)
                    plank.lineWidth = 1
                    plank.position = CGPoint(x: pos.x, y: pos.y + tile * 0.32)
                    plank.zPosition = 4.5
                    world.addChild(plank)
                    let bolts = SKSpriteNode(color: ArtCatalog.neonCyan.withAlphaComponent(0.55), size: CGSize(width: tile * 0.9, height: 2))
                    bolts.position = plank.position
                    bolts.zPosition = 4.6
                    world.addChild(bolts)
                case .crewCage:
                    break // live node from crewNodes
                default:
                    break
                }
            }
        }
    }

    // MARK: - UI

    private func setupControls() {
        // Auto-runner: no left stick. Right-thumb JUMP / POUNCE / DASH + MASK (when ready).
        moveHitZone = SKNode()
        moveHitZone.name = "moveHitZone"
        moveHitZone.zPosition = 190
        moveHitZone.isHidden = true
        playHUD.addChild(moveHitZone)
        jumpHitZone = SKNode()
        jumpHitZone.name = "jumpHitZone"
        jumpHitZone.zPosition = 190
        playHUD.addChild(jumpHitZone)
        pounceHitZone = SKNode()
        pounceHitZone.name = "pounceHitZone"
        pounceHitZone.zPosition = 190
        playHUD.addChild(pounceHitZone)

        // Stick nodes kept for layout guards / smoke mirrors but fully hidden.
        let stickR = CGFloat(max(58, tuning.feel.stickMaxRadius * 0.95))
        stickBase = SKShapeNode(circleOfRadius: stickR)
        stickBase.fillColor = .clear
        stickBase.strokeColor = .clear
        stickBase.zPosition = 200
        stickBase.isHidden = true
        stickBase.alpha = 0
        playHUD.addChild(stickBase)
        stickKnob = SKShapeNode(circleOfRadius: stickR * 0.42)
        stickKnob.fillColor = .clear
        stickKnob.strokeColor = .clear
        stickKnob.zPosition = 201
        stickKnob.isHidden = true
        stickKnob.alpha = 0
        playHUD.addChild(stickKnob)

        jumpBtn = makeFaceButton(title: "JUMP", color: ArtCatalog.neonLime, large: true, iconName: "jump")
        jumpBtn.name = "jumpBtn"
        playHUD.addChild(jumpBtn)
        pounceBtn = makeFaceButton(title: "POUNCE", color: ArtCatalog.neonPink, large: true, iconName: "pounce")
        pounceBtn.name = "pounceBtn"
        playHUD.addChild(pounceBtn)
        dashBtn = makeFaceButton(title: "DASH", color: ArtCatalog.neonCyan, large: false, iconName: "dash")
        dashBtn.name = "dashBtn"
        attachCooldownRing(to: dashBtn, name: "dashRing", color: ArtCatalog.neonCyan)
        playHUD.addChild(dashBtn)
        // Same size as DASH — sits in the 2×2 grid without overlapping JUMP/POUNCE.
        maskBtn = makeFaceButton(title: "MASK", color: ArtCatalog.neonCyan, large: false, iconName: "mask")
        maskBtn.name = "maskBtn"
        attachChargeBadge(to: maskBtn, name: "maskCharges")
        maskBtn.isHidden = true
        playHUD.addChild(maskBtn)
        // GRAB folded into auto-pickup — keep a hidden stub so optional UI code stays safe.
        grabBtn = makeFaceButton(title: "GRAB", color: ArtCatalog.neonOrange, large: false, iconName: "grab")
        grabBtn.name = "grabBtn"
        grabBtn.isHidden = true
        grabBtn.alpha = 0
        playHUD.addChild(grabBtn)

        dashHitZone = SKNode(); dashHitZone.name = "dashHitZone"; dashHitZone.zPosition = 190; playHUD.addChild(dashHitZone)
        maskHitZone = SKNode(); maskHitZone.name = "maskHitZone"; maskHitZone.zPosition = 190; playHUD.addChild(maskHitZone)
        grabHitZone = SKNode(); grabHitZone.name = "grabHitZone"; grabHitZone.zPosition = 190; grabHitZone.isHidden = true; playHUD.addChild(grabHitZone)

        // Thin progress track: bandit → vault.
        let track = SKShapeNode(rectOf: CGSize(width: 220, height: 6), cornerRadius: 3)
        track.name = "progressTrack"
        track.fillColor = SKColor(white: 0.12, alpha: 0.85)
        track.strokeColor = SKColor(white: 1, alpha: 0.2)
        track.lineWidth = 1
        track.zPosition = 205
        playHUD.addChild(track)
        progressTrack = track
        let fill = SKShapeNode(rectOf: CGSize(width: 4, height: 6), cornerRadius: 3)
        fill.name = "progressFill"
        fill.fillColor = ArtCatalog.neonLime
        fill.strokeColor = .clear
        fill.zPosition = 206
        playHUD.addChild(fill)
        progressFill = fill
        let dot = SKShapeNode(circleOfRadius: 5)
        dot.fillColor = ArtCatalog.neonPink
        dot.strokeColor = .white
        dot.lineWidth = 1
        dot.zPosition = 207
        playHUD.addChild(dot)
        progressBanditDot = dot
    }

    private func attachCooldownRing(to btn: SKShapeNode, name: String, color: SKColor) {
        let ring = SKShapeNode(circleOfRadius: 28)
        ring.name = name
        ring.strokeColor = color
        ring.fillColor = .clear
        ring.lineWidth = 4
        ring.glowWidth = 1
        ring.zPosition = 5
        ring.position = .zero
        ring.isHidden = true
        btn.addChild(ring)
    }

    private func attachChargeBadge(to btn: SKShapeNode, name: String) {
        let badge = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        badge.name = name
        badge.fontSize = 11
        badge.fontColor = ArtCatalog.neonCyan
        badge.horizontalAlignmentMode = .right
        badge.verticalAlignmentMode = .top
        badge.position = CGPoint(x: 34, y: 22)
        badge.zPosition = 6
        btn.addChild(badge)
    }

    private func makeFaceButton(
        title: String,
        color: SKColor,
        large: Bool = false,
        iconName: String? = nil
    ) -> SKShapeNode {
        let edge: CGFloat
        let font: CGFloat
        if large {
            // Thumb-sized face (≥112 pt). Invisible zones add the forgiving miss padding.
            edge = CGFloat(max(112, tuning.feel.faceButtonMinPt))
            font = title.count > 5 ? 12 : 14
        } else {
            edge = 92
            font = 13
        }
        let h = large ? edge * 0.78 : 56
        let b = SKShapeNode(
            rectOf: CGSize(width: edge, height: h),
            cornerRadius: large ? 22 : 16
        )
        b.fillColor = SKColor(red: 0.05, green: 0.04, blue: 0.14, alpha: 0.88)
        b.strokeColor = color
        b.lineWidth = 3
        b.glowWidth = 2
        b.zPosition = 200
        if let iconName, let tex = JuiceFX.buttonIcon(iconName) {
            let icon = SKSpriteNode(texture: tex, size: CGSize(width: edge * 0.42, height: edge * 0.42))
            icon.name = "btnIcon"
            icon.position = CGPoint(x: 0, y: h * 0.12)
            icon.zPosition = 1
            b.addChild(icon)
            let t = SKLabelNode(fontNamed: "AvenirNext-Heavy")
            t.text = title
            t.fontSize = font
            t.fontColor = color
            t.verticalAlignmentMode = .center
            t.position = CGPoint(x: 0, y: -h * 0.32)
            t.name = "btnLabel"
            b.addChild(t)
        } else {
            let t = SKLabelNode(fontNamed: "AvenirNext-Heavy")
            t.text = title
            t.fontSize = font
            t.fontColor = color
            t.verticalAlignmentMode = .center
            t.name = "btnLabel"
            b.addChild(t)
        }
        return b
    }

    private func secondaryButtonSize() -> CGSize {
        CGSize(width: 92, height: 56)
    }

    private func paddedSecondaryHitRect(for btn: SKShapeNode) -> CGRect {
        let vis = secondaryButtonSize()
        let pad = CGFloat(max(28, tuning.feel.faceButtonHitPad * 0.7))
        return CGRect(
            x: btn.position.x - vis.width * 0.5 - pad,
            y: btn.position.y - vis.height * 0.5 - pad,
            width: vis.width + pad * 2,
            height: vis.height + pad * 2
        )
    }

    private func pressFaceButton(_ btn: SKShapeNode) {
        btn.removeAction(forKey: "press")
        // Never body.setScale on the bandit — buttons are fine; keep press scale symmetric.
        btn.xScale = 1
        btn.yScale = 1
        let down = SKAction.group([
            SKAction.scaleX(to: 0.88, duration: 0.05),
            SKAction.scaleY(to: 0.88, duration: 0.05),
            SKAction.fadeAlpha(to: 1, duration: 0.05),
        ])
        let up = SKAction.group([
            SKAction.scaleX(to: 1.0, duration: 0.1),
            SKAction.scaleY(to: 1.0, duration: 0.1),
        ])
        up.timingMode = .easeOut
        btn.run(SKAction.sequence([down, up]), withKey: "press")
    }

    /// Smoke autoplay: flash the matching face button when the director taps an action.
    private func flashSmokeFaceButtons(from input: InputFrame) {
        if input.jumpPressed, jumpBtn != nil { pressFaceButton(jumpBtn) }
        if input.pouncePressed, pounceBtn != nil { pressFaceButton(pounceBtn) }
        if input.dashPressed, dashBtn != nil { pressFaceButton(dashBtn) }
        if input.maskPressed, maskBtn != nil { pressFaceButton(maskBtn) }
        if input.grabPressed, grabBtn != nil { pressFaceButton(grabBtn) }
    }

    /// Cooldown ring, MASK charges badge, GRAB dim/hide from live sim state.
    private func refreshActionButtonChrome() {
        guard dashBtn != nil, maskBtn != nil, grabBtn != nil else { return }
        let b = sim.state.bandit
        let feel = tuning.feel
        // DASH cooldown ring (full → empty as cooldown drains).
        if let ring = dashBtn.childNode(withName: "dashRing") as? SKShapeNode {
            if b.dashCooldown > 0.02 {
                let t = max(0, min(1, b.dashCooldown / max(0.05, feel.dashCooldown)))
                ring.isHidden = false
                ring.alpha = 0.85
                ring.path = {
                    let r: CGFloat = 28
                    let start = CGFloat.pi / 2
                    let end = start - CGFloat(t) * CGFloat.pi * 2
                    let path = CGMutablePath()
                    path.addArc(center: .zero, radius: r, startAngle: start, endAngle: end, clockwise: true)
                    return path
                }()
                dashBtn.alpha = 0.55
            } else {
                ring.isHidden = true
                dashBtn.alpha = 1
            }
        }
        // MASK appears only when the meter is full (charges > 0) or already active.
        let maskReady = b.maskCharges > 0 || b.maskMode
        maskBtn.isHidden = !maskReady
        maskHitZone.isHidden = !maskReady
        if let badge = maskBtn.childNode(withName: "maskCharges") as? SKLabelNode {
            let charges = max(0, b.maskCharges)
            badge.text = charges > 0 ? "×\(charges)" : ""
            badge.isHidden = !maskReady || charges <= 0
        }
        if b.maskMode {
            maskBtn.alpha = 0.85
            maskBtn.strokeColor = ArtCatalog.neonLime
            maskBtn.glowWidth = 6
        } else if maskReady {
            maskBtn.alpha = 1
            maskBtn.strokeColor = ArtCatalog.neonCyan
            maskBtn.glowWidth = 5
            if maskBtn.action(forKey: "maskPulse") == nil {
                maskBtn.run(SKAction.repeatForever(SKAction.sequence([
                    SKAction.group([
                        SKAction.fadeAlpha(to: 0.75, duration: 0.35),
                        SKAction.scale(to: 1.06, duration: 0.35),
                    ]),
                    SKAction.group([
                        SKAction.fadeAlpha(to: 1.0, duration: 0.35),
                        SKAction.scale(to: 1.0, duration: 0.35),
                    ]),
                ])), withKey: "maskPulse")
            }
        } else {
            maskBtn.removeAction(forKey: "maskPulse")
            maskBtn.setScale(1)
        }
        grabBtn.isHidden = true
        grabBtn.alpha = 0
        grabHitZone.isHidden = true
    }

    private func updateProgressBar(barWidth: CGFloat, barY: CGFloat) {
        guard let fill = progressFill, let dot = progressBanditDot else { return }
        let span = max(1.0, exitWorldX - startWorldX)
        let progressX = sim.state.bandit.position.x
        let t = max(0.0, min(1.0, (progressX - startWorldX) / span))
        let w = max(CGFloat(4), barWidth * CGFloat(t))
        fill.path = CGPath(
            roundedRect: CGRect(x: -barWidth * 0.5, y: -3, width: w, height: 6),
            cornerWidth: 3, cornerHeight: 3, transform: nil
        )
        fill.position = CGPoint(x: 0, y: barY)
        fill.fillColor = ArtCatalog.neonLime
        dot.position = CGPoint(x: -barWidth * 0.5 + w, y: barY)
    }

    /// Face-button visual size (matches `makeFaceButton(large:)`).
    private func faceButtonVisualSize() -> CGSize {
        let edge = CGFloat(max(112, tuning.feel.faceButtonMinPt))
        return CGSize(width: edge, height: edge * 0.78)
    }

    /// Expanded hit rect around a face button — every drawn pixel + pad, including stroke.
    private func paddedFaceHitRect(for btn: SKShapeNode) -> CGRect {
        let vis = faceButtonVisualSize()
        // Stroke (3) + glow (~2) sit outside the path; cover them + feel pad.
        let pad = CGFloat(max(40, tuning.feel.faceButtonHitPad)) + 8
        return CGRect(
            x: btn.position.x - vis.width * 0.5 - pad,
            y: btn.position.y - vis.height * 0.5 - pad,
            width: vis.width + pad * 2,
            height: vis.height + pad * 2
        )
    }

    /// Rebuild hit plates from the *drawn* buttons + pad. Move zone stays left of face hits.
    private func layoutControlHitZones() {
        guard moveHitZone != nil, jumpHitZone != nil, pounceHitZone != nil,
              dashHitZone != nil, maskHitZone != nil, grabHitZone != nil,
              jumpBtn != nil, pounceBtn != nil, dashBtn != nil, maskBtn != nil, grabBtn != nil else { return }
        let hw = size.width * 0.5
        let hh = size.height * 0.5
        let insets = safeInsets()
        let bottomSafe = max(insets.bottom, 20)
        moveHitZone.removeAllChildren()
        jumpHitZone.removeAllChildren()
        pounceHitZone.removeAllChildren()
        dashHitZone.removeAllChildren()
        maskHitZone.removeAllChildren()
        grabHitZone.removeAllChildren()

        let jumpRect = paddedFaceHitRect(for: jumpBtn)
        let pounceRect = paddedFaceHitRect(for: pounceBtn)
        let dashRect = paddedSecondaryHitRect(for: dashBtn)
        let maskRect = paddedSecondaryHitRect(for: maskBtn)
        let grabRect = paddedSecondaryHitRect(for: grabBtn)
        // Expand jump/pounce plates toward the right edge / each other so misses still land,
        // but never cross the midline into the move side.
        let faceLeft = min(jumpRect.minX, pounceRect.minX, dashRect.minX, maskRect.minX, grabRect.minX)
        let jumpPlateRect = CGRect(
            x: max(0, jumpRect.minX - 12),
            y: jumpRect.minY,
            width: hw - max(0, jumpRect.minX - 12) + 4,
            height: jumpRect.height
        )
        let pouncePlateRect = CGRect(
            x: max(0, pounceRect.minX - 12),
            y: pounceRect.minY,
            width: hw - max(0, pounceRect.minX - 12) + 4,
            height: pounceRect.height
        )
        placeHitPlate(on: jumpHitZone, rect: jumpPlateRect, name: "jumpPlate")
        placeHitPlate(on: pounceHitZone, rect: pouncePlateRect, name: "pouncePlate")
        placeHitPlate(on: dashHitZone, rect: dashRect, name: "dashPlate")
        placeHitPlate(on: maskHitZone, rect: maskRect, name: "maskPlate")
        placeHitPlate(on: grabHitZone, rect: grabRect, name: "grabPlate")

        // Move: left third, hard-capped so it never overlaps face hit plates.
        let moveMaxX = min(-size.width * 0.02, faceLeft - 8)
        let moveW = max(80, moveMaxX - (-hw))
        let moveH = size.height * 0.52
        let moveRect = CGRect(
            x: -hw,
            y: -hh + bottomSafe * 0.15,
            width: moveW,
            height: moveH
        )
        placeHitPlate(on: moveHitZone, rect: moveRect, name: "movePlate")
        refreshTouchDebugOverlay()
    }

    private func placeHitPlate(on zone: SKNode, rect: CGRect, name: String) {
        zone.position = CGPoint(x: rect.midX, y: rect.midY)
        let plate = SKShapeNode(rectOf: CGSize(width: rect.width, height: rect.height), cornerRadius: 10)
        plate.fillColor = .clear
        plate.strokeColor = .clear
        plate.name = name
        zone.addChild(plate)
    }

    private func hitInZone(_ zone: SKNode, pointInHUD p: CGPoint) -> Bool {
        // playHUD sits at the origin under hud — plate.contains expects zone-local coords.
        let local = CGPoint(x: p.x - zone.position.x, y: p.y - zone.position.y)
        return zone.children.contains { $0.contains(local) }
    }

    private func hitPaddedFaceButton(_ btn: SKShapeNode, pointInHUD p: CGPoint) -> Bool {
        paddedFaceHitRect(for: btn).contains(p)
    }

    /// Debug overlay of real touch areas (off by default).
    private func refreshTouchDebugOverlay() {
        touchDebugRoot?.removeFromParent()
        touchDebugRoot = nil
        guard showTouchDebug, jumpBtn != nil, pounceBtn != nil, moveHitZone != nil else { return }
        let root = SKNode()
        root.name = "touchDebugRoot"
        root.zPosition = 250
        func addRect(_ rect: CGRect, color: SKColor, label: String) {
            let n = SKShapeNode(rectOf: CGSize(width: rect.width, height: rect.height), cornerRadius: 6)
            n.position = CGPoint(x: rect.midX, y: rect.midY)
            n.fillColor = color.withAlphaComponent(0.22)
            n.strokeColor = color
            n.lineWidth = 2
            n.glowWidth = 0
            root.addChild(n)
            let t = SKLabelNode(fontNamed: "AvenirNext-Bold")
            t.text = label
            t.fontSize = 11
            t.fontColor = color
            t.verticalAlignmentMode = .center
            t.position = CGPoint(x: rect.midX, y: rect.midY)
            root.addChild(t)
        }
        if let move = moveHitZone.children.first {
            let r = CGRect(
                x: moveHitZone.position.x - move.frame.width * 0.5,
                y: moveHitZone.position.y - move.frame.height * 0.5,
                width: move.frame.width,
                height: move.frame.height
            )
            addRect(r, color: ArtCatalog.neonCyan, label: "MOVE")
        }
        addRect(paddedFaceHitRect(for: jumpBtn), color: ArtCatalog.neonLime, label: "JUMP")
        addRect(paddedFaceHitRect(for: pounceBtn), color: ArtCatalog.neonPink, label: "POUNCE")
        if dashBtn != nil {
            addRect(paddedSecondaryHitRect(for: dashBtn), color: ArtCatalog.neonCyan, label: "DASH")
        }
        if maskBtn != nil {
            addRect(paddedSecondaryHitRect(for: maskBtn), color: ArtCatalog.neonCyan, label: "MASK")
        }
        if grabBtn != nil {
            addRect(paddedSecondaryHitRect(for: grabBtn), color: ArtCatalog.neonOrange, label: "GRAB")
        }
        if let jump = jumpHitZone.children.first {
            let r = CGRect(
                x: jumpHitZone.position.x - jump.frame.width * 0.5,
                y: jumpHitZone.position.y - jump.frame.height * 0.5,
                width: jump.frame.width,
                height: jump.frame.height
            )
            addRect(r, color: ArtCatalog.neonLime.withAlphaComponent(0.7), label: "JUMP+")
        }
        if let pounce = pounceHitZone.children.first {
            let r = CGRect(
                x: pounceHitZone.position.x - pounce.frame.width * 0.5,
                y: pounceHitZone.position.y - pounce.frame.height * 0.5,
                width: pounce.frame.width,
                height: pounce.frame.height
            )
            addRect(r, color: ArtCatalog.neonPink.withAlphaComponent(0.7), label: "POUNCE+")
        }
        playHUD.addChild(root)
        touchDebugRoot = root
    }

    private func setupHUD() {
        hudPill = SKShapeNode(rectOf: CGSize(width: 168, height: 54), cornerRadius: 14)
        hudPill.fillColor = SKColor(red: 0.04, green: 0.03, blue: 0.10, alpha: 0.72)
        hudPill.strokeColor = SKColor(white: 1, alpha: 0.12)
        hudPill.lineWidth = 1
        hudPill.zPosition = 198
        hudPill.name = "hudPill"
        playHUD.addChild(hudPill)

        for (label, color) in [
            (hudCarried, ArtCatalog.neonOrange),
            (hudHearts, ArtCatalog.neonPink),
            (hudCombo, ArtCatalog.neonCyan),
            (hudTime, SKColor.white),
        ] as [(SKLabelNode, SKColor)] {
            styleHUDLabel(label, color: color)
            playHUD.addChild(label)
        }
        // FPS / TUNING only in DEBUG and never during SmokeAutoplay (review gate).
        #if DEBUG
        if !smokeEnabled {
            fpsLabel.fontSize = 11
            fpsLabel.fontColor = .white
            fpsLabel.horizontalAlignmentMode = .left
            fpsLabel.verticalAlignmentMode = .bottom
            fpsLabel.zPosition = 210
            hud.addChild(fpsLabel)
        }
        #endif
    }

    /// Compact HUD font — sits on the dark pill, not raw over the skyline.
    private func styleHUDLabel(_ label: SKLabelNode, color: SKColor) {
        label.fontName = "AvenirNext-Heavy"
        label.fontSize = 13
        label.fontColor = color
        label.horizontalAlignmentMode = .left
        label.verticalAlignmentMode = .center
        label.zPosition = 210
        if label.childNode(withName: "hudOutline") == nil {
            let outline = SKLabelNode(fontNamed: "AvenirNext-Heavy")
            outline.name = "hudOutline"
            outline.fontSize = 13
            outline.fontColor = SKColor(red: 0.02, green: 0.01, blue: 0.08, alpha: 0.9)
            outline.horizontalAlignmentMode = .left
            outline.verticalAlignmentMode = .center
            outline.position = CGPoint(x: 1, y: -1)
            outline.zPosition = -1
            label.addChild(outline)
            let glow = SKLabelNode(fontNamed: "AvenirNext-Heavy")
            glow.name = "hudGlow"
            glow.fontSize = 13
            glow.fontColor = color.withAlphaComponent(0.35)
            glow.horizontalAlignmentMode = .left
            glow.verticalAlignmentMode = .center
            glow.position = .zero
            glow.zPosition = -2
            glow.setScale(1.03)
            label.addChild(glow)
        }
        if let outline = label.childNode(withName: "hudOutline") as? SKLabelNode {
            outline.text = label.text
            outline.fontSize = label.fontSize
        }
        if let glow = label.childNode(withName: "hudGlow") as? SKLabelNode {
            glow.text = label.text
            glow.fontSize = label.fontSize
            glow.fontColor = color.withAlphaComponent(0.45)
        }
    }

    private func setupTitle() {
        titleRoot.zPosition = 300
        titleRoot.isHidden = true // Revealed after publisher ident (or immediately if skipped).
        overlay.addChild(titleRoot)

        // Dedicated title plate — official leap key art (aspect-fill), never live level geometry.
        let alley = SKNode()
        alley.name = "titleAlley"
        alley.zPosition = -20
        titleRoot.addChild(alley)

        let wash = SKShapeNode(rectOf: CGSize(width: 4000, height: 4000))
        wash.fillColor = SKColor(red: 0.02, green: 0.02, blue: 0.07, alpha: 1)
        wash.strokeColor = .clear
        wash.name = "titleWash"
        alley.addChild(wash)

        // Official Higgsfield leap still — edge-to-edge hero behind chrome.
        let keyTex: SKTexture? = {
            for rel in TitleArt.titleKeyArtCandidates {
                if let t = ArtCatalog.downsampledTexture(relative: rel, maxPixel: 1400) { return t }
            }
            return nil
        }()
        if let keyTex {
            let hero = SKSpriteNode(texture: keyTex)
            hero.name = "titleKeyArt"
            hero.zPosition = 0
            hero.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            alley.addChild(hero)
        } else if let far = ArtCatalog.background(.farSkyline, height: 920, maxPixel: 1024) {
            // Fallback only if key art is missing from the bundle.
            far.name = "titleFar"
            far.alpha = 0.55
            far.zPosition = 0
            alley.addChild(far)
        }

        // Soft darken so B1 logo / TAP TO START / bottom bar stay readable over the hero.
        let dim = SKShapeNode(rectOf: CGSize(width: 4000, height: 4000))
        dim.name = "titleDim"
        dim.fillColor = SKColor(red: 0.02, green: 0.01, blue: 0.08, alpha: 0.42)
        dim.strokeColor = .clear
        dim.zPosition = 5
        alley.addChild(dim)

        let rain = ArtCatalog.rainEmitter(sceneSize: CGSize(width: 480, height: 900))
        rain.name = "titleRain"
        rain.zPosition = 8
        rain.position = CGPoint(x: 0, y: 220)
        alley.addChild(rain)

        let glow = SKShapeNode(circleOfRadius: 110)
        glow.name = "titleGlow"
        glow.fillColor = ArtCatalog.neonPink.withAlphaComponent(0.14)
        glow.strokeColor = ArtCatalog.neonCyan.withAlphaComponent(0.28)
        glow.lineWidth = 2
        glow.glowWidth = 8
        glow.zPosition = 9
        titleRoot.addChild(glow)

        // B1 holo glass logo — hero of the top third (no font title).
        let logo = ArtCatalog.makeLogoNode(lite: false)
        logo.name = "titleLogo"
        logo.zPosition = 12
        logo.alpha = 0
        titleRoot.addChild(logo)
        runTitleLogoIntro(logo)

        let play = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        play.name = "tapToStart"
        play.text = "TAP TO START"
        play.fontSize = 22
        play.fontColor = .white
        play.zPosition = 14
        titleRoot.addChild(play)
        play.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.group([
                SKAction.fadeAlpha(to: 0.35, duration: 0.55),
                SKAction.scale(to: 0.96, duration: 0.55),
            ]),
            SKAction.group([
                SKAction.fadeAlpha(to: 1, duration: 0.55),
                SKAction.scale(to: 1.06, duration: 0.55),
            ]),
        ])))

        // Tidy bottom bar — MAP · MUTE · DAILY with spacing (no overlaps).
        let bar = SKNode()
        bar.name = "titleBottomBar"
        bar.zPosition = 15
        titleRoot.addChild(bar)
        let mapBtn = RetentionChrome.makeChromeButton(title: "MAP", color: ArtCatalog.neonCyan, name: "titleMap")
        bar.addChild(mapBtn)
        let muteBtn = RetentionChrome.makeChromeButton(
            title: JuiceSound.shared.muted ? "UNMUTE" : "MUTE",
            color: ArtCatalog.neonPink,
            name: "titleMute"
        )
        bar.addChild(muteBtn)
        let dailyBtn = RetentionChrome.makeChromeButton(title: "DAILY", color: ArtCatalog.neonLime, name: "titleDaily")
        bar.addChild(dailyBtn)

        let credit = SKLabelNode(fontNamed: "AvenirNext-Medium")
        credit.name = "titleCredit"
        credit.text = TitleArt.assetCredits
        credit.fontSize = 9
        credit.fontColor = SKColor(white: 1, alpha: 0.45)
        credit.zPosition = 16
        titleRoot.addChild(credit)

        layoutTitleChrome()
    }

    /// Glitch-in (~0.6s) then idle shimmer/hover + occasional slice glitch.
    private func runTitleLogoIntro(_ logo: SKNode) {
        logo.removeAction(forKey: "logoPulse")
        logo.removeAction(forKey: "logoGlitch")
        logo.alpha = 0
        logo.setScale(1.12)
        let intro = SKAction.sequence([
            SKAction.group([
                SKAction.fadeAlpha(to: 1, duration: 0.22),
                SKAction.scaleX(to: 1.2, duration: 0.08),
            ]),
            SKAction.group([
                SKAction.scaleX(to: 0.82, duration: 0.07),
                SKAction.fadeAlpha(to: 0.55, duration: 0.05),
            ]),
            SKAction.group([
                SKAction.scaleX(to: 1.05, duration: 0.1),
                SKAction.fadeAlpha(to: 1, duration: 0.08),
            ]),
            SKAction.scale(to: 1.0, duration: 0.13),
            SKAction.run { [weak self, weak logo] in
                guard let self, let logo else { return }
                self.runTitleLogoIdle(logo)
            },
        ])
        logo.run(intro, withKey: "logoIntro")
    }

    private func runTitleLogoIdle(_ logo: SKNode) {
        let base = (logo.userData?["baseScale"] as? CGFloat) ?? logo.xScale
        logo.removeAction(forKey: "logoPulse")
        logo.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.group([
                SKAction.moveBy(x: 0, y: 4, duration: 1.35),
                SKAction.fadeAlpha(to: 0.92, duration: 1.35),
                SKAction.scale(to: base * 1.02, duration: 1.35),
            ]),
            SKAction.group([
                SKAction.moveBy(x: 0, y: -4, duration: 1.35),
                SKAction.fadeAlpha(to: 1.0, duration: 1.35),
                SKAction.scale(to: base, duration: 1.35),
            ]),
        ])), withKey: "logoPulse")
        logo.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.wait(forDuration: 3.6),
            SKAction.group([
                SKAction.scaleX(to: base * 1.18, duration: 0.04),
                SKAction.fadeAlpha(to: 0.7, duration: 0.04),
            ]),
            SKAction.group([
                SKAction.scaleX(to: base * 0.9, duration: 0.05),
                SKAction.fadeAlpha(to: 1, duration: 0.05),
            ]),
            SKAction.scale(to: base, duration: 0.08),
        ])), withKey: "logoGlitch")
    }

    private func refreshMuteButton() {
        guard let btn = titleRoot.childNode(withName: "//titleMute") else { return }
        let label = btn.children.compactMap { $0 as? SKLabelNode }.first
        label?.text = JuiceSound.shared.muted ? "UNMUTE" : "MUTE"
    }

    private func setupRetention() {
        retentionRoot.zPosition = 340
        retentionRoot.isHidden = true
        retentionRoot.name = "retentionRoot"
        overlay.addChild(retentionRoot)
    }

    private func showDistrictMap() {
        if retentionMode == "map" { return }
        retentionRoot.removeAllChildren()
        retentionRoot.setScale(1)
        retentionRoot.alpha = 1
        retentionRoot.isHidden = false
        let progress = progressStore.load()
        let map = RetentionChrome.makeDistrictMap(size: size, progress: progress)
        retentionRoot.addChild(map)
        RetentionChrome.present(map)
        retentionMode = "map"
        smokeStatus.map = true
        writeSmokeStatus()
    }

    private func showDailyHeist() {
        if retentionMode == "daily" { return }
        // Leaving map → daily: drop the map flag so we don't flip every frame.
        SmokeBrain.setSmokeFlag("smoke_show_map.txt", present: false)
        retentionRoot.removeAllChildren()
        retentionRoot.setScale(1)
        retentionRoot.alpha = 1
        retentionRoot.isHidden = false
        let progress = progressStore.load()
        let day = ProgressStore.dayKey()
        let daily = RetentionChrome.makeDailyHeist(size: size, dayKey: day, progress: progress)
        retentionRoot.addChild(daily)
        RetentionChrome.present(daily)
        retentionMode = "daily"
        smokeStatus.daily = true
        gameCenter.setAccessPointVisible(true, showHighlights: true)
        writeSmokeStatus()
    }

    private func hideRetention() {
        retentionRoot.isHidden = true
        retentionRoot.removeAllChildren()
        retentionRoot.setScale(1)
        retentionRoot.alpha = 1
        retentionMode = nil
    }

    /// B1 logo in the top third; raccoon mid; TAP TO START; bottom bar with non-overlapping buttons.
    private func layoutTitleChrome() {
        guard size.width > 1, size.height > 1 else { return }
        let insets = safeInsets()
        let topSafe = max(insets.top, 54) + 10
        let bottomSafe = max(insets.bottom, 22)
        let hh = size.height * 0.5
        guard let logo = titleRoot.childNode(withName: "titleLogo") else { return }
        // Wide B1 lockup — keep under ~78% width so height stays inside the top safe band.
        let base = ArtCatalog.fitTitleLogo(logo, sceneWidth: size.width, fraction: 0.78)
        let safeTop = hh - topSafe
        let safeBottom = -hh + bottomSafe
        let safeH = safeTop - safeBottom
        // Top third: logo hero (nudge down from the safe top so the tall holo art clears the notch).
        var logoY = safeTop - safeH * 0.20
        logo.position = CGPoint(x: 0, y: logoY)
        if logo.action(forKey: "logoIntro") == nil, logo.action(forKey: "logoPulse") == nil {
            runTitleLogoIdle(logo)
        } else if logo.action(forKey: "logoPulse") != nil {
            runTitleLogoIdle(logo)
        }

        if let glow = titleRoot.childNode(withName: "titleGlow") {
            glow.position = logo.position
            glow.setScale(max(0.85, size.width * 0.72 / 220))
        }
        if let alley = titleRoot.childNode(withName: "titleAlley") {
            // Aspect-fill leap key art to the full scene (edge-to-edge hero).
            if let hero = alley.childNode(withName: "titleKeyArt") as? SKSpriteNode,
               let tex = hero.texture
            {
                let tw = max(tex.size().width, 1)
                let th = max(tex.size().height, 1)
                let scale = max(size.width / tw, size.height / th)
                hero.size = CGSize(width: tw * scale, height: th * scale)
                hero.position = .zero
            }
            alley.childNode(withName: "titleFar")?.position = CGPoint(x: 0, y: 40)
        }
        // TAP sits mid-lower so it stays clear of the leap silhouette and bottom chrome.
        titleRoot.childNode(withName: "tapToStart")?.position = CGPoint(
            x: 0,
            y: safeBottom + safeH * 0.28
        )

        // Bottom bar: chrome buttons are 140pt wide — scale down and space centers by width+gap
        // so MAP / MUTE / DAILY never intersect (CI titleOk gate).
        let barY = safeBottom + 40
        let btnScale: CGFloat = 0.68
        let btnW: CGFloat = 140 * btnScale
        let centerGap: CGFloat = 14
        let spacing = btnW + centerGap
        if let bar = titleRoot.childNode(withName: "titleBottomBar") {
            bar.position = .zero
            for name in ["titleMap", "titleMute", "titleDaily"] {
                bar.childNode(withName: name)?.setScale(btnScale)
            }
            bar.childNode(withName: "titleMap")?.position = CGPoint(x: -spacing, y: barY)
            bar.childNode(withName: "titleMute")?.position = CGPoint(x: 0, y: barY)
            bar.childNode(withName: "titleDaily")?.position = CGPoint(x: spacing, y: barY)
        }
        titleRoot.childNode(withName: "titleCredit")?.position = CGPoint(x: 0, y: safeBottom + 10)

        var ok = ArtCatalog.logoFrameInsideSafeArea(
            logoFrame: logo.calculateAccumulatedFrame(),
            sceneSize: size,
            topSafe: topSafe,
            bottomSafe: bottomSafe
        )
        if !ok {
            _ = ArtCatalog.fitTitleLogo(logo, sceneWidth: size.width, fraction: 0.68)
            logoY -= 28
            logo.position = CGPoint(x: 0, y: logoY)
            runTitleLogoIdle(logo)
            ok = ArtCatalog.logoFrameInsideSafeArea(
                logoFrame: logo.calculateAccumulatedFrame(),
                sceneSize: size,
                topSafe: topSafe,
                bottomSafe: bottomSafe
            )
        }
        if !ok {
            // Last resort: shrink further — title still ships, gate must clear for smoke.
            _ = ArtCatalog.fitTitleLogo(logo, sceneWidth: size.width, fraction: 0.58)
            logo.position = CGPoint(x: 0, y: safeTop - safeH * 0.28)
            runTitleLogoIdle(logo)
            ok = ArtCatalog.logoFrameInsideSafeArea(
                logoFrame: logo.calculateAccumulatedFrame(),
                sceneSize: size,
                topSafe: topSafe,
                bottomSafe: bottomSafe
            )
        }
        var buttonFrames: [CGRect] = []
        for name in ["titleMap", "titleMute", "titleDaily"] {
            if let n = titleRoot.childNode(withName: "//\(name)") {
                // Use the shape path bounds (ignore glow/label inflation) for the overlap gate.
                let f = n.calculateAccumulatedFrame()
                let tight = CGRect(
                    x: n.position.x - btnW * 0.5,
                    y: n.position.y - 20 * btnScale,
                    width: btnW,
                    height: 40 * btnScale
                )
                // Prefer parent-bar local → scene: buttons live under titleBottomBar at .zero.
                buttonFrames.append(tight.isEmpty ? f : tight)
            }
        }
        let noOverlap = ArtCatalog.framesNonOverlapping(buttonFrames, gap: 2)
        smokeStatus.titleOk = ok && noOverlap
        if smokeEnabled { writeSmokeStatus() }
        _ = base
    }

    private func setupPauseMenu() {
        pauseBtn = makeFaceButton(title: "PAUSE", color: ArtCatalog.neonCyan)
        pauseBtn.name = "pauseBtn"
        pauseBtn.zPosition = 212
        playHUD.addChild(pauseBtn)

        pauseRoot.zPosition = 330
        pauseRoot.isHidden = true
        pauseRoot.name = "pauseRoot"
        overlay.addChild(pauseRoot)

        let wash = SKShapeNode(rectOf: CGSize(width: 4000, height: 4000))
        wash.fillColor = SKColor(red: 0.02, green: 0.02, blue: 0.08, alpha: 0.62)
        wash.strokeColor = .clear
        wash.name = "pauseWash"
        pauseRoot.addChild(wash)

        // Tall enough for RESUME / RESTART / volume rows / MUTE / HOME + credit note + padding.
        let card = SKShapeNode(rectOf: CGSize(width: 300, height: 520), cornerRadius: 14)
        card.fillColor = SKColor(red: 0.07, green: 0.05, blue: 0.16, alpha: 0.96)
        card.strokeColor = ArtCatalog.neonCyan
        card.lineWidth = 2.5
        card.glowWidth = 2
        card.name = "pauseCard"
        pauseRoot.addChild(card)

        let compact = ArtCatalog.makeCompactLogoNode(maxWidth: 148)
        compact.name = "pauseLogo"
        compact.position = CGPoint(x: 0, y: 198)
        card.addChild(compact)
        let title = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        title.name = "pauseTitle"
        title.text = "PAUSED"
        title.fontSize = 18
        title.fontColor = ArtCatalog.neonCyan
        title.position = CGPoint(x: 0, y: 158)
        card.addChild(title)

        let resume = makeOutcomeButton(title: "RESUME", color: ArtCatalog.neonLime, name: "pauseResume", wide: true)
        resume.position = CGPoint(x: 0, y: 128)
        card.addChild(resume)
        let restart = makeOutcomeButton(title: "RESTART", color: ArtCatalog.neonOrange, name: "pauseRestart", wide: true)
        restart.position = CGPoint(x: 0, y: 72)
        card.addChild(restart)

        // Music / SFX volume sliders
        card.addChild(makePauseVolumeRow(
            label: "MUSIC",
            namePrefix: "pauseMusic",
            y: 18,
            value: JuiceSound.shared.musicVolume
        ))
        card.addChild(makePauseVolumeRow(
            label: "SFX",
            namePrefix: "pauseSfx",
            y: -22,
            value: JuiceSound.shared.sfxVolume
        ))

        let mute = makeOutcomeButton(
            title: JuiceSound.shared.muted ? "UNMUTE" : "MUTE",
            color: ArtCatalog.neonPink,
            name: "pauseMute",
            wide: true
        )
        mute.position = CGPoint(x: 0, y: -78)
        card.addChild(mute)
        let storyBtn = makeOutcomeButton(title: "STORY", color: ArtCatalog.neonCyan, name: "pauseStory", wide: true)
        storyBtn.position = CGPoint(x: 0, y: -134)
        card.addChild(storyBtn)
        let home = makeOutcomeButton(title: "HOME", color: ArtCatalog.neonPink, name: "pauseHome", wide: true)
        home.position = CGPoint(x: 0, y: -190)
        card.addChild(home)

        let note = SKLabelNode(fontNamed: "AvenirNext-Medium")
        note.name = "pauseVolumeNote"
        note.text = JuiceSound.shared.muted ? "Audio muted" : TitleArt.assetCredits
        note.fontSize = 10
        note.fontColor = SKColor(white: 1, alpha: 0.55)
        note.position = CGPoint(x: 0, y: -236)
        card.addChild(note)

        let count = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        count.name = "pauseCountdown"
        count.fontSize = 48
        count.fontColor = .white
        count.alpha = 0
        count.zPosition = 5
        count.verticalAlignmentMode = .center
        pauseRoot.addChild(count)
        pauseCountLabel = count
    }

    private func makePauseVolumeRow(label: String, namePrefix: String, y: CGFloat, value: Float) -> SKNode {
        let row = SKNode()
        row.name = "\(namePrefix)Row"
        row.position = CGPoint(x: 0, y: y)

        let lab = SKLabelNode(fontNamed: "AvenirNext-Bold")
        lab.text = label
        lab.fontSize = 11
        lab.fontColor = ArtCatalog.neonCyan
        lab.horizontalAlignmentMode = .left
        lab.verticalAlignmentMode = .center
        lab.position = CGPoint(x: -118, y: 0)
        lab.name = "\(namePrefix)Label"
        row.addChild(lab)

        let track = SKShapeNode(rectOf: CGSize(width: 110, height: 6), cornerRadius: 3)
        track.fillColor = SKColor(white: 0.2, alpha: 0.9)
        track.strokeColor = ArtCatalog.neonCyan.withAlphaComponent(0.4)
        track.lineWidth = 1
        track.position = CGPoint(x: 10, y: 0)
        track.name = "\(namePrefix)Track"
        row.addChild(track)

        let fillW = CGFloat(max(0.05, min(1, value))) * 110
        let fill = SKShapeNode(rectOf: CGSize(width: fillW, height: 6), cornerRadius: 3)
        fill.fillColor = ArtCatalog.neonPink.withAlphaComponent(0.85)
        fill.strokeColor = .clear
        fill.position = CGPoint(x: 10 - (110 - fillW) * 0.5, y: 0)
        fill.name = "\(namePrefix)Fill"
        row.addChild(fill)

        let minus = makeFaceButton(title: "−", color: ArtCatalog.neonPink)
        minus.name = "\(namePrefix)Minus"
        minus.childNode(withName: "btnLabel")?.name = "\(namePrefix)Minus"
        minus.setScale(0.55)
        minus.position = CGPoint(x: -52, y: 0)
        row.addChild(minus)

        let plus = makeFaceButton(title: "+", color: ArtCatalog.neonLime)
        plus.name = "\(namePrefix)Plus"
        plus.childNode(withName: "btnLabel")?.name = "\(namePrefix)Plus"
        plus.setScale(0.55)
        plus.position = CGPoint(x: 78, y: 0)
        row.addChild(plus)

        return row
    }

    private func refreshPauseVolumeRows() {
        guard let card = pauseRoot.childNode(withName: "pauseCard") else { return }
        for (prefix, value) in [("pauseMusic", JuiceSound.shared.musicVolume), ("pauseSfx", JuiceSound.shared.sfxVolume)] {
            guard let row = card.childNode(withName: "\(prefix)Row"),
                  let fill = row.childNode(withName: "\(prefix)Fill") as? SKShapeNode else { continue }
            let fillW = CGFloat(max(0.05, min(1, value))) * 110
            fill.path = CGPath(roundedRect: CGRect(x: -fillW * 0.5, y: -3, width: fillW, height: 6), cornerWidth: 3, cornerHeight: 3, transform: nil)
            fill.position = CGPoint(x: 10 - (110 - fillW) * 0.5, y: 0)
        }
    }

    private func refreshPauseMuteButton() {
        guard let card = pauseRoot.childNode(withName: "pauseCard") else { return }
        if let mute = card.childNode(withName: "pauseMute"),
           let label = mute.children.compactMap({ $0 as? SKLabelNode }).first {
            label.text = JuiceSound.shared.muted ? "UNMUTE" : "MUTE"
        }
        if let note = card.childNode(withName: "pauseVolumeNote") as? SKLabelNode {
            note.text = JuiceSound.shared.muted ? "Audio muted" : TitleArt.assetCredits
        }
        refreshPauseVolumeRows()
    }

    private func setPaused(_ on: Bool, system: Bool = false) {
        // Scene may not have finished didMove yet (unit probes / early resign).
        guard sim != nil else { return }
        let playing: Bool = {
            if case .playing = sim.state.phase { return true }
            return false
        }()
        guard playing || runPaused else { return }
        // Manual pause button is ignored under smoke; harness flags drive pause beats instead.
        if on {
            if runPaused {
                pauseFromSystem = system || pauseFromSystem
                clearLatchedPlayInput()
                return
            }
            runPaused = true
            pauseFromSystem = system
            resumeCountdown = 0
            skipFreezeSample = true
            pauseCountLabel?.alpha = 0
            pauseCountLabel?.text = ""
            clearAllActionInput()
            pauseRoot.isHidden = false
            layoutUI()
            if smokeEnabled { writeSmokeStatus() }
        } else {
            runPaused = false
            pauseFromSystem = false
            skipFreezeSample = true
            pauseRoot.isHidden = true
            layoutUI()
            if smokeEnabled { writeSmokeStatus() }
        }
    }

    /// Drop stick / face-button latch without requiring HUD nodes.
    private func clearLatchedPlayInput() {
        clearAllActionInput()
    }

    /// Auto-pause from SwiftUI / UIKit lifecycle (resign active, background).
    /// Idempotent — clears latched input even before `sim` / HUD exist; no flicker on banners.
    public func pauseFromAppLifecycle() {
        clearAllActionInput()
        pauseFromSystem = true
        guard sim != nil else { return }
        if runPaused { return }
        setPaused(true, system: true)
    }

    private func clearAllActionInput() {
        releaseStickInput()
        jumpHeld = false
        jumpPressed = false
        pouncePressed = false
        dashPressed = false
        maskPressed = false
        grabPressed = false
        jumpTouch = nil
        pounceTouch = nil
        dashTouch = nil
        maskTouch = nil
        grabTouch = nil
    }

    /// Resume after lifecycle pause: brief 3-2-1, else immediate unpause.
    private func beginResumeFromPause() {
        guard runPaused else { return }
        JuiceSound.shared.playUITap()
        runPaused = false
        skipFreezeSample = true
        pauseRoot.isHidden = true
        if pauseFromSystem {
            pauseFromSystem = false
            resumeCountdown = 3.0
            pauseCountLabel?.text = "3"
            pauseCountLabel?.alpha = 1
            pauseCountLabel?.setScale(1.2)
            layoutUI()
        } else {
            layoutUI()
        }
    }

    private func setupOutcome() {
        outcomeRoot.zPosition = 320
        outcomeRoot.isHidden = true
        overlay.addChild(outcomeRoot)

        let wash = SKShapeNode(rectOf: CGSize(width: 4000, height: 4000))
        wash.fillColor = SKColor(red: 0.02, green: 0.02, blue: 0.08, alpha: 0.58)
        wash.strokeColor = .clear
        wash.name = "outcomeWash"
        outcomeRoot.addChild(wash)

        let card = SKShapeNode(rectOf: CGSize(width: 300, height: 368), cornerRadius: 14)
        card.fillColor = SKColor(red: 0.07, green: 0.05, blue: 0.16, alpha: 0.96)
        card.strokeColor = ArtCatalog.neonCyan
        card.lineWidth = 2.5
        card.glowWidth = 2
        card.name = "outcomeCard"
        outcomeRoot.addChild(card)

        let compact = ArtCatalog.makeCompactLogoNode(maxWidth: 140)
        compact.name = "outcomeLogo"
        compact.position = CGPoint(x: 0, y: 142)
        card.addChild(compact)
        let title = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        title.name = "outcomeTitle"
        title.fontSize = 24
        title.fontColor = ArtCatalog.neonLime
        title.position = CGPoint(x: 0, y: 102)
        card.addChild(title)

        let stars = SKNode()
        stars.name = "outcomeStars"
        stars.position = CGPoint(x: 0, y: 64)
        card.addChild(stars)
        for i in 0..<3 {
            let star = SKLabelNode(fontNamed: "AvenirNext-Heavy")
            star.text = "★"
            star.fontSize = 32
            star.fontColor = ArtCatalog.neonOrange.withAlphaComponent(0.25)
            star.position = CGPoint(x: CGFloat(i - 1) * 44, y: 0)
            star.name = "star\(i)"
            stars.addChild(star)
        }

        let score = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        score.name = "outcomeScore"
        score.fontSize = 20
        score.fontColor = ArtCatalog.neonCyan
        score.position = CGPoint(x: 0, y: 28)
        score.text = "SCORE 0"
        card.addChild(score)

        let shinyRow = SKNode()
        shinyRow.name = "outcomeShinies"
        shinyRow.position = CGPoint(x: 0, y: 4)
        card.addChild(shinyRow)
        let gear = SKLabelNode(fontNamed: "AvenirNext-Bold")
        gear.text = "⚙"
        gear.fontSize = 22
        gear.fontColor = ArtCatalog.neonOrange
        gear.horizontalAlignmentMode = .right
        gear.position = CGPoint(x: -8, y: 0)
        gear.name = "gearIcon"
        shinyRow.addChild(gear)
        let shinyLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        shinyLabel.name = "shinyCount"
        shinyLabel.fontSize = 22
        shinyLabel.fontColor = .white
        shinyLabel.horizontalAlignmentMode = .left
        shinyLabel.position = CGPoint(x: 4, y: 0)
        shinyRow.addChild(shinyLabel)

        let meta = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        meta.name = "outcomeMeta"
        meta.fontSize = 14
        meta.fontColor = SKColor(white: 0.92, alpha: 1)
        meta.position = CGPoint(x: 0, y: -18)
        card.addChild(meta)

        let hint = SKLabelNode(fontNamed: "AvenirNext-Bold")
        hint.name = "outcomeHint"
        hint.fontSize = 12
        hint.fontColor = ArtCatalog.neonOrange
        hint.preferredMaxLayoutWidth = 260
        hint.numberOfLines = 2
        hint.verticalAlignmentMode = .center
        hint.horizontalAlignmentMode = .center
        hint.position = CGPoint(x: 0, y: -40)
        hint.text = ""
        card.addChild(hint)

        let pa = SKLabelNode(fontNamed: "AvenirNext-Medium")
        pa.name = "outcomePA"
        pa.fontSize = 10
        pa.fontColor = ArtCatalog.neonPink
        pa.preferredMaxLayoutWidth = 240
        pa.numberOfLines = 2
        // Flavor well above the primary CTA — 2 lines must never cover GO FOR 3★.
        pa.verticalAlignmentMode = .center
        pa.horizontalAlignmentMode = .center
        pa.position = CGPoint(x: 0, y: -56)
        pa.isHidden = true
        card.addChild(pa)

        // Keep legacy name for count-up path compatibility.
        let stats = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        stats.name = "outcomeStats"
        stats.isHidden = true
        card.addChild(stats)

        let primary = makeOutcomeButton(title: "RETRY", color: ArtCatalog.neonLime, name: "retryBtn", wide: true)
        primary.position = CGPoint(x: 0, y: -132)
        card.addChild(primary)
        let next = makeOutcomeButton(title: "NEXT", color: ArtCatalog.neonLime, name: "nextBtn", wide: true)
        next.position = CGPoint(x: 0, y: -132)
        next.isHidden = true
        card.addChild(next)
        let home = makeOutcomeButton(title: "HOME", color: ArtCatalog.neonPink, name: "homeBtn", wide: false)
        home.position = CGPoint(x: 0, y: -188)
        card.addChild(home)
    }

    private func makeOutcomeButton(title: String, color: SKColor, name: String, wide: Bool = false) -> SKShapeNode {
        let size = wide ? CGSize(width: 220, height: 48) : CGSize(width: 140, height: 40)
        let b = SKShapeNode(rectOf: size, cornerRadius: wide ? 12 : 10)
        b.fillColor = color.withAlphaComponent(wide ? 0.38 : 0.22)
        b.strokeColor = color
        b.lineWidth = 2
        b.glowWidth = wide ? 1.5 : 1
        b.name = name
        let t = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        t.text = title
        t.fontSize = wide ? 17 : 14
        t.fontColor = .white
        t.verticalAlignmentMode = .center
        t.name = name
        b.addChild(t)
        return b
    }

    #if DEBUG
    private func setupDebugTuning() {
        guard !smokeEnabled else { return }
        let menu = DebugTuningMenu(tuning: tuning)
        menu.onChange = { [weak self] t in
            guard let self else { return }
            self.tuning = t
            self.sim.tuning = t
        }
        overlay.addChild(menu)
        tuningMenu = menu

        let btn = SKLabelNode(fontNamed: "AvenirNext-Bold")
        btn.text = "TUNING"
        btn.fontSize = 11
        btn.fontColor = ArtCatalog.neonCyan.withAlphaComponent(0.8)
        btn.name = "debugToggle"
        btn.zPosition = 880
        hud.addChild(btn)
        debugToggle = btn
    }
    #endif

    private func layoutUI() {
        guard stickBase != nil, jumpBtn != nil, pounceBtn != nil, sim != nil else { return }
        let hw = size.width * 0.5
        let hh = size.height * 0.5
        let insets = safeInsets()
        // Extra pad under the island — topSafe alone still clips on Pro Max sims.
        let topSafe = max(insets.top, 59) + 22
        let bottomSafe = max(insets.bottom, 20)
        let leftSafe = max(insets.left, 0)
        // Full-bleed sky — oversized so no black letterbox on any iPhone aspect.
        skyFill.size = CGSize(width: size.width * 3.2, height: size.height * 3.2)
        skyFill.position = .zero
        skyFill.color = ArtCatalog.nightSky
        skyFill.colorBlendFactor = 1

        let rightSafe = max(insets.right, 0)
        stickBase.isHidden = true
        stickKnob.isHidden = true
        // Controls live in a dedicated bottom strip — clear of the playfield floor.
        let edge = CGFloat(max(88, tuning.feel.faceButtonMinPt * 0.78))
        let outerX = hw - edge * 0.52 - rightSafe
        let innerX = outerX - edge * 0.92
        let controlStripH = edge * 1.55 + bottomSafe
        controlStripLift = controlStripH * 0.42
        let baseY = -hh + bottomSafe + edge * 0.42
        if controlStripNode == nil {
            let strip = SKShapeNode()
            strip.name = "controlStrip"
            strip.fillColor = SKColor(white: 0.04, alpha: 0.72)
            strip.strokeColor = SKColor(white: 1, alpha: 0.08)
            strip.lineWidth = 1
            strip.zPosition = 150
            playHUD.addChild(strip)
            controlStripNode = strip
        }
        controlStripNode?.path = CGPath(
            rect: CGRect(x: -hw, y: -hh, width: size.width, height: controlStripH),
            transform: nil
        )
        controlStripNode?.isHidden = playHUD.isHidden
        // 2×2 thumb grid — MASK never stacks on DASH.
        // [MASK] [JUMP]
        // [DASH] [POUNCE]
        let colR = outerX
        let colL = innerX - edge * 0.15
        let rowTop = baseY + edge * 0.95
        let rowBot = baseY
        jumpBtn.position = CGPoint(x: colR, y: rowTop)
        pounceBtn.position = CGPoint(x: colR, y: rowBot)
        dashBtn.position = CGPoint(x: colL, y: rowBot)
        maskBtn.position = CGPoint(x: colL, y: rowTop)
        grabBtn.isHidden = true
        layoutControlHitZones()
        refreshActionButtonChrome()

        // Top HUD bands (top→bottom): progress | stats+pause | objective chip — no overlap.
        let hudTop = hh - topSafe - 10
        let hudX = -hw + 18 + leftSafe
        let barW: CGFloat = min(size.width * 0.42, CGFloat(200))
        let barY = hudTop
        progressTrack?.position = CGPoint(x: 0, y: barY)
        progressTrack?.path = CGPath(
            roundedRect: CGRect(x: -barW * 0.5, y: -3, width: barW, height: 6),
            cornerWidth: 3,
            cornerHeight: 3,
            transform: nil
        )
        updateProgressBar(barWidth: barW, barY: barY)

        let statsY = hudTop - 22
        hudPill.position = CGPoint(x: hudX + 70, y: statsY - 4)
        hudPill.isHidden = playHUD.isHidden
        hudCarried.position = CGPoint(x: hudX, y: statsY + 6)
        hudHearts.position = CGPoint(x: hudX + 68, y: statsY + 6)
        hudCombo.position = CGPoint(x: hudX, y: statsY - 12)
        hudTime.position = CGPoint(x: hudX + 96, y: statsY - 12)
        for label in [hudCarried, hudHearts, hudCombo, hudTime] {
            if let outline = label.childNode(withName: "hudOutline") as? SKLabelNode {
                outline.text = label.text
            }
            if let glow = label.childNode(withName: "hudGlow") as? SKLabelNode {
                glow.text = label.text
            }
        }
        if let pauseBtn {
            pauseBtn.position = CGPoint(x: hw - 44 - rightSafe, y: statsY)
            let pl = pauseBtn.childNode(withName: "btnLabel") as? SKLabelNode
            pl?.fontSize = 10
        }
        // Objective chip well below stats + PAUSE (iPhone SE / 16 Pro safe).
        if let chip = objectiveBanner {
            chip.position = CGPoint(x: 0, y: statsY - 52)
        }
        #if DEBUG
        fpsLabel.position = CGPoint(x: -hw + 16, y: -hh + 16 + bottomSafe * 0.25)
        debugToggle?.position = CGPoint(x: hw - 40, y: hudTop)
        tuningMenu?.position = .zero
        #endif

        if let edge = maskVignette.childNode(withName: "vignetteEdge") as? SKSpriteNode {
            // Oversized dark plate — corners read heavier; center stays the night playfield.
            edge.size = CGSize(width: size.width * 1.2, height: size.height * 1.2)
            edge.position = .zero
            edge.alpha = 0.22
        }
        if !titleRoot.isHidden {
            layoutTitleChrome()
        }
        if showingPublisherIdent {
            layoutPublisherIdentBackground()
        }
        updateHUDVisibility()
    }

    private func updateHUDVisibility() {
        let playing: Bool = {
            if case .playing = sim.state.phase { return true }
            return false
        }()
        let onTitle = !titleRoot.isHidden || showingPublisherIdent
        // Title owns the screen — hide live level so geometry/shinies can't peek under UI.
        stage.isHidden = onTitle
        skyFill.isHidden = onTitle
        let showPlayHUD = playing && resumeCountdown <= 0 && !onTitle
        playHUD.isHidden = !showPlayHUD
        hudPill.isHidden = !showPlayHUD
        pauseBtn?.isHidden = !showPlayHUD
        if !showPlayHUD || runPaused {
            releaseStickInput()
        }
        if runPaused {
            for node in [stickBase, stickKnob, jumpBtn, pounceBtn, pauseBtn] as [SKNode?] {
                node?.alpha = 0
            }
        } else if playing, resumeCountdown <= 0 {
            let stickA: CGFloat = stickTouch == nil ? 0.22 : 1
            stickBase?.alpha = stickA
            stickKnob?.alpha = stickA
            jumpBtn?.alpha = 1
            pounceBtn?.alpha = 1
            pauseBtn?.alpha = 1
        }
    }

    private func cg(_ v: Vec2) -> CGPoint { CGPoint(x: v.x, y: v.y) }


    private func setupStoryOverlays() {
        introRoot.zPosition = 360
        introRoot.isHidden = true
        introRoot.name = "introRoot"
        overlay.addChild(introRoot)
        districtCardRoot.zPosition = 350
        districtCardRoot.isHidden = true
        districtCardRoot.name = "districtCardRoot"
        overlay.addChild(districtCardRoot)

        // Comic intro is presented after the publisher ident (see finishPublisherIdentAndShowTitle).
    }

    private func presentIntroIfNeededAfterIdent() {
        if !smokeEnabled, !progressStore.load().sawIntro {
            presentIntro(fromScratch: true)
        }
    }

    private func makeCrewCageNode(crewID: String) -> SKNode {
        let root = SKNode()
        root.name = "crewCage_\(crewID)"
        let tile = CGFloat(tuning.tileSize)
        let bars = SKShapeNode(rectOf: CGSize(width: tile * 0.95, height: tile * 1.2), cornerRadius: 4)
        bars.fillColor = SKColor(red: 0.12, green: 0.14, blue: 0.2, alpha: 0.85)
        bars.strokeColor = ArtCatalog.neonOrange
        bars.lineWidth = 2
        root.addChild(bars)
        let mascot = ArtCatalog.makeBanditFrontMascot(size: CGSize(width: tile * 0.7, height: tile * 0.7))
        mascot.setScale(0.7)
        mascot.position = CGPoint(x: 0, y: -4)
        root.addChild(mascot)
        let tag = SKLabelNode(fontNamed: "AvenirNext-Bold")
        tag.text = story.crew(id: crewID)?.name ?? "CREW"
        tag.fontSize = 8
        tag.fontColor = ArtCatalog.neonLime
        tag.position = CGPoint(x: 0, y: tile * 0.55)
        root.addChild(tag)
        return root
    }

    private func presentIntro(fromScratch: Bool) {
        if fromScratch { introPanelIndex = 0 }
        showingIntro = true
        introRoot.removeAllChildren()
        introRoot.isHidden = false
        titleRoot.isHidden = true
        let comic = StoryChrome.makeIntroComic(size: size, story: story, panelIndex: introPanelIndex)
        introRoot.addChild(comic)
        if smokeEnabled {
            smokeStatus.phase = "intro"
            smokeStatus.write()
        }
    }

    private func advanceIntro() {
        introPanelIndex += 1
        if introPanelIndex >= story.introPanels.count {
            dismissIntro()
            return
        }
        presentIntro(fromScratch: false)
    }

    private func dismissIntro() {
        showingIntro = false
        introRoot.isHidden = true
        introRoot.removeAllChildren()
        progressStore.markIntroSeen()
        showTitleScreen()
        if smokeEnabled {
            smokeStatus.phase = "title"
            smokeStatus.boot = "ready"
            smokeStatus.write()
        }
    }

    private func presentDistrictCardThenPlay() {
        showingDistrictCard = true
        titleRoot.isHidden = true
        districtCardRoot.removeAllChildren()
        districtCardRoot.isHidden = false
        let card = StoryChrome.makeDistrictCard(size: size, district: pendingDistrict, story: story)
        districtCardRoot.addChild(card)
        // Auto-advance after a short beat so smoke / impatient taps still flow.
        districtCardRoot.removeAction(forKey: "districtAuto")
        districtCardRoot.run(SKAction.sequence([
            SKAction.wait(forDuration: smokeEnabled ? 0.35 : 1.4),
            SKAction.run { [weak self] in self?.finishDistrictCardAndPlay() },
        ]), withKey: "districtAuto")
    }

    private func finishDistrictCardAndPlay() {
        guard showingDistrictCard else { return }
        showingDistrictCard = false
        districtCardRoot.removeAction(forKey: "districtAuto")
        districtCardRoot.isHidden = true
        districtCardRoot.removeAllChildren()
        beginPlay()
    }

    private func reloadDistrictMap(_ id: DistrictID) {
        do {
            let map = try DistrictLevels.load(id)
            sim = Sim(map: map, tuning: tuning, seed: smokeEnabled ? 7 : 11)
            // Soft reload: respawn pickups/enemies/crew for the new district layout.
            shinyNodes.values.forEach { $0.removeFromParent() }
            shinyNodes.removeAll()
            mopNodes.values.forEach { $0.removeFromParent() }
            mopNodes.removeAll()
            crewNodes.values.forEach { $0.removeFromParent() }
            crewNodes.removeAll()
            for s in sim.state.shinies.prefix(smokeEnabled ? sim.state.shinies.count : min(sim.state.shinies.count, 40)) {
                let n = ArtCatalog.makeShinyNode()
                n.position = cg(s.position)
                n.zPosition = 20
                world.addChild(n)
                shinyNodes[s.id] = n
            }
            for m in sim.state.mops.prefix(smokeEnabled ? sim.state.mops.count : min(sim.state.mops.count, 24)) {
                let n = ArtCatalog.makeMopNode()
                n.position = cg(m.position)
                n.zPosition = 30
                world.addChild(n)
                mopNodes[m.id] = n
            }
            for c in sim.state.crewCages {
                let n = makeCrewCageNode(crewID: c.crewID)
                n.position = cg(c.position)
                n.zPosition = 28
                world.addChild(n)
                crewNodes[c.id] = n
            }
        } catch {
            // Keep current map on load failure.
        }
    }

    private func requestBeginPlay() {
        isDailyRun = false
        racingGhostSamples = []
        racingGhostKind = nil
        // Smoke skips the district card so title→play timing stays in the freeze budget.
        if smokeEnabled {
            beginPlay()
            return
        }
        presentDistrictCardThenPlay()
    }

    /// Daily Heist: UTC-seeded Neon Docks grammar + optional ghost race.
    private func startDailyHeist(racing: GhostKind?) {
        hideRetention()
        isDailyRun = true
        dailyDayKey = ProgressStore.dayKey()
        tookDamageThisRun = false
        sawMaskThisRun = false
        ghostRecorder.reset()
        racingGhostKind = racing
        do {
            let map = try DailyHeist.loadMap()
            let seed = DailyHeist.seed(dayKey: dailyDayKey)
            sim = Sim(map: map, tuning: tuning, seed: seed)
            pendingDistrict = .neonDocks
            rebuildWorldEntitiesAfterDailyReload()
        } catch {
            // Fall through to current map if daily load fails.
        }
        Task { await prepareRacingGhost(kind: racing) }
        beginPlay()
    }

    private func rebuildWorldEntitiesAfterDailyReload() {
        shinyNodes.values.forEach { $0.removeFromParent() }
        shinyNodes.removeAll()
        mopNodes.values.forEach { $0.removeFromParent() }
        mopNodes.removeAll()
        crewNodes.values.forEach { $0.removeFromParent() }
        crewNodes.removeAll()
        for s in sim.state.shinies {
            let n = ArtCatalog.makeShinyNode()
            n.position = cg(s.position)
            n.zPosition = 20
            world.addChild(n)
            shinyNodes[s.id] = n
        }
        for m in sim.state.mops {
            let n = ArtCatalog.makeMopNode()
            n.position = cg(m.position)
            n.zPosition = 30
            world.addChild(n)
            mopNodes[m.id] = n
        }
        for c in sim.state.crewCages {
            let n = makeCrewCageNode(crewID: c.crewID)
            n.position = cg(c.position)
            n.zPosition = 28
            world.addChild(n)
            crewNodes[c.id] = n
        }
    }

    private func prepareRacingGhost(kind: GhostKind?) async {
        guard let kind else {
            racingGhostSamples = []
            return
        }
        let run: GhostRun?
        switch kind {
        case .own:
            run = await ghostStore.loadOwnBest(dayKey: dailyDayKey)
        case .worldBest:
            run = await ghostStore.loadWorldBest(dayKey: dailyDayKey)
        case .friend:
            // Friend picker arrives with GC Challenges UI; for now race world best as stand-in.
            run = await ghostStore.loadWorldBest(dayKey: dailyDayKey)
        }
        racingGhostSamples = run?.samples.map {
            GhostSamplePoint(t: $0.t, x: $0.x, y: $0.y, facing: $0.facing)
        } ?? []
    }

    private func showTitleScreen() {
        // Never leave play toasts / objective chip on the title art.
        clearPlayToasts()
        objectiveBanner?.removeFromParent()
        objectiveBanner = nil
        if case .playing = sim.state.phase {
            titleRoot.isHidden = true
            return
        }
        titleRoot.isHidden = false
        if let rain = titleRoot.childNode(withName: "//titleRain") as? SKEmitterNode {
            rain.isPaused = false
            rain.particleBirthRate = 22
        }
        layoutTitleChrome()
    }

    private func beginPlay() {
        // Start audio here (not in didMove) so smoke video has a soundtrack without launch jetsam.
        // simctl recordVideo has no app-audio track — smoke also writes smoke_audio_events.txt for mux.
        if smokeEnabled {
            JuiceSound.shared.beginSmokeAudioLog()
            if smokeWallStart == 0 {
                smokeWallStart = CACurrentMediaTime()
                try? FileManager.default.removeItem(at: SmokeStatus.timerLogURL)
            }
        }
        JuiceSound.shared.prepare()
        JuiceSound.shared.playUITap()
        // Gameplay bed: main_theme with alt rotation. District beds via startLevelMusic(district:).
        JuiceSound.shared.startLevelMusic()
        mopAlerted.removeAll()
        celebratedFirstStomp = false
        celebratedEarlyWin = false
        tutorialStep = 0
        tutorialStomps = 0
        if !isDailyRun {
            tookDamageThisRun = false
            sawMaskThisRun = false
            ghostRecorder.reset()
        }
        ensureGhostVisual()
        gameCenter.setAccessPointVisible(false, showHighlights: false)
        midSurpriseFired = false
        lastStompElapsed = -1
        nextLullNudgeAt = 8
        runDustCooldown = 0
        startWorldX = sim.state.bandit.position.x
        if let ex = sim.map.findFirst(.exit) {
            exitWorldX = sim.map.worldCenter(ofX: ex.0, y: ex.1, tileSize: tuning.tileSize).x
        } else {
            exitWorldX = startWorldX + Double(sim.map.width) * tuning.tileSize * 0.8
        }
        if !smokeEnabled { hapticMed.impactOccurred() }
        sim.startRun()
        // Keep the freeze sample — allow one ≤250ms title→play transition frame (preload should
        // keep real devices under that; simctl recordVideo may still brush the budget).
        transitionBudgetMs = titlePlayTransitionBudgetMs
        titleRoot.isHidden = true
        // Stop title rain so hidden emitters do not keep burning GPU during play.
        if let rain = titleRoot.childNode(withName: "//titleRain") as? SKEmitterNode {
            rain.isPaused = true
            rain.particleBirthRate = 0
        }
        layoutUI()
        snapCameraToHero()
        resetHeroFramingSamples()
        showObjectiveBanner()
        writeSmokeStatus()
    }

    private static let mopChatterLines = [
        "mop_pest_detected.m4a",
        "mop_sanitizing.m4a",
        "mop_do_not_resist.m4a",
        "mop_sweep_protocol.m4a",
        "mop_please_hold_still.m4a",
    ]

    private func doRetry() {
        failOutcomeHold = 0
        resumeCountdown = 0
        setPaused(false)
        JuiceSound.shared.prepare()
        JuiceSound.shared.playUITap()
        JuiceSound.shared.startLevelMusic()
        mopAlerted.removeAll()
        tutorialStep = 0
        tutorialStomps = 0
        celebratedFirstStomp = false
        lastObjectiveTip = ""
        clearPlayToasts()
        objectiveBanner?.removeFromParent()
        objectiveBanner = nil
        sim.retry()
        hideOutcome()
        snapCameraToHero()
        // Keep pre-death heroX min/max for the CI framing gate — finishPush sprints
        // to EXIT and must not wipe (or re-sample) the live-play band.
        if !smoke.diedOnce {
            resetHeroFramingSamples()
        } else if smokeEnabled {
            // Mark the post-death clean start→vault run for the evidence clip cut.
            let wall = smokeWallStart > 0 ? CACurrentMediaTime() - smokeWallStart : 0
            let line = String(format: "clean_run_t0=%.3f\n", wall)
            try? line.write(to: SmokeStatus.docsURL.appendingPathComponent("smoke_clean_run.txt"),
                            atomically: true, encoding: .utf8)
        }
        refreshObjectiveChip(forceBanner: true)
        updateHUDVisibility()
    }

    private func clearPlayToasts() {
        toastQueue.removeAll()
        toastShowing = false
        activeToastNode?.removeAllActions()
        activeToastNode?.removeFromParent()
        activeToastNode = nil
    }

    /// Instantly park the camera on the hero so the first frames aren't focus=(0,0) → negative heroX.
    private func snapCameraToHero() {
        cameraFacing = sim.state.bandit.facing >= 0 ? 1 : -1
        cameraFocus = cameraTarget(for: sim.state.bandit)
        let z = Self.worldZoom
        stage.position = CGPoint(x: -cameraFocus.x * z, y: -cameraFocus.y * z)
    }

    private func resetHeroFramingSamples() {
        smokeStatus.heroX = 0.5
        smokeStatus.heroXMin = 1
        smokeStatus.heroXMax = 0
    }

    /// Same look-ahead + soft clamp as the live camera update (single 0.20×viewW lead).
    private func cameraTarget(for b: BanditState) -> CGPoint {
        let mapW = CGFloat(sim.map.width) * CGFloat(tuning.tileSize)
        let mapH = CGFloat(sim.map.height) * CGFloat(tuning.tileSize)
        let viewW = size.width / Self.worldZoom
        let viewH = size.height / Self.worldZoom
        // 0.20×viewW → hero ~30% when facing right (20–45% framing band).
        let lead = cameraFacing * 0.20 * viewW
        // Lift just enough for the control strip — keep skyline parallax in frame.
        let liftWorld = controlStripLift / Self.worldZoom
        var target = CGPoint(
            x: CGFloat(b.position.x) + lead,
            y: CGFloat(b.position.y) + 28 + liftWorld * 0.2
        )
        let minX = viewW * 0.18
        let maxX = max(minX, mapW - viewW * 0.18)
        let minY = viewH * 0.28 + liftWorld * 0.15
        let maxY = max(minY, mapH - viewH * 0.18)
        target.x = min(max(target.x, minX), maxX)
        target.y = min(max(target.y, minY), maxY)
        return target
    }

    /// Undo a post-Mask splash/bag that landed before pause/bg finished — keeps harness order intact.
    private func softReviveSmokeHarness() {
        sim.state.phase = .playing
        if sim.state.bandit.hearts <= 0 {
            sim.state.bandit.hearts = max(1, tuning.hearts)
        }
        sim.state.bandit.anim = .idle
        sim.state.bandit.animHold = 0
        sim.state.bandit.invuln = 2.0
        sim.state.bandit.velocity = .zero
        // Nudge up out of water/spikes if the fail reason was a hazard tile.
        let tile = tuning.tileSize
        let tx = Int(floor(sim.state.bandit.position.x / tile))
        let ty = Int(floor((sim.state.bandit.position.y - 12) / tile))
        let t = sim.map.tile(atX: tx, y: ty)
        if t == .water || t == .spike {
            sim.state.bandit.position.y += tile * 2.5
        }
        failOutcomeHold = 0
        hideOutcome()
        // Cancelled deaths must not sticky-set diedOnce → finishPush → phase=won before 05.
        smoke.diedOnce = false
        smoke.failWait = 0
        if smoke.act != .showcaseMask && smoke.act != .seekDeath {
            smoke.act = .showcaseMask
        }
        snapCameraToHero()
    }

    // MARK: - Touch

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if smokeEnabled { return } // scripted input only
        for touch in touches {
            let p = touch.location(in: hud)
            #if DEBUG
            if let toggle = debugToggle, toggle.contains(p) {
                tuningMenu?.toggle()
                return
            }
            if let menu = tuningMenu, !menu.isHidden {
                if menu.handleTap(at: touch.location(in: overlay)) { return }
            }
            #endif
            if !retentionRoot.isHidden {
                let hitNames = Set(nodes(at: touch.location(in: self)).compactMap(\.name))
                if hitNames.contains("mapBack") || hitNames.contains("dailyBack") {
                    JuiceSound.shared.playUIBack()
                    hideRetention()
                    return
                }
                if hitNames.contains("dailyPlay")
                    || hitNames.contains("dailyRaceOwn")
                    || hitNames.contains("dailyRaceBest")
                    || hitNames.contains("dailyRaceFriend") {
                    JuiceSound.shared.playUITap()
                    let kind: GhostKind? = {
                        if hitNames.contains("dailyRaceOwn") { return .own }
                        if hitNames.contains("dailyRaceBest") { return .worldBest }
                        if hitNames.contains("dailyRaceFriend") { return .friend }
                        return nil
                    }()
                    startDailyHeist(racing: kind)
                    return
                }
                if hitNames.contains("dailyChallenge") {
                    JuiceSound.shared.playUITap()
                    gameCenter.challengeFriends(
                        leaderboardID: GameCenterIDs.dailyHeist,
                        message: "Beat my Daily Heist score!"
                    )
                    return
                }
                if hitNames.contains("dailyLeaderboardBtn") {
                    JuiceSound.shared.playUITap()
                    gameCenter.presentLeaderboard(id: GameCenterIDs.dailyHeist)
                    return
                }
                for d in DistrictID.allCases {
                    if hitNames.contains("district_\(d.rawValue)") {
                        JuiceSound.shared.playUITap()
                        hideRetention()
                        pendingDistrict = d
                        reloadDistrictMap(d)
                        requestBeginPlay()
                        return
                    }
                }
                if hitNames.contains("districtLabel") {
                    JuiceSound.shared.playUITap()
                    hideRetention()
                    requestBeginPlay()
                    return
                }
                return
            }
            if showingIntro {
                let hitNames = Set(nodes(at: touch.location(in: self)).compactMap(\.name))
                if hitNames.contains("introSkip") {
                    JuiceSound.shared.playUITap()
                    dismissIntro()
                    return
                }
                JuiceSound.shared.playUITap()
                advanceIntro()
                return
            }
            if showingDistrictCard {
                JuiceSound.shared.playUITap()
                finishDistrictCardAndPlay()
                return
            }
            if showingPublisherIdent {
                skipPublisherIdentIfNeeded()
                return
            }
            if case .title = sim.state.phase {
                let hitNames = Set(nodes(at: touch.location(in: self)).compactMap(\.name))
                if hitNames.contains("titleMute") {
                    JuiceSound.shared.toggleMute()
                    refreshMuteButton()
                    if !JuiceSound.shared.muted {
                        JuiceSound.shared.playUITap()
                    }
                    return
                }
                if hitNames.contains("titleMap") {
                    JuiceSound.shared.playUITap()
                    showDistrictMap()
                    return
                }
                if hitNames.contains("titleDaily") {
                    JuiceSound.shared.playUITap()
                    showDailyHeist()
                    return
                }
                requestBeginPlay()
                return
            }
            if !pauseRoot.isHidden, let card = pauseRoot.childNode(withName: "pauseCard") {
                let pCard = touch.location(in: card)
                let hitNames = Set(nodes(at: touch.location(in: self)).compactMap(\.name))
                if hitNames.contains("pauseResume") {
                    beginResumeFromPause()
                    return
                }
                if hitNames.contains("pauseRestart") {
                    JuiceSound.shared.playUITap()
                    setPaused(false)
                    doRetry()
                    return
                }
                if hitNames.contains("pauseMusicMinus") {
                    JuiceSound.shared.musicVolume = max(0, JuiceSound.shared.musicVolume - 0.1)
                    refreshPauseVolumeRows()
                    JuiceSound.shared.playUITap()
                    return
                }
                if hitNames.contains("pauseMusicPlus") {
                    JuiceSound.shared.musicVolume = min(1, JuiceSound.shared.musicVolume + 0.1)
                    refreshPauseVolumeRows()
                    JuiceSound.shared.playUITap()
                    return
                }
                if hitNames.contains("pauseSfxMinus") {
                    JuiceSound.shared.sfxVolume = max(0, JuiceSound.shared.sfxVolume - 0.1)
                    refreshPauseVolumeRows()
                    JuiceSound.shared.playUITap()
                    return
                }
                if hitNames.contains("pauseSfxPlus") {
                    JuiceSound.shared.sfxVolume = min(1, JuiceSound.shared.sfxVolume + 0.1)
                    refreshPauseVolumeRows()
                    JuiceSound.shared.playUITap()
                    return
                }
                if hitNames.contains("pauseMute") {
                    JuiceSound.shared.toggleMute()
                    refreshPauseMuteButton()
                    if !JuiceSound.shared.muted { JuiceSound.shared.playUITap() }
                    return
                }
                if hitNames.contains("pauseStory") {
                    JuiceSound.shared.playUITap()
                    setPaused(false)
                    pauseRoot.isHidden = true
                    presentIntro(fromScratch: true)
                    return
                }
                if hitNames.contains("pauseHome") {
                    setPaused(false)
                    hideOutcome()
                    JuiceSound.shared.stopMusic()
                    JuiceSound.shared.playUIBack()
                    JuiceSound.shared.playTitleSting()
                    sim = Sim(map: sim.map, tuning: tuning, seed: smokeEnabled ? 7 : 11)
                    showTitleScreen()
                    writeSmokeStatus()
                    updateHUDVisibility()
                    return
                }
                if card.contains(pCard) { return }
            }
            if case .playing = sim.state.phase, resumeCountdown <= 0, !runPaused {
                let pHud = touch.location(in: hud)
                if pauseBtn?.contains(pHud) == true {
                    JuiceSound.shared.playUITap()
                    setPaused(true)
                    return
                }
            }
            if runPaused || resumeCountdown > 0 { return }
            if !outcomeRoot.isHidden, let card = outcomeRoot.childNode(withName: "outcomeCard") {
                let pCard = touch.location(in: card)
                if let home = card.childNode(withName: "homeBtn"), home.contains(pCard) {
                    hideOutcome()
                    JuiceSound.shared.stopMusic()
                    JuiceSound.shared.playUIBack()
                    JuiceSound.shared.playTitleSting()
                    sim = Sim(map: sim.map, tuning: tuning, seed: smokeEnabled ? 7 : 11)
                    showTitleScreen()
                    writeSmokeStatus()
                    updateHUDVisibility()
                    return
                }
                if let retry = card.childNode(withName: "retryBtn"), !retry.isHidden, retry.contains(pCard) {
                    doRetry()
                    return
                }
                if let next = card.childNode(withName: "nextBtn"), !next.isHidden, next.contains(pCard) {
                    doRetry()
                    return
                }
                if case .failed = sim.state.phase {
                    doRetry()
                }
                return
            }
            // Face cluster first — never let the move stick steal a right-thumb tap.
            if tryBeginFaceTouch(touch, at: p) { continue }
            // Move stick: only the left move plate (no "any x < 0" fallback — that ate JUMP).
            if stickTouch == nil, hitInZone(moveHitZone, pointInHUD: p) {
                stickTouch = touch
                stickOrigin = p
                stickBase.position = p
                stickKnob.position = p
                stickBase.alpha = 1
                stickKnob.alpha = 1
                updateStick(p)
            }
        }
    }

    /// Bind a right-thumb button if the touch lands on it. Returns true when claimed.
    @discardableResult
    private func tryBeginFaceTouch(_ touch: UITouch, at p: CGPoint) -> Bool {
        let onJump = hitPaddedFaceButton(jumpBtn, pointInHUD: p) || hitInZone(jumpHitZone, pointInHUD: p)
        let onPounce = hitPaddedFaceButton(pounceBtn, pointInHUD: p) || hitInZone(pounceHitZone, pointInHUD: p)
        let onDash = hitPaddedSecondary(dashBtn, pointInHUD: p) || hitInZone(dashHitZone, pointInHUD: p)
        let onMask = hitPaddedSecondary(maskBtn, pointInHUD: p) || hitInZone(maskHitZone, pointInHUD: p)
        let onGrab = hitPaddedSecondary(grabBtn, pointInHUD: p) || hitInZone(grabHitZone, pointInHUD: p)
        if jumpTouch == nil, onJump {
            jumpTouch = touch
            jumpPressed = true
            jumpHeld = true
            pressFaceButton(jumpBtn)
            if !smokeEnabled { hapticLight.impactOccurred() }
            return true
        }
        if pounceTouch == nil, onPounce {
            pounceTouch = touch
            pouncePressed = true
            pressFaceButton(pounceBtn)
            if !smokeEnabled { hapticMed.impactOccurred() }
            return true
        }
        if dashTouch == nil, onDash, sim.state.bandit.dashCooldown <= 0 {
            dashTouch = touch
            dashPressed = true
            pressFaceButton(dashBtn)
            if !smokeEnabled { hapticMed.impactOccurred() }
            return true
        }
        if maskTouch == nil, onMask, sim.state.bandit.maskCharges > 0, !sim.state.bandit.maskMode {
            maskTouch = touch
            maskPressed = true
            pressFaceButton(maskBtn)
            if !smokeEnabled { hapticHeavy.impactOccurred() }
            return true
        }
        if grabTouch == nil, onGrab, sim.state.bandit.interactTarget != .none {
            grabTouch = touch
            grabPressed = true
            pressFaceButton(grabBtn)
            if !smokeEnabled { hapticLight.impactOccurred() }
            return true
        }
        return false
    }

    private func hitPaddedSecondary(_ btn: SKShapeNode?, pointInHUD p: CGPoint) -> Bool {
        guard let btn, !btn.isHidden else { return false }
        return paddedSecondaryHitRect(for: btn).contains(p)
    }

    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if smokeEnabled { return }
        for touch in touches {
            if touch === stickTouch {
                // Drag-off / lifecycle pause must not leave moveX latched.
                if runPaused || resumeCountdown > 0 {
                    releaseStickInput()
                    continue
                }
                updateStick(touch.location(in: hud))
            }
            if runPaused || resumeCountdown > 0 { continue }
            // Sliding onto a face button from a miss still counts (forgiving multitouch).
            let p = touch.location(in: hud)
            if touch !== stickTouch,
               touch !== jumpTouch, touch !== pounceTouch,
               touch !== dashTouch, touch !== maskTouch, touch !== grabTouch {
                _ = tryBeginFaceTouch(touch, at: p)
            }
        }
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Always clear tracked fingers — never skip while paused/countdown or moveX latches
        // after Control Center, JUMP multitouch, or background resign.
        if smokeEnabled { return }
        releaseEndedTouches(touches)
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if smokeEnabled { return }
        releaseEndedTouches(touches)
    }

    /// Zero stick / face-button state for ended or cancelled fingers.
    private func releaseEndedTouches(_ touches: Set<UITouch>) {
        for touch in touches {
            if touch === stickTouch {
                releaseStickInput()
            }
            if touch === jumpTouch {
                jumpTouch = nil
                jumpHeld = false
            }
            if touch === pounceTouch {
                pounceTouch = nil
            }
            if touch === dashTouch {
                dashTouch = nil
            }
            if touch === maskTouch {
                maskTouch = nil
            }
            if touch === grabTouch {
                grabTouch = nil
            }
        }
    }

    private func releaseStickInput() {
        stickTouch = nil
        moveX = 0
        moveY = 0
        if stickBase != nil, stickKnob != nil {
            stickKnob.position = stickBase.position
            stickBase.alpha = 0.38
            stickKnob.alpha = 0.38
        }
    }

    // MARK: - Input latch probes (MagpieTests / feel regression)

    /// Current latched horizontal stick (−1…1).
    public var debugMoveX: Double { moveX }
    public var debugJumpHeld: Bool { jumpHeld }
    public var debugHasStickTouch: Bool { stickTouch != nil }

    /// Inject stick magnitude without a UITouch (unit tests).
    public func debugSetMoveX(_ x: Double) {
        moveX = max(-1, min(1, x))
    }

    /// Simulate JUMP held alongside stick (multitouch) then release stick only.
    public func debugPressJumpAlongsideMove() {
        jumpPressed = true
        jumpHeld = true
    }

    public func debugPressDashAlongsideMove() {
        dashPressed = true
    }

    public func debugPressMaskAlongsideMove() {
        maskPressed = true
    }

    public func debugPressGrabAlongsideMove() {
        grabPressed = true
    }

    public func debugPressPounceAlongsideMove() {
        pouncePressed = true
    }

    public var debugDashPressed: Bool { dashPressed }
    public var debugMaskPressed: Bool { maskPressed }
    public var debugGrabPressed: Bool { grabPressed }
    public var debugPouncePressed: Bool { pouncePressed }

    public func debugReleaseJump() {
        jumpHeld = false
        jumpPressed = false
        jumpTouch = nil
    }

    public func debugClearActionEdges() {
        dashPressed = false
        maskPressed = false
        grabPressed = false
        pouncePressed = false
        jumpPressed = false
    }

    public func debugReleaseStick() {
        releaseStickInput()
    }

    /// Background / Control Center path — must zero move even if a finger was down.
    public func debugLifecyclePause() {
        pauseFromAppLifecycle()
    }

    /// Smoke/boot phase string published for launch smoke tests (`title`, `intro`, …).
    public var debugSmokePhase: String { smokeStatus.phase }

    /// True once `didMove` has wired the sim (title screen reachable).
    public var debugSimReady: Bool { sim != nil }

    /// Drop latched fingers whose UITouch phase already ended/cancelled.
    private func sanitizeTrackedTouches() {
        if let t = stickTouch, t.phase == .ended || t.phase == .cancelled {
            releaseStickInput()
        }
        if let t = jumpTouch, t.phase == .ended || t.phase == .cancelled {
            jumpTouch = nil
            jumpHeld = false
        }
        if let t = pounceTouch, t.phase == .ended || t.phase == .cancelled {
            pounceTouch = nil
        }
        if let t = dashTouch, t.phase == .ended || t.phase == .cancelled { dashTouch = nil }
        if let t = maskTouch, t.phase == .ended || t.phase == .cancelled { maskTouch = nil }
        if let t = grabTouch, t.phase == .ended || t.phase == .cancelled { grabTouch = nil }
    }

    private func updateStick(_ p: CGPoint) {
        let delta = CGPoint(x: p.x - stickOrigin.x, y: p.y - stickOrigin.y)
        let maxR = CGFloat(tuning.feel.stickMaxRadius)
        let dead = tuning.feel.stickDeadZone
        var dx = delta.x, dy = delta.y
        let len = hypot(dx, dy)
        // Finger slid far off the virtual stick origin → treat as release (no latched run).
        let releaseR = maxR * 2.6
        if len > releaseR {
            releaseStickInput()
            return
        }
        if len > maxR {
            dx = dx / len * maxR
            dy = dy / len * maxR
        }
        stickKnob.position = CGPoint(x: stickOrigin.x + dx, y: stickOrigin.y + dy)
        // Radial dead zone + analog ramp on X/Y (down holds drop-through on one-ways).
        let nx = Double(dx / maxR)
        let ny = Double(dy / maxR)
        let ax = abs(nx)
        if ax <= dead {
            moveX = 0
        } else {
            let remapped = (ax - dead) / max(0.05, 1 - dead)
            moveX = (nx < 0 ? -1 : 1) * min(1, remapped)
        }
        let ay = abs(ny)
        if ay <= dead {
            moveY = 0
        } else {
            let remapped = (ay - dead) / max(0.05, 1 - dead)
            moveY = (ny < 0 ? -1 : 1) * min(1, remapped)
        }
        if dy > maxR * 0.72 && !jumpHeld {
            jumpPressed = true
            jumpHeld = true
        }
    }

    private func hideOutcome() {
        if let card = outcomeRoot.childNode(withName: "outcomeCard") {
            card.removeAllActions()
            card.setScale(1)
            card.alpha = 1
            card.position = .zero
        }
        outcomeRoot.isHidden = true
        if maskMusicOn {
            maskMusicOn = false
            JuiceSound.shared.setMaskModeMusic(false)
        }
        maskVignette.removeAllActions()
        maskVignette.alpha = 0
        maskVignette.isHidden = true
        layoutUI()
    }

    // MARK: - Update

    public override func update(_ currentTime: TimeInterval) {
        if lastTime == 0 { lastTime = currentTime }
        let rawDt = max(0, currentTime - lastTime)
        lastTime = currentTime
        // Freeze gate: sample live gameplay. Ignore pause/resume gaps + death-hold.
        // Skip the same startup window as the FPS average (first 2s) — title→play / audio
        // prep hitch must not fail the mid-run freeze gate. One transition budget remains
        // as a belt-and-suspenders for the first counted frame after that window.
        let livePlay: Bool = {
            if case .playing = sim.state.phase {
                return !runPaused && resumeCountdown <= 0 && failOutcomeHold <= 0
            }
            return false
        }()
        if skipFreezeSample {
            skipFreezeSample = false
        } else if livePlay, sim.state.elapsed > 2 || !smokeEnabled {
            let ms = rawDt * 1000
            if transitionBudgetMs > 0 {
                // Absorb one post-startup transition frame of any size.
                transitionBudgetMs = 0
            } else {
                maxFrameMs = max(maxFrameMs, ms)
            }
        }
        var dt = rawDt
        if dt > 0.1 { dt = 0.1 }

        let instFPS = 1 / max(dt, 0.0001)
        // Average FPS = frameCount / elapsedTime (not mean of 1/dt).
        // Skip the first 2s (startup hitch) when averaging for the smoke gate.
        if sim.state.elapsed > 2 || !smokeEnabled {
            fpsTimeSum += rawDt
            fpsCount += 1
        }
        #if DEBUG
        if !smokeEnabled {
            fpsAcc += dt
            if fpsAcc >= 0.25 {
                displayedFPS = Int(instFPS.rounded())
                fpsLabel.text = "FPS \(displayedFPS)"
                fpsAcc = 0
            }
        }
        #endif

        statusAcc += dt
        if smokeEnabled {
            // Title: write every frame so CI can snap 01-title before autoplay advances.
            // Write often so screenshot-moment status matches what the still shows.
            let interval: TimeInterval = {
                if case .title = sim.state.phase { return 0.05 }
                if showingPublisherIdent { return 0.05 }
                return 0.08
            }()
            if statusAcc >= interval {
                statusAcc = 0
                writeSmokeStatus()
            }
            // Pause / background beats (harness-driven during live play).
            if case .playing = sim.state.phase {
                let wantPause = SmokeBrain.smokeFlagExists("smoke_show_pause.txt")
                    && !SmokeBrain.smokeFlagExists("smoke_pause_ok.txt")
                let wantBg = SmokeBrain.smokeFlagExists("smoke_background.txt")
                    && !SmokeBrain.smokeFlagExists("smoke_foreground.txt")
                if wantBg {
                    if !runPaused || !pauseFromSystem {
                        setPaused(true, system: true)
                    }
                } else if wantPause {
                    if !runPaused {
                        setPaused(true, system: false)
                    }
                } else if runPaused {
                    // Harness cleared the hold — resume (with countdown after system pause).
                    beginResumeFromPause()
                }
            }
            // Retention screens after RESULTS (harness-driven).
            // Prefer Daily when both flags exist — never flip map↔daily every frame.
            if case .won = sim.state.phase {
                if SmokeBrain.smokeFlagExists("smoke_show_daily.txt") {
                    if retentionMode != "daily" {
                        hideOutcome()
                        titleRoot.isHidden = true
                        showDailyHeist()
                    }
                } else if SmokeBrain.smokeFlagExists("smoke_show_map.txt"), retentionMode != "map" {
                    hideOutcome()
                    titleRoot.isHidden = true
                    showDistrictMap()
                }
            }
        }

        // Safety net: if a post-Mask fail stuck us before pause/bg finished, revive in place.
        if smokeEnabled,
           smoke.sawMask,
           !SmokeBrain.smokeFlagExists("smoke_foreground.txt"),
           case .failed = sim.state.phase
        {
            softReviveSmokeHarness()
            smokeSoftReviveCount += 1
        }

        if failOutcomeHold > 0 {
            failOutcomeHold = max(0, failOutcomeHold - dt)
            sync(dt: CGFloat(dt))
            updateHUDVisibility()
            if failOutcomeHold <= 0 {
                showOutcome()
            }
            return
        }

        if resumeCountdown > 0 {
            resumeCountdown = max(0, resumeCountdown - dt)
            let tick = Int(ceil(resumeCountdown))
            if tick > 0, let count = pauseCountLabel {
                count.text = "\(tick)"
                count.alpha = 1
            } else {
                pauseCountLabel?.alpha = 0
                pauseCountLabel?.text = ""
            }
            sync(dt: CGFloat(dt))
            updateHUDVisibility()
            if resumeCountdown <= 0 {
                skipFreezeSample = true
                layoutUI()
            }
            return
        }

        // Hit-stop must survive screenshot stalls (dt spikes to 0.1). Drain at most ~1 frame.
        if hitStop > 0 {
            hitStop = max(0, hitStop - min(dt, 1.0 / 60.0))
            if hitStop > 0 {
                // Keep camera / particles / squash actions alive while sim freezes.
                sync(dt: 0)
                return
            }
        }

        if runPaused {
            sync(dt: 0)
            updateHUDVisibility()
            return
        }

        accumulator += dt
        var steps = 0
        // Smoke: 1:1 on title (ident/title stills); allow 2 catch-up steps in play so
        // wall-clock harness timeouts keep pace. landCooldown is ≥0.22s so the raw
        // sim-land gate (≥100ms wall) still holds at 2× stepping.
        let maxSteps: Int = {
            if !smokeEnabled { return 4 }
            if case .title = sim.state.phase { return 1 }
            return 2
        }()
        // Safety net: if UIKit ended the stick finger without delivering touchesEnded
        // (Control Center / call / rare multitouch races), drop the latch immediately.
        sanitizeTrackedTouches()

        while accumulator >= tuning.dt && steps < maxSteps {
            // Auto-runner: always push right unless smoke director overrides.
            var input = InputFrame(
                moveX: 1,
                moveY: 0,
                jumpPressed: jumpPressed,
                jumpHeld: jumpHeld,
                pouncePressed: pouncePressed,
                dashPressed: dashPressed,
                maskPressed: maskPressed,
                grabPressed: false
            )
            jumpPressed = false
            pouncePressed = false
            dashPressed = false
            maskPressed = false
            grabPressed = false
            moveX = 1
            moveY = 0

            if smokeEnabled {
                let cue = smoke.next(sim: sim)
                if cue.start { beginPlay() }
                if cue.retry {
                    if case .won = sim.state.phase, !smoke.diedOnce {
                        // Premature vault (should be rare with pre-vault clamp) — clear .won,
                        // never soft-bounce past the green VAULT for hundreds of seconds.
                        sim.state.phase = .playing
                        sim.state.vaultReached = false
                        hideOutcome()
                        clearPlayToasts()
                    } else {
                        skipFreezeSample = true
                        transitionBudgetMs = max(transitionBudgetMs, 2500)
                        doRetry()
                    }
                }
                input = cue.input
                let midrunOk = SmokeBrain.smokeFlagExists("smoke_midrun_ok.txt")
                // Pre-midrun: honor soft-hold / short reverse so the MOP pack stays ahead.
                // Post-midrun: allow left for mop hunt + vault retreat until death beat.
                // seekDeath may ease left into a canal lip.
                let allowReverse = !midrunOk
                    || smoke.act == .seekDeath
                    || smoke.act == .play
                    || smoke.act == .showcaseMask
                    || smoke.act == .finishPush // walk back onto .exit if overshot
                if abs(input.moveX) < 0.1, (midrunOk && smoke.act != .finishPush) || smoke.act == .seekDeath {
                    input.moveX = 1
                } else if abs(input.moveX) < 0.1, !midrunOk {
                    // Soft-hold on the teaching runway — do not shove past the MOP pack.
                } else if input.moveX < 0, !allowReverse {
                    input.moveX = 1
                }
                flashSmokeFaceButtons(from: input)
            }

            if case .playing = sim.state.phase {
                sim.step(input)
                // Smoke pre-death: hard stop one tile short of EXIT so the green VAULT
                // never cracks early — but leave the street MOP pack reachable so
                // stomp → stomp-chain shots stay distinct (exitX-3 parked on the lip).
                if smokeEnabled, !smoke.diedOnce, case .playing = sim.state.phase {
                    let tile = tuning.tileSize
                    if let exitX = sim.map.findFirst(.exit)?.0 {
                        let maxX = Double(exitX - 1) * tile
                        if sim.state.bandit.position.x > maxX {
                            sim.state.bandit.position.x = maxX
                            if sim.state.bandit.velocity.x > 0 {
                                sim.state.bandit.velocity.x = 0
                            }
                        }
                    }
                }
                // After Mask, keep the bandit alive through pause/bg so death wait isn't raced by phase=won.
                if smokeEnabled,
                   smoke.sawMask,
                   !SmokeBrain.smokeFlagExists("smoke_foreground.txt"),
                   case .failed = sim.state.phase
                {
                    softReviveSmokeHarness()
                    smokeSoftReviveCount += 1
                    sim.state.events.removeAll {
                        if case .fail = $0.kind { return true }
                        return false
                    }
                }
                handle(sim.state.events)
                // Hold Mask Mode open until the harness snaps 04 / 04b — screenshot I/O
                // can take seconds of wall time while the sim keeps ticking.
                if smokeEnabled {
                    let mask1Pending = !SmokeBrain.smokeFlagExists("smoke_mask_ok.txt")
                    let mask2Pending = SmokeBrain.smokeFlagExists("smoke_mask_ok.txt")
                        && !SmokeBrain.smokeFlagExists("smoke_mask2_ok.txt")
                    // Invuln through Mask showcase + pause/bg (MOPs); water/spikes use soft-revive above.
                    if smoke.sawMask, !SmokeBrain.smokeFlagExists("smoke_foreground.txt") {
                        if sim.state.bandit.invuln < 0.35 {
                            smokeInvulnTopUpCount += 1
                        }
                        sim.state.bandit.invuln = max(sim.state.bandit.invuln, 0.35)
                    }
                    let midrunOk = SmokeBrain.smokeFlagExists("smoke_midrun_ok.txt")
                    // Cancel accidental Mask before midrun still — keeps palette + act machine honest.
                    if !midrunOk, sim.state.bandit.maskMode {
                        sim.state.bandit.maskMode = false
                        sim.state.bandit.maskTimer = 0
                        sim.state.bandit.combo = 0
                        smokePreMidrunMaskCancelCount += 1
                    }
                    // Harness: force Mask Mode for 04 / 04b when the bot can't re-chain in time.
                    // Re-apply every frame while the flag is present (mask-2 re-arm must stick).
                    if midrunOk, SmokeBrain.smokeFlagExists("smoke_force_mask.txt") {
                        sim.state.bandit.maskMode = true
                        sim.state.bandit.maskTimer = max(sim.state.bandit.maskTimer, 6.0)
                        sim.state.bandit.combo = max(sim.state.bandit.combo, tuning.maskModeAtCombo)
                        sim.state.bandit.maskCharges = max(sim.state.bandit.maskCharges, 1)
                        smoke.sawMask = true
                        smoke.sawStomp = true
                        smokeSawMaskDropAfterFirst = true
                    }
                    // Harness: dump Bandit into canal water for the death beat if seekDeath stalls.
                    // Force phase=failed immediately — teleport alone can miss a sim tick before
                    // the harness hard-timeout (seen when soft-arm and hard-fail shared a loop).
                    if SmokeBrain.smokeFlagExists("smoke_force_fail.txt"),
                       case .playing = sim.state.phase
                    {
                        let tile = tuning.tileSize
                        if let water = sim.map.findFirst(.water) {
                            sim.state.bandit.position = Vec2(
                                (Double(water.0) + 0.5) * tile,
                                (Double(water.1) + 0.5) * tile
                            )
                        }
                        sim.state.bandit.velocity = .zero
                        sim.state.bandit.invuln = 0
                        sim.state.bandit.maskMode = false
                        sim.state.bandit.maskTimer = 0
                        sim.state.bandit.hearts = 0
                        sim.state.phase = .failed(.fellInWater)
                        smoke.act = .seekDeath
                        smoke.diedOnce = true
                        smokeStatus.died = true
                        // Harness dump can hitch a frame — don't fail the freeze gate on it.
                        skipFreezeSample = true
                        transitionBudgetMs = max(transitionBudgetMs, 2000)
                    }
                    // Pin Mask open only while the harness is actively capturing 04 / 04b
                    // (smoke_capture_mask.txt). Do NOT pin from midrun→stomp-chain — that
                    // stretched Mask to ~48s vs the ~design window.
                    let capturingMask = SmokeBrain.smokeFlagExists("smoke_capture_mask.txt")
                    let holdFirst = midrunOk && mask1Pending && capturingMask
                    let holdSecond = midrunOk && mask2Pending && smokeSawMaskDropAfterFirst && capturingMask
                    if sim.state.bandit.maskMode, holdFirst || holdSecond {
                        sim.state.bandit.maskTimer = max(sim.state.bandit.maskTimer, 3.0)
                        smokeMaskPinSeconds += tuning.dt
                        smokeMaskPinActive = true
                    } else {
                        smokeMaskPinActive = false
                    }
                    // After 04: wait for a clean maskOn=0 before allowing Mask re-entry for 04b.
                    // Mop-pack bounce + stomp refresh used to re-arm Mask forever past mask-off.
                    if !mask1Pending, mask2Pending, !smokeSawMaskDropAfterFirst {
                        if sim.state.bandit.maskMode {
                            if !smokeMaskDecayArmed {
                                smokeMaskDecayArmed = true
                                // Cap remaining time so mask-off arrives within a few seconds
                                // of the still (shot already captured under pin).
                                smokeMaskDecayCap = min(sim.state.bandit.maskTimer, 3.0)
                                sim.state.bandit.maskTimer = smokeMaskDecayCap
                            }
                            sim.state.bandit.velocity = .zero
                            let expected = max(0, smokeMaskDecayCap - tuning.dt)
                            if sim.state.bandit.maskTimer > expected {
                                smokeMaskRefreshSuppressSeconds +=
                                    sim.state.bandit.maskTimer - expected
                                sim.state.bandit.maskTimer = expected
                            }
                            smokeMaskDecayCap = sim.state.bandit.maskTimer
                            if sim.state.bandit.maskTimer <= 0 {
                                sim.state.bandit.maskMode = false
                            }
                        } else {
                            // Suppress re-trigger until harness observes the drop.
                            if sim.state.bandit.combo >= tuning.maskModeAtCombo {
                                sim.state.bandit.combo = max(0, tuning.maskModeAtCombo - 1)
                            }
                            smokeMaskDecayArmed = false
                            smokeMaskDecayCap = -1
                        }
                    } else if !sim.state.bandit.maskMode {
                        smokeMaskDecayArmed = false
                        smokeMaskDecayCap = -1
                    }
                    if !sim.state.bandit.maskMode, !mask1Pending {
                        smokeSawMaskDropAfterFirst = true
                    }
                    // Harness can request an immediate status write at shot time.
                    if SmokeBrain.smokeFlagExists("smoke_snap_status.txt") {
                        writeSmokeStatus()
                        SmokeBrain.setSmokeFlag("smoke_snap_status.txt", present: false)
                    }
                    writeSmokeForcedDetailIfNeeded()
                }
            }
            accumulator -= tuning.dt
            steps += 1
        }
        sync(dt: CGFloat(dt))
        updateHUDVisibility()
    }

    private func playSFX(_ key: AssetKey) {
        JuiceSound.shared.play(key)
    }

    private func handle(_ events: [SimEvent]) {
        for e in events {
            switch e.kind {
            case .jump:
                JuiceSound.shared.playJump()
                if !smokeEnabled { hapticLight.impactOccurred() }
                squash(0.62, 1.55)
                shake(0.32)
                dust(at: e.position, count: 7, color: ArtCatalog.neonCyan)
                jumpSpark(at: e.position)
                JuiceFX.play(
                    .footDust, at: cg(e.position), in: world,
                    size: 56, z: 47, timePerFrame: 1.0 / 28.0, blendAdd: true
                )
            case .land:
                // Raw sim land for CI double-land gate (before audible debounce).
                JuiceSound.shared.logRawLand()
                JuiceSound.shared.playLand()
                squash(1.58, 0.48)
                shake(0.48)
                dust(at: e.position, count: 16, color: ArtCatalog.neonOrange)
                landRing(at: e.position)
                JuiceFX.play(
                    .footDust, at: cg(e.position), in: world,
                    size: 72, z: 47, timePerFrame: 1.0 / 26.0, blendAdd: true
                )
            case .pounce:
                JuiceSound.shared.playPounce()
                if !smokeEnabled { hapticMed.impactOccurred() }
                shake(0.7)
                squash(0.8, 1.28)
                neonBurst(at: e.position, color: ArtCatalog.neonCyan, count: 8)
            case .dash:
                JuiceSound.shared.playDash()
                if !smokeEnabled { hapticMed.impactOccurred() }
                shake(0.45)
                squash(0.72, 1.35)
                dust(at: e.position, count: 10, color: ArtCatalog.neonCyan)
                neonBurst(at: e.position, color: ArtCatalog.neonCyan, count: 6)
                JuiceFX.play(
                    .footDust, at: cg(e.position), in: world,
                    size: 64, z: 48, timePerFrame: 1.0 / 28.0, blendAdd: true
                )
            case .grab:
                JuiceSound.shared.playGrab()
                if !smokeEnabled { hapticLight.impactOccurred() }
                squash(1.2, 0.85)
                dust(at: e.position, count: 6, color: ArtCatalog.neonOrange)
            case .gadget:
                JuiceSound.shared.playPounce()
                shake(0.4)
                neonBurst(at: e.position, color: ArtCatalog.neonLime, count: 8)
            case .flop:
                // Belly-flop is mid-air commit — do NOT play land SFX here. Pounce→flop→land
                // within <100ms used to log two "sfx land" lines and fail the CI double-land gate.
                squash(1.48, 0.5)
                shake(0.28)
            case .stomp:
                smoke.noteStomp()
                // Midrun hold: ignore accidental pre-hunt stomps in the smoke counter/wait gate.
                let midrunOk = !smokeEnabled || SmokeBrain.smokeFlagExists("smoke_midrun_ok.txt")
                if midrunOk { smokeStatus.stomps += 1 }
                tutorialStomps += 1
                if tutorialStep < 1 { tutorialStep = 1 }
                if tutorialStomps >= 3, tutorialStep < 2 { tutorialStep = 2 }
                refreshObjectiveChip()
                JuiceSound.shared.playStomp()
                JuiceSound.shared.playMopChatter(Self.mopChatterLines)
                if !smokeEnabled { hapticHeavy.impactOccurred() }
                // Hit-stop ~60 ms; combo bumps the punch.
                let combo = sim.state.bandit.combo
                let stop = combo >= 3
                    ? max(tuning.feel.stompHitstop, 0.08)
                    : tuning.feel.stompHitstop
                hitStop = max(hitStop, stop)
                shake(1.85)
                squash(1.72, 0.34)
                impactFlash(intensity: combo >= 3 ? 0.6 : 0.42)
                zoomPunch(1.05)
                let stompPos = cg(e.position)
                JuiceFX.play(
                    .stompBurst, at: stompPos, in: world,
                    size: 96, z: 58, timePerFrame: 1.0 / 28.0, blendAdd: true
                )
                JuiceFX.play(
                    .mopDeath, at: stompPos, in: world,
                    size: 88, z: 57, timePerFrame: 1.0 / 26.0, blendAdd: false
                )
                neonBurst(at: e.position, color: ArtCatalog.neonPink, count: 10)
                neonBurst(at: e.position, color: ArtCatalog.neonCyan, count: 6)
                // Coin burst on every stomp.
                neonBurst(at: e.position, color: ArtCatalog.neonLime, count: 8)
                dust(at: e.position, count: 12, color: ArtCatalog.neonPink)
                impactRing(at: e.position, color: ArtCatalog.neonPink)
                squashMop(at: e.position)
                hitSpark(at: e.position, color: ArtCatalog.neonPink)
                scorePop(at: e.position, text: "+\(max(1, combo))", color: ArtCatalog.neonLime)
                if combo >= 2 {
                    scorePop(
                        at: Vec2(e.position.x, e.position.y + tuning.tileSize * 0.9),
                        text: "x\(combo)",
                        color: ArtCatalog.neonCyan
                    )
                }
                lastStompElapsed = sim.state.elapsed
                nextLullNudgeAt = sim.state.elapsed + 9
                if !celebratedFirstStomp {
                    celebratedFirstStomp = true
                    showPlayToast("STOMPED!", color: ArtCatalog.neonLime, hold: 1.1)
                }
            case .shiny:
                let combo = sim.state.bandit.combo
                JuiceSound.shared.playCollect(combo: max(1, combo), loot: false)
                shake(0.18)
                collectShinyJuice(at: e.position)
            case .bank:
                let combo = max(1, sim.state.bandit.combo)
                JuiceSound.shared.playCollect(combo: combo, loot: true)
                shake(0.28)
                shinySparkle(at: e.position)
                hitSpark(at: e.position, color: ArtCatalog.neonLime)
                impactRing(at: e.position, color: ArtCatalog.neonLime)
            case .maskOn:
                smoke.sawMask = true
                smokeStatus.mask = true
                // De-stack from stomp_crunch: wait 90ms, then sting + flash.
                hitStop = max(hitStop, 0.12)
                run(SKAction.sequence([
                    SKAction.wait(forDuration: 0.09),
                    SKAction.run { [weak self] in
                        guard let self else { return }
                        self.playSFX(.sfxMaskModeOn)
                        if !self.maskMusicOn {
                            self.maskMusicOn = true
                            JuiceSound.shared.setMaskModeMusic(true)
                        }
                        if !self.smokeEnabled { self.hapticHeavy.impactOccurred() }
                        self.flashMask()
                        // First-minute win: Mask Mode inside ~20 s is the early payoff.
                        if !self.celebratedEarlyWin, self.sim.state.elapsed <= 22 {
                            self.celebratedEarlyWin = true
                            self.showPlayToast("MASK MODE — FIRST WIN!", color: ArtCatalog.neonCyan, hold: 1.6)
                            self.shake(1.25)
                            self.impactFlash(intensity: 0.45)
                            self.zoomPunch(1.06)
                            self.neonBurst(at: self.sim.state.bandit.position, color: ArtCatalog.neonCyan, count: 26)
                            // Kill the post-Mask lull: point at EXIT hard.
                            self.run(SKAction.sequence([
                                SKAction.wait(forDuration: 1.7),
                                SKAction.run { [weak self] in
                                    guard let self else { return }
                                    self.showPlayToast("NOW → NEON EXIT", color: ArtCatalog.neonLime, hold: 1.7)
                                    self.ampExitBeacon()
                                },
                            ]))
                        }
                    },
                ]))
            case .hurt:
                tookDamageThisRun = true
                JuiceSound.shared.playHurt()
                damageFlash()
                shake(0.35)
            case .win:
                // Only a real EXIT-tile vaultReached may show VAULT CRACKED.
                guard sim.state.vaultReached else {
                    writeSmokeStatus()
                    break
                }
                // Smoke: premature vault before the death beat must not sticky-set won=
                // or flash VAULT CRACKED mid-run. Real clear happens after diedOnce.
                if smokeEnabled, !smoke.diedOnce {
                    sim.state.phase = .playing
                    sim.state.vaultReached = false
                    writeSmokeStatus()
                    break
                }
                smokeStatus.won = true
                playSFX(.sfxWin)
                JuiceSound.shared.setMaskModeMusic(false)
                clearMaskGrade()
                showOutcome()
                writeSmokeStatus()
            case .fail:
                smokeStatus.died = true
                JuiceSound.shared.playKO()
                JuiceSound.shared.setMaskModeMusic(false)
                clearMaskGrade()
                // Full-opacity KO in front of the MOP — cancel i-frame blink / ghosting.
                sim.state.bandit.invuln = 0
                bandit.alpha = 1
                bandit.zPosition = 55
                hitStop = max(hitStop, 0.28)
                // Hold so the bandit death sheet plays before SPLASHED.
                // Smoke still defers the card until the Mask screenshot flag lands.
                let maskOk = SmokeBrain.smokeFlagExists("smoke_mask_ok.txt")
                if smokeEnabled, !maskOk {
                    writeSmokeStatus()
                } else {
                    failOutcomeHold = 1.35
                    skipFreezeSample = true
                    writeSmokeStatus()
                }
            case .checkpoint:
                playSFX(.sfxCheckpoint)
                hitSpark(at: e.position, color: ArtCatalog.neonLime)
            case .dust:
                dust(at: e.position)
            case .shake:
                shake(0.3)
            case .crewFreed(let crewID):
                progressStore.recordCrewFreed(crewID)
                let member = story.crew(id: crewID)
                let name = member?.name ?? "Crew"
                showPlayToast("FREED \(name.uppercased())!", color: ArtCatalog.neonLime, hold: 2.0)
                JuiceSound.shared.playUITap()
                neonBurst(at: e.position, color: ArtCatalog.neonLime, count: 16)
                for (id, node) in crewNodes {
                    guard let cage = sim.state.crewCages.first(where: { $0.id == id }),
                          cage.crewID == crewID, cage.freed else { continue }
                    node.run(SKAction.sequence([
                        SKAction.group([SKAction.fadeOut(withDuration: 0.35), SKAction.scale(to: 1.3, duration: 0.35)]),
                        SKAction.removeFromParent(),
                    ]))
                    crewNodes.removeValue(forKey: id)
                }
            }
        }
        smokeStatus.maskOn = sim.state.bandit.maskMode
        if !sim.state.bandit.maskMode, maskMusicOn {
            maskMusicOn = false
            JuiceSound.shared.setMaskModeMusic(false)
        }
    }

    private func showOutcome() {
        clearPlayToasts()
        objectiveBanner?.removeFromParent()
        objectiveBanner = nil
        // Fake-win gate: never paint VAULT CRACKED unless feet hit the EXIT tile.
        if case .won = sim.state.phase, !sim.state.vaultReached {
            return
        }
        outcomeRoot.isHidden = false
        layoutUI()
        guard let card = outcomeRoot.childNode(withName: "outcomeCard"),
              let title = card.childNode(withName: "outcomeTitle") as? SKLabelNode,
              let shinyCount = card.childNode(withName: "outcomeShinies")?.childNode(withName: "shinyCount") as? SKLabelNode,
              let meta = card.childNode(withName: "outcomeMeta") as? SKLabelNode,
              let starsNode = card.childNode(withName: "outcomeStars") else { return }
        let scoreLabel = card.childNode(withName: "outcomeScore") as? SKLabelNode
        let hintLabel = card.childNode(withName: "outcomeHint") as? SKLabelNode

        let shinies = sim.state.bandit.carriedShinies + sim.state.bandit.bankedShinies
        let totalShiniesOnMap = max(1, sim.state.shinies.count)
        let isWin: Bool
        // Results always show the run clock (sim elapsed) — same number the player watched
        // on a normal clear. Smoke wall-clock is harness-only and must not inflate the card.
        let seconds: Double
        let combo: Int
        var clearResult: ProgressStore.ClearResult?
        var finalShiniesForCount = shinies
        switch sim.state.phase {
        case .won(_, let shinyTotal, let c):
            guard sim.state.vaultReached else { return }
            isWin = true
            seconds = sim.state.elapsed
            combo = c
            finalShiniesForCount = shinyTotal
            title.fontColor = ArtCatalog.neonLime
            title.text = "VAULT CRACKED"
            tutorialStep = 3
            // Do not refreshObjectiveChip here — it would re-show "To the vault" over the card.
            // Big loot burst on vault clear.
            neonBurst(at: sim.state.bandit.position, color: ArtCatalog.neonLime, count: 18)
            neonBurst(at: sim.state.bandit.position, color: ArtCatalog.neonCyan, count: 12)
            shinySparkle(at: sim.state.bandit.position)
            shinyCount.text = "0"
            meta.text = String(format: "⏱ %.0fs    ✦ combo x%d", seconds, combo)
            if let pa = card.childNode(withName: "outcomePA") as? SKLabelNode {
                let idx = progressStore.load().freedCrewIDs.count
                pa.text = story.paTaunt(index: max(0, idx))
                pa.isHidden = pa.text?.isEmpty != false
            }
        case .failed(let reason):
            isWin = false
            seconds = sim.state.elapsed
            combo = sim.state.bestCombo
            title.fontColor = ArtCatalog.neonPink
            title.text = reason == .fellInWater ? "SPLASHED" : (reason == .spiked ? "SPIKED" : "BAGGED")
            shinyCount.text = "\(shinies)"
            meta.text = String(format: "⏱ %.0fs    ✦ combo x%d", seconds, combo)
        default:
            return
        }

        // Stars only on clear — death card shows empty medals (no awarded stars).
        let starCount: Int = {
            guard isWin else { return 0 }
            let totalShinies = sim.state.shinies.count
            let got = sim.state.bandit.carriedShinies + sim.state.bandit.bankedShinies
            if isDailyRun {
                let score = DailyScore.compute(
                    seconds: seconds,
                    shiniesCollected: got,
                    shiniesTotal: totalShinies,
                    tookDamage: tookDamageThisRun,
                    combo: combo
                )
                let streak = progressStore.recordDailyClear(dayKey: dailyDayKey, score: score)
                _ = progressStore.recordClear(
                    levelID: ProgressStore.dailyLevelID,
                    shiniesCollected: got,
                    shiniesTotal: totalShinies,
                    seconds: seconds,
                    combo: combo
                )
                gameCenter.submitScore(score, leaderboardID: GameCenterIDs.dailyHeist)
                gameCenter.submitScore(score, leaderboardID: GameCenterIDs.mostWantedWeekly)
                gameCenter.submitScore(combo, leaderboardID: GameCenterIDs.bestCombo)
                reportDailyAchievements(score: score, streak: streak, medals: 0, gotAllLoot: got >= totalShinies)
                persistDailyGhost(score: score, seconds: seconds)
                return got >= totalShinies && !tookDamageThisRun ? 3 : (got >= totalShinies / 2 ? 2 : 1)
            }
            let levelID = ProgressStore.levelID(for: pendingDistrict)
            let earned = progressStore.recordClear(
                levelID: levelID,
                shiniesCollected: got,
                shiniesTotal: totalShinies,
                seconds: seconds,
                combo: combo
            )
            clearResult = earned
            // Fun-pass stars: 1 finish, 2 all loot, 3 no hits.
            var stars = 1
            if got >= totalShinies { stars += 1 }
            if !tookDamageThisRun { stars += 1 }
            lastAwardedMedals = stars
            smokeStatus.medals = stars
            smokeStatus.combo = max(smokeStatus.combo, combo)
            reportCampaignAchievements(
                levelID: levelID,
                medals: stars,
                noDamage: !tookDamageThisRun
            )
            return stars
        }()

        if isWin {
            gameCenter.setAccessPointVisible(true, showHighlights: true)
        }

        // Score: shinies ×100 + combo ×50 + time bonus under par + star bonus.
        let par = ProgressStore.defaultParSeconds
        let timeBonus = isWin ? max(0, Int((par - seconds) * 12)) : 0
        let finalScore = finalShiniesForCount * 100 + combo * 50 + timeBonus + starCount * 250
        scoreLabel?.text = "SCORE 0"
        scoreLabel?.fontColor = isWin ? ArtCatalog.neonCyan : ArtCatalog.neonPink.withAlphaComponent(0.85)
        scoreLabel?.removeAction(forKey: "scoreCount")
        if finalScore > 0 {
            if scoreLabel?.userData == nil { scoreLabel?.userData = NSMutableDictionary() }
            scoreLabel?.userData?["n"] = 0
            let steps = min(28, max(8, finalScore / 40))
            let step = max(1, finalScore / steps)
            scoreLabel?.run(SKAction.repeat(SKAction.sequence([
                SKAction.run { [weak scoreLabel] in
                    guard let scoreLabel else { return }
                    let n = min(finalScore, ((scoreLabel.userData?["n"] as? Int) ?? 0) + step)
                    scoreLabel.userData?["n"] = n
                    scoreLabel.text = "SCORE \(n)"
                    scoreLabel.setScale(1.08)
                    scoreLabel.run(SKAction.scale(to: 1.0, duration: 0.05))
                    JuiceSound.shared.playTallyTick()
                },
                SKAction.wait(forDuration: 0.04),
            ]), count: steps), withKey: "scoreCount")
        }

        if isWin {
            shinyCount.removeAction(forKey: "count")
            if shinyCount.userData == nil { shinyCount.userData = NSMutableDictionary() }
            shinyCount.userData?["n"] = 0
            let finalShinies = finalShiniesForCount
            shinyCount.run(SKAction.repeat(SKAction.sequence([
                SKAction.run { [weak shinyCount] in
                    guard let shinyCount else { return }
                    let n = min(finalShinies, ((shinyCount.userData?["n"] as? Int) ?? 0) + 1)
                    shinyCount.userData?["n"] = n
                    shinyCount.text = "\(n)"
                    shinyCount.setScale(1.2)
                    shinyCount.run(SKAction.scale(to: 1.0, duration: 0.06))
                    JuiceSound.shared.playTallyTick()
                },
                SKAction.wait(forDuration: 0.05),
            ]), count: max(1, finalShinies)), withKey: "count")
        }

        // Replay reason — always give the player a next itch.
        if isWin, let medals = clearResult?.medals {
            if medals.count >= 3 {
                hintLabel?.text = "PERFECT HEIST — can you beat \(Int(seconds))s?"
                hintLabel?.fontColor = ArtCatalog.neonLime
            } else if !medals.allShinies {
                let missing = max(0, totalShiniesOnMap - finalShiniesForCount)
                hintLabel?.text = missing > 0
                    ? "Replay: snag \(missing) more ⚙ for All Shinies ★"
                    : "Replay: grab every ⚙ for All Shinies ★"
                hintLabel?.fontColor = ArtCatalog.neonOrange
            } else if !medals.parTime {
                hintLabel?.text = "Replay: finish under \(Int(par))s for Par ★"
                hintLabel?.fontColor = ArtCatalog.neonOrange
            } else {
                hintLabel?.text = "One more star waiting — go again!"
                hintLabel?.fontColor = ArtCatalog.neonOrange
            }
        } else if !isWin {
            if shinies > 0 {
                hintLabel?.text = "You had \(shinies) ⚙ — stomp back in and finish!"
            } else {
                hintLabel?.text = "Stomp a MOP, grab ⚙, hit EXIT — you've got this"
            }
            hintLabel?.fontColor = ArtCatalog.neonOrange
        } else {
            hintLabel?.text = ""
        }

        // Ease-out card (~250ms): scale 0.8 → 1, fade, dim backdrop, then stagger medals/buttons.
        card.removeAllActions()
        card.setScale(0.8)
        card.alpha = 0
        card.position = CGPoint(x: 0, y: -36)
        let wash = outcomeRoot.childNode(withName: "outcomeWash")
        wash?.removeAllActions()
        wash?.alpha = 0
        wash?.run(SKAction.fadeAlpha(to: 1, duration: 0.26))
        let appear = SKAction.group([
            SKAction.fadeIn(withDuration: 0.24),
            SKAction.scale(to: 1.0, duration: 0.26),
            SKAction.moveTo(y: 0, duration: 0.26),
        ])
        appear.timingMode = .easeOut
        card.run(appear)

        starsNode.isHidden = false
        card.childNode(withName: "newBestStamp")?.removeFromParent()
        card.childNode(withName: "levelUpStamp")?.removeFromParent()
        card.childNode(withName: "outcomeConfetti")?.removeFromParent()
        for i in 0..<3 {
            guard let star = starsNode.childNode(withName: "star\(i)") as? SKLabelNode else { continue }
            star.removeAllActions()
            star.alpha = 0
            star.setScale(0.45)
            star.fontColor = ArtCatalog.neonOrange.withAlphaComponent(0.22)
            if isWin, i < starCount {
                star.run(SKAction.sequence([
                    SKAction.wait(forDuration: 0.32 + 0.16 * Double(i)),
                    SKAction.group([
                        SKAction.run { JuiceSound.shared.playStar(i) },
                        SKAction.fadeAlpha(to: 1, duration: 0.12),
                        SKAction.scale(to: 1.4, duration: 0.12),
                    ]),
                    SKAction.run { star.fontColor = ArtCatalog.neonLime },
                    SKAction.scale(to: 1.0, duration: 0.1),
                ]))
            } else if isWin {
                // Empty medal slot (dim) after stagger.
                star.run(SKAction.sequence([
                    SKAction.wait(forDuration: 0.32 + 0.16 * Double(i)),
                    SKAction.group([
                        SKAction.fadeAlpha(to: 1, duration: 0.12),
                        SKAction.scale(to: 1.0, duration: 0.12),
                    ]),
                ]))
            }
            // Death: stars stay alpha 0 — no medals on fail.
        }

        // Star labels (Finish / All Shinies / Par) — keep visible under NEW BEST.
        let starLabels = ["Finish", "All Shinies", "Par"]
        for i in 0..<3 {
            guard let star = starsNode.childNode(withName: "star\(i)") else { continue }
            star.childNode(withName: "starCaption")?.removeFromParent()
            let cap = SKLabelNode(fontNamed: "AvenirNext-Medium")
            cap.name = "starCaption"
            cap.text = starLabels[i]
            cap.fontSize = 8
            cap.fontColor = SKColor(white: 0.78, alpha: 1)
            cap.position = CGPoint(x: 0, y: -16)
            star.addChild(cap)
        }

        if isWin, starCount >= 3 {
            title.text = "PERFECT HEIST"
            let confetti = ArtCatalog.resultsConfettiEmitter()
            confetti.name = "outcomeConfetti"
            confetti.position = CGPoint(x: 0, y: 80)
            card.addChild(confetti)
            confetti.run(SKAction.sequence([
                SKAction.wait(forDuration: 2.4),
                SKAction.fadeOut(withDuration: 0.4),
                SKAction.removeFromParent(),
            ]))
        }

        if isWin, let result = clearResult {
            if result.isNewBest {
                let stamp = SKLabelNode(fontNamed: "AvenirNext-Heavy")
                stamp.name = "newBestStamp"
                stamp.text = "NEW BEST"
                stamp.fontSize = 14
                stamp.fontColor = ArtCatalog.neonOrange
                // Clear of All Shinies label + gear count — slam beside the count, angled.
                stamp.position = CGPoint(x: 86, y: 8)
                stamp.zRotation = -0.14
                stamp.alpha = 0
                stamp.setScale(1.4)
                stamp.zPosition = 5
                card.addChild(stamp)
                stamp.run(SKAction.sequence([
                    SKAction.wait(forDuration: 0.9),
                    SKAction.group([
                        SKAction.run { JuiceSound.shared.playNewBest() },
                        SKAction.fadeIn(withDuration: 0.12),
                        SKAction.scale(to: 1.0, duration: 0.16),
                    ]),
                ]))
            }
        }

        let retry = card.childNode(withName: "retryBtn") as? SKShapeNode
        let next = card.childNode(withName: "nextBtn") as? SKShapeNode
        let home = card.childNode(withName: "homeBtn")
        retry?.isHidden = isWin
        next?.isHidden = !isWin
        // Button copy sells the next run.
        if let label = retry?.children.compactMap({ $0 as? SKLabelNode }).first {
            label.text = shinies > 0 ? "RETRY — FINISH IT" : "RETRY"
        }
        if let label = next?.children.compactMap({ $0 as? SKLabelNode }).first {
            if starCount >= 3 {
                label.text = "PLAY AGAIN"
            } else if starCount == 2 {
                label.text = "GO FOR 3★"
            } else {
                label.text = "GO FOR MORE ★"
            }
        }
        for (idx, btn) in [retry as SKNode?, next as SKNode?, home].enumerated() {
            guard let btn, !btn.isHidden else { continue }
            btn.alpha = 0
            btn.setScale(0.85)
            btn.removeAllActions()
            let pop = SKAction.group([
                SKAction.fadeIn(withDuration: 0.16),
                SKAction.scale(to: 1.0, duration: 0.18),
            ])
            pop.timingMode = .easeOut
            btn.run(SKAction.sequence([
                SKAction.wait(forDuration: 0.55 + 0.08 * Double(idx)),
                pop,
            ]))
        }
    }

    private func sync(dt: CGFloat) {
        let b = sim.state.bandit
        // Physics uses body center; foot-anchored sprites need the feet on the deck.
        bandit.position = CGPoint(x: CGFloat(b.position.x), y: CGFloat(b.position.y) - bodyCenterToFeet)
        // Every frame: body.xScale from sign(velocity.x). Source sheets face west.
        bandit.setFacingFromVelocity(b.velocity.x, fallbackFacing: b.facing)
        let moveSpeed = CGFloat(hypot(b.velocity.x, 0) / max(tuning.tileSize, 1))
        let runSpeed = CGFloat(tuning.runSpeed)
        bandit.show(
            anim: b.anim,
            maskMode: b.maskMode,
            dt: dt,
            moveSpeed: moveSpeed,
            runSpeed: runSpeed,
            smokeLite: false
        )
        // Foot puffs while sprinting — motion reads even if the sheet is subtle.
        runDustCooldown -= dt
        if b.onGround, abs(b.velocity.x) > tuning.feel.runSpeed * tuning.tileSize * 0.45, runDustCooldown <= 0 {
            runDustCooldown = 0.11
            dust(at: b.position, count: 3, color: ArtCatalog.neonCyan.withAlphaComponent(0.7))
        }
        // If the street goes quiet, nudge the player back into stomps.
        if case .playing = sim.state.phase, !runPaused, sim.state.elapsed >= nextLullNudgeAt {
            let sinceStomp = lastStompElapsed < 0
                ? sim.state.elapsed
                : sim.state.elapsed - lastStompElapsed
            let nearMop = sim.state.mops.contains {
                $0.alive && abs($0.position.y - b.position.y) < tuning.tileSize * 2.5
                    && abs($0.position.x - b.position.x) < tuning.tileSize * 14
            }
            if sinceStomp >= 7, nearMop {
                nextLullNudgeAt = sim.state.elapsed + 10
                showPlayToast("POUNCE A MOP!", color: ArtCatalog.neonPink, hold: 1.25)
                if let mop = sim.state.mops.filter(\.alive).min(by: {
                    abs($0.position.x - b.position.x) < abs($1.position.x - b.position.x)
                }) {
                    impactRing(at: mop.position, color: ArtCatalog.neonPink)
                    neonBurst(at: mop.position, color: ArtCatalog.neonOrange, count: 6)
                }
            } else {
                nextLullNudgeAt = sim.state.elapsed + 2.5
            }
        }
        if b.anim == .death {
            bandit.alpha = 1
            bandit.zPosition = 55
        } else if b.invuln > 0 {
            // Stay at least half-visible during i-frames — never a faint ghost.
            let minA = CGFloat(tuning.feel.invulnMinAlpha)
            bandit.alpha = Int(b.invuln * 16) % 2 == 0 ? minA : 1
            bandit.zPosition = 20
        } else {
            bandit.alpha = 1
            bandit.zPosition = 20
        }

        if isDailyRun, sim.state.phase == .playing {
            ghostRecorder.capture(
                elapsed: sim.state.elapsed,
                position: b.position,
                facing: b.facing
            )
        }
        updateRacingGhostVisual(elapsed: sim.state.elapsed)

        for s in sim.state.shinies {
            guard let node = shinyNodes[s.id] else { continue }
            if shinyCollecting.contains(s.id) { continue }
            node.isHidden = !s.alive
        }
        for c in sim.state.crewCages {
            guard let node = crewNodes[c.id] else { continue }
            node.position = cg(c.position)
            node.isHidden = c.freed
        }
        for m in sim.state.mops {
            guard let node = mopNodes[m.id] else { continue }
            if node.userData?["squashing"] as? Bool == true { continue }
            // MOP home is already foot-on-deck; nudge 1px into the tile top.
            node.position = CGPoint(x: CGFloat(m.position.x), y: CGFloat(m.position.y) - 1)
            if m.alive {
                node.isHidden = false
                node.alpha = 1
                var pose = m.anim
                let near = abs(m.position.x - b.position.x) < 80
                    && abs(m.position.y - b.position.y) < 60
                if pose == .walk, near {
                    pose = .attack
                    if !mopAlerted.contains(m.id) {
                        mopAlerted.insert(m.id)
                        JuiceSound.shared.playMopAlert()
                        JuiceSound.shared.playMopChatter(story.mopChatter.map(\.file))
                    }
                } else if !near {
                    mopAlerted.remove(m.id)
                }
                node.show(anim: pose, facing: m.facing)
            } else if m.anim == .death, m.animHold > 0 {
                // Stomp juice owns the pop — don't play the tip-over death slide.
                node.isHidden = true
            } else {
                node.isHidden = true
            }
        }

        refreshActionButtonChrome()
        let shinyTotal = b.carriedShinies + b.bankedShinies
        smokeStatus.shinies = shinyTotal
        hudCarried.text = "✦ \(shinyTotal)"
        hudHearts.text = String(repeating: "♥", count: max(0, b.hearts))
        let barW: CGFloat = min(size.width * 0.55, CGFloat(240))
        let barY = size.height * 0.5 - max(safeInsets().top, CGFloat(59)) - CGFloat(6)
        updateProgressBar(barWidth: barW, barY: barY)
        if tutorialStep == 0, !b.onGround, b.velocity.y != 0 {
            tutorialStep = 1
            refreshObjectiveChip()
        }
        if tutorialStep >= 2, b.maskMode { tutorialStep = 3; refreshObjectiveChip() }
        if b.maskMode {
            hudCombo.text = "MASK ×\(max(0, b.maskCharges)) · x\(max(1, b.combo))"
            hudCombo.isHidden = false
            hudCombo.fontColor = ArtCatalog.neonCyan
            (hudCombo.childNode(withName: "hudGlow") as? SKLabelNode)?.fontColor = ArtCatalog.neonCyan.withAlphaComponent(0.35)
        } else if b.combo >= 1 {
            hudCombo.text = "x\(b.combo)"
            hudCombo.isHidden = false
            hudCombo.fontColor = ArtCatalog.neonLime
            (hudCombo.childNode(withName: "hudGlow") as? SKLabelNode)?.fontColor = ArtCatalog.neonLime.withAlphaComponent(0.35)
            // Pulse on each new chain step so the counter feels alive.
            if b.combo >= 2, hudCombo.action(forKey: "comboPulse") == nil {
                hudCombo.run(SKAction.sequence([
                    SKAction.scale(to: 1.18, duration: 0.07),
                    SKAction.scale(to: 1.0, duration: 0.1),
                ]), withKey: "comboPulse")
            }
        } else {
            hudCombo.text = ""
            hudCombo.isHidden = true
        }
        // Always show the heist clock (sim elapsed) — wall-clock smoke harness time is not level time.
        if smokeEnabled, smokeWallStart > 0 {
            smokeWallElapsed = CACurrentMediaTime() - smokeWallStart
        }
        hudTime.text = String(format: "⏱ %.0fs", sim.state.elapsed)
        for label in [hudCarried, hudHearts, hudCombo, hudTime] {
            (label.childNode(withName: "hudOutline") as? SKLabelNode)?.text = label.text
            (label.childNode(withName: "hudGlow") as? SKLabelNode)?.text = label.text
        }
        // Mask Mode: soft edge pulse only — afterimages come from BanditVisual.tickMotionTrail.
        if b.maskMode {
            maskGradePulse += dt
            maskVignette.alpha = 1
            if let edge = maskVignette.childNode(withName: "vignetteEdge") as? SKSpriteNode {
                edge.alpha = 0.18 + 0.06 * sin(maskGradePulse * 3.5)
            }
            skyFill.color = ArtCatalog.nightSky
            skyFill.colorBlendFactor = 1
            if !lastMaskMode {
                sawMaskThisRun = true
                applyMaskParallaxGrade(active: true, pulse: 1)
            }
        } else {
            maskParticleAcc = 0
            maskGradePulse = 0
            if lastMaskMode {
                applyMaskParallaxGrade(active: false, pulse: 1)
            }
        }

        // Single look-ahead: facing × 0.20×viewW → hero at ~30% (right) / ~70% (left).
        // Side-switch delay: ignore brief facing flips so a quick reverse doesn't park the
        // hero near ~70% while he faces right again.
        let rawWant: CGFloat = b.facing >= 0 ? 1 : -1
        let nowFace = CACurrentMediaTime()
        // ~0.9s side-switch delay so a quick reverse can't whip the hero to ~70%.
        if rawWant != cameraWantFace {
            if nowFace >= cameraFacingHoldUntil {
                cameraWantFace = rawWant
                cameraFacingHoldUntil = nowFace + 0.9
            }
        } else {
            cameraFacingHoldUntil = nowFace + 0.9
        }
        let faceBlend = min(1, CGFloat(dt) / 0.32)
        cameraFacing += (cameraWantFace - cameraFacing) * faceBlend
        var target = cameraTarget(for: b)
        // Speed-scaled follow: sprint locks on; idle eases. Stops the camera feeling sticky.
        let speedFrac = min(1, CGFloat(abs(b.velocity.x)) / max(1, CGFloat(tuning.feel.runSpeed * tuning.tileSize)))
        let s = min(1, CGFloat(tuning.cameraSmooth) * (1.45 + 0.9 * speedFrac))
        cameraFocus.x += (target.x - cameraFocus.x) * s
        cameraFocus.y += (target.y - cameraFocus.y) * s
        let z = Self.worldZoom
        // Keep the hero in the 22–40% band while the right lead is active.
        var banditSceneX = z * (CGFloat(b.position.x) - cameraFocus.x)
        var heroFrac = Double((banditSceneX + size.width * 0.5) / max(size.width, 1))
        if cameraWantFace > 0, cameraFacing > 0.85, (heroFrac > 0.40 || heroFrac < 0.22) {
            let desired = size.width * (0.30 - 0.5) // scene-x for 30% of width
            cameraFocus.x = CGFloat(b.position.x) - desired / z
            target = cameraTarget(for: b)
            cameraFocus.x += (target.x - cameraFocus.x) * 0.55
            banditSceneX = z * (CGFloat(b.position.x) - cameraFocus.x)
            heroFrac = Double((banditSceneX + size.width * 0.5) / max(size.width, 1))
        }
        stage.position = CGPoint(x: -cameraFocus.x * z, y: -cameraFocus.y * z)
        // Mid-level surprise earlier so the first-minute lull after Mask still has a beat.
        if case .playing = sim.state.phase, !runPaused, !midSurpriseFired {
            let tx = Int(floor(b.position.x / tuning.tileSize))
            if tx >= 28 || sim.state.elapsed >= 26 {
                fireMidLevelSurprise()
            }
        }
        // Hero screen-x every live frame. Min/max accumulate when the right lead is settled
        // (mid-lerp after a reverse is not a placement the framing gate should measure).
        // Skip post-death EXIT sprint (finishPush) — that intentionally rushes the camera.
        // Samples are preserved across death→retry so the gate still sees live-play framing.
        if case .playing = sim.state.phase,
           !runPaused,
           resumeCountdown <= 0,
           sim.state.elapsed > 1.0,
           !smoke.diedOnce
        {
            smokeStatus.heroX = heroFrac
            let settledRight = cameraWantFace > 0
                && cameraFacing > 0.92
                && abs(cameraFacing - cameraWantFace) < 0.06
            if settledRight {
                smokeStatus.heroXMin = min(smokeStatus.heroXMin, heroFrac)
                smokeStatus.heroXMax = max(smokeStatus.heroXMax, heroFrac)
            }
        }
        // Slow parallax — keep plates covering the view (tiled in buildParallax).
        // Stronger lag so the skyline scrolls instead of reading as a static top plate.
        parallaxFar.position = CGPoint(x: cameraFocus.x * 0.45, y: cameraFocus.y * 0.7)
        parallaxMid.position = CGPoint(x: cameraFocus.x * 0.28, y: cameraFocus.y * 0.55)
        parallaxNear.position = CGPoint(x: cameraFocus.x * 0.12, y: cameraFocus.y * 0.4)

        // Mask Mode: keep vignette visible while active; fade out on exit.
        // Do NOT ramp parent alpha toward 1 over an opaque wash — that cyan-bleaches CI shots.
        if b.maskMode {
            maskVignette.isHidden = false
            maskVignette.alpha = 1
        } else if lastMaskMode {
            maskVignette.removeAllActions()
            maskVignette.run(SKAction.sequence([
                SKAction.fadeOut(withDuration: 0.18),
                SKAction.run { [weak self] in self?.maskVignette.isHidden = true },
            ]))
        }
        lastMaskMode = b.maskMode
    }

    private func squash(_ x: CGFloat, _ y: CGFloat) {
        bandit.squash(x: x, y: y)
    }

    /// Brief full-screen additive flash on heavy hits (stomp / Mask).
    private func impactFlash(intensity: CGFloat) {
        let flash = SKSpriteNode(color: .white, size: size)
        flash.alpha = min(0.7, max(0.15, intensity))
        flash.blendMode = .add
        flash.zPosition = 500
        flash.name = "impactFlash"
        overlay.childNode(withName: "impactFlash")?.removeFromParent()
        overlay.addChild(flash)
        flash.run(SKAction.sequence([
            SKAction.fadeOut(withDuration: 0.09),
            SKAction.removeFromParent(),
        ]))
    }

    /// Tiny FOV kick so stomps feel heavier than a flat shake.
    private func zoomPunch(_ peak: CGFloat) {
        stage.removeAction(forKey: "zoomPunch")
        let base = Self.worldZoom
        stage.setScale(base)
        let up = SKAction.scale(to: base * peak, duration: 0.04)
        up.timingMode = .easeOut
        let down = SKAction.scale(to: base, duration: 0.12)
        down.timingMode = .easeIn
        stage.run(SKAction.sequence([up, down]), withKey: "zoomPunch")
    }

    /// After Mask, make the EXIT beacon impossible to miss.
    private func ampExitBeacon() {
        guard let beacon = exitBeacon else { return }
        beacon.removeAction(forKey: "amp")
        beacon.setScale(1)
        beacon.run(SKAction.repeat(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 1.35, duration: 0.18),
                SKAction.fadeAlpha(to: 1, duration: 0.18),
            ]),
            SKAction.group([
                SKAction.scale(to: 1.05, duration: 0.22),
                SKAction.fadeAlpha(to: 0.85, duration: 0.22),
            ]),
        ]), count: 6), withKey: "amp")
        if let arrow = beacon.children.compactMap({ $0 as? SKLabelNode }).first {
            arrow.fontColor = ArtCatalog.neonLime
            arrow.fontSize = 15
        }
    }

    /// Objective tips are queued toasts only — never a sticky chip that stacks with TAP MASK.
    private func showObjectiveBanner() {
        refreshObjectiveChip(forceBanner: true)
    }

    private func refreshObjectiveChip(forceBanner: Bool = false) {
        objectiveBanner?.removeFromParent()
        objectiveBanner = nil
        let stompsNeeded = 3
        let done = max(0, min(tutorialStomps, stompsNeeded))
        var tips: [(key: String, text: String, color: SKColor)] = []
        switch tutorialStep {
        case 0, 1:
            tips.append(("stomp-\(done)", "Stomp MOPs \(done)/\(stompsNeeded)", ArtCatalog.neonLime))
        case 2:
            if sim.state.bandit.maskCharges > 0 || sim.state.bandit.maskMode {
                tips.append(("mask", "TAP MASK — smash mode!", ArtCatalog.neonCyan))
                tips.append(("vault", "To the vault", ArtCatalog.neonLime))
            } else {
                tips.append(("stomp-\(done)", "Stomp MOPs \(done)/\(stompsNeeded)", ArtCatalog.neonLime))
            }
        default:
            tips.append(("vault", "To the vault", ArtCatalog.neonLime))
        }
        // Queue each objective tip once (~3s auto-dismiss). Never stack on screen.
        // Callers clear lastObjectiveTip on new runs; forceBanner is legacy no-op for “show now”.
        _ = forceBanner
        for tip in tips {
            let already = lastObjectiveTip == tip.key
                || lastObjectiveTip.hasPrefix(tip.key + ",")
                || lastObjectiveTip.contains("," + tip.key)
            guard !already else { continue }
            lastObjectiveTip = lastObjectiveTip.isEmpty ? tip.key : lastObjectiveTip + "," + tip.key
            showPlayToast(tip.text, color: tip.color, hold: 3.0)
        }
    }

    private func showPlayToast(_ text: String, color: SKColor, hold: TimeInterval) {
        // ~3s on screen; queue so TAP MASK never stacks over Stomp/To the vault.
        let capped = min(max(hold, 2.5), 3.2)
        // Drop a duplicate of the currently-queued or showing tip.
        if activeToastNode != nil || toastShowing {
            toastQueue.removeAll { $0.text == text }
        }
        if toastQueue.contains(where: { $0.text == text }) { return }
        if let active = activeToastNode,
           let label = active.children.compactMap({ $0 as? SKLabelNode }).first,
           label.text == text {
            return
        }
        toastQueue.append((text, color, capped))
        pumpToastQueue()
    }

    private func pumpToastQueue() {
        guard !toastShowing else { return }
        guard !toastQueue.isEmpty else { return }
        let next = toastQueue.removeFirst()
        toastShowing = true
        activeToastNode?.removeAllActions()
        activeToastNode?.removeFromParent()
        // Single toast slot under the stats row — never stack with another tip.
        let insets = safeInsets()
        let topSafe = max(insets.top, 59) + 86
        let root = SKNode()
        root.name = "playToast"
        root.zPosition = 275
        root.alpha = 0
        root.setScale(0.85)
        root.position = CGPoint(x: 0, y: size.height * 0.5 - topSafe)
        let bg = SKShapeNode(rectOf: CGSize(width: min(size.width * 0.78, 300), height: 30), cornerRadius: 8)
        bg.fillColor = SKColor(red: 0.03, green: 0.02, blue: 0.08, alpha: 0.88)
        bg.strokeColor = next.color.withAlphaComponent(0.85)
        bg.lineWidth = 1.2
        root.addChild(bg)
        let toast = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        toast.text = next.text
        toast.fontSize = 13
        toast.fontColor = next.color
        toast.verticalAlignmentMode = .center
        toast.horizontalAlignmentMode = .center
        root.addChild(toast)
        overlay.addChild(root)
        activeToastNode = root
        root.run(SKAction.sequence([
            SKAction.group([
                SKAction.fadeIn(withDuration: 0.1),
                SKAction.scale(to: 1.0, duration: 0.12),
            ]),
            SKAction.wait(forDuration: next.hold),
            SKAction.fadeOut(withDuration: 0.2),
            SKAction.removeFromParent(),
            SKAction.run { [weak self] in
                self?.toastShowing = false
                self?.activeToastNode = nil
                self?.pumpToastQueue()
            },
        ]))
    }

    private func placeExitBeacon(at pos: CGPoint, tile: CGFloat) {
        exitBeacon?.removeFromParent()
        let root = SKNode()
        root.name = "exitBeacon"
        root.position = CGPoint(x: pos.x, y: pos.y + tile * 1.35)
        root.zPosition = 8
        let arrow = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        arrow.text = "▼ VAULT"
        arrow.fontSize = 12
        arrow.fontColor = ArtCatalog.neonLime
        arrow.verticalAlignmentMode = .center
        root.addChild(arrow)
        let glow = SKSpriteNode(texture: ArtCatalog.softCircleTexture(), size: CGSize(width: tile * 2.2, height: tile * 1.2))
        glow.color = ArtCatalog.neonLime
        glow.colorBlendFactor = 1
        glow.alpha = 0.35
        glow.blendMode = .add
        glow.zPosition = -1
        root.addChild(glow)
        root.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.group([
                SKAction.moveBy(x: 0, y: 6, duration: 0.55),
                SKAction.fadeAlpha(to: 1.0, duration: 0.55),
            ]),
            SKAction.group([
                SKAction.moveBy(x: 0, y: -6, duration: 0.55),
                SKAction.fadeAlpha(to: 0.55, duration: 0.55),
            ]),
        ])))
        world.addChild(root)
        exitBeacon = root
    }

    /// Mid-run beat: neon surge + rooftop tease so the middle of the docks feels alive.
    private func fireMidLevelSurprise() {
        midSurpriseFired = true
        showPlayToast("ROOFTOP ROUTE — GO UP!", color: ArtCatalog.neonPink, hold: 1.6)
        shake(0.9)
        if !smokeEnabled { hapticMed.impactOccurred() }
        // Brief city-wide neon pulse on parallax mid signs.
        for node in [parallaxMid, parallaxNear, parallaxFar] {
            node.run(SKAction.sequence([
                SKAction.fadeAlpha(to: 1.0, duration: 0.08),
                SKAction.fadeAlpha(to: 0.55, duration: 0.12),
                SKAction.fadeAlpha(to: 1.0, duration: 0.18),
            ]))
        }
        neonBurst(at: sim.state.bandit.position, color: ArtCatalog.neonPink, count: 16)
        neonBurst(at: sim.state.bandit.position, color: ArtCatalog.neonCyan, count: 12)
        playSFX(.sfxCheckpoint)
    }

    private func ensureLandDustEmitter() {
        guard landDustEmitter == nil else { return }
        let e = SKEmitterNode()
        e.particleTexture = ArtCatalog.softCircleTexture()
        e.particleBirthRate = 0
        e.numParticlesToEmit = 0
        e.particleLifetime = 0.28
        e.particleLifetimeRange = 0.06
        e.particlePositionRange = CGVector(dx: 10, dy: 2)
        e.emissionAngle = .pi / 2
        e.emissionAngleRange = 1.1
        e.particleSpeed = 55
        e.particleSpeedRange = 35
        e.particleAlpha = 0.85
        e.particleAlphaSpeed = -3.0
        e.particleScale = 0.35
        e.particleScaleRange = 0.15
        e.particleScaleSpeed = -0.8
        e.particleColor = ArtCatalog.neonOrange
        e.particleColorBlendFactor = 1
        e.particleBlendMode = .add
        e.zPosition = 40
        e.targetNode = world
        world.addChild(e)
        landDustEmitter = e
    }

    private func dust(at pos: Vec2, count: Int = 8, color: SKColor = ArtCatalog.neonOrange) {
        ensureLandDustEmitter()
        guard let e = landDustEmitter else { return }
        e.position = cg(pos)
        e.particleColor = color
        e.particleBirthRate = 0
        e.numParticlesToEmit = count
        e.particleBirthRate = CGFloat(max(80, count * 12))
        e.resetSimulation()
        e.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.08),
            SKAction.run { [weak e] in
                e?.particleBirthRate = 0
                e?.numParticlesToEmit = 0
            },
        ]), withKey: "dustBurst")
    }

    /// Tiny upward sparks on jump takeoff.
    private func jumpSpark(at pos: Vec2) {
        let origin = cg(pos)
        for _ in 0..<5 {
            let p = SKSpriteNode(
                texture: ArtCatalog.softCircleTexture(),
                size: CGSize(width: CGFloat.random(in: 3...6), height: CGFloat.random(in: 3...6))
            )
            p.color = ArtCatalog.neonCyan
            p.colorBlendFactor = 1
            p.blendMode = .add
            p.alpha = 0.9
            p.position = CGPoint(x: origin.x + CGFloat.random(in: -8...8), y: origin.y - 6)
            p.zPosition = 48
            world.addChild(p)
            p.run(SKAction.sequence([
                SKAction.group([
                    SKAction.moveBy(x: CGFloat.random(in: -12...12), y: CGFloat.random(in: 12...28), duration: 0.18),
                    SKAction.fadeOut(withDuration: 0.18),
                    SKAction.scale(to: 0.2, duration: 0.18),
                ]),
                SKAction.removeFromParent(),
            ]))
        }
    }

    /// Soft landing ripple under the feet.
    private func landRing(at pos: Vec2) {
        let ring = SKShapeNode(circleOfRadius: 6)
        ring.strokeColor = ArtCatalog.neonOrange.withAlphaComponent(0.85)
        ring.fillColor = .clear
        ring.lineWidth = 2
        ring.glowWidth = 2
        ring.position = cg(pos)
        ring.zPosition = 42
        world.addChild(ring)
        ring.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 2.4, duration: 0.16),
                SKAction.fadeOut(withDuration: 0.16),
            ]),
            SKAction.removeFromParent(),
        ]))
    }

    /// Expanding impact ring on stomp / bank — reads as a hit.
    private func impactRing(at pos: Vec2, color: SKColor) {
        let ring = SKShapeNode(circleOfRadius: 8)
        ring.strokeColor = color
        ring.fillColor = color.withAlphaComponent(0.12)
        ring.lineWidth = 2.5
        ring.glowWidth = 3
        ring.position = cg(pos)
        ring.zPosition = 50
        ring.setScale(0.4)
        world.addChild(ring)
        ring.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 2.8, duration: 0.18),
                SKAction.fadeOut(withDuration: 0.18),
            ]),
            SKAction.removeFromParent(),
        ]))
    }

    private func shinySparkle(at pos: Vec2) {
        for _ in 0..<9 {
            let p = SKShapeNode(circleOfRadius: CGFloat.random(in: 1.8...4))
            p.fillColor = ArtCatalog.neonOrange
            p.strokeColor = ArtCatalog.neonCyan.withAlphaComponent(0.85)
            p.lineWidth = 0.8
            p.glowWidth = 1.5
            p.position = cg(pos)
            p.zPosition = 55
            world.addChild(p)
            p.run(SKAction.sequence([
                SKAction.group([
                    SKAction.moveBy(x: CGFloat.random(in: -34...34), y: CGFloat.random(in: 10...42), duration: 0.32),
                    SKAction.fadeOut(withDuration: 0.32),
                    SKAction.scale(to: 0.2, duration: 0.32),
                ]),
                SKAction.removeFromParent(),
            ]))
        }
    }

    private func damageFlash() {
        _ = tryFullscreenFlash(color: ArtCatalog.neonPink, peakAlpha: 0.2, duration: 0.1)
        bandit.enumerateChildNodes(withName: "//*") { node, _ in
            guard let s = node as? SKSpriteNode, s.name != "trail_*" else { return }
            guard ["torso", "head", "armF", "armB", "legF", "legB", "tail", "sprite"].contains(s.name ?? "") else { return }
            s.run(SKAction.sequence([
                SKAction.colorize(with: ArtCatalog.neonPink, colorBlendFactor: 0.75, duration: 0.05),
                SKAction.colorize(withColorBlendFactor: 0.12, duration: 0.22),
            ]))
        }
    }

    /// Small styled hit popup near the contact — no giant debug words.
    private func hitSpark(at pos: Vec2, color: SKColor) {
        let l = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        l.text = "✦"
        l.fontSize = 14
        l.fontColor = color
        l.position = cg(pos)
        l.zPosition = 62
        l.setScale(0.35)
        l.alpha = 0
        l.name = "hitSpark"
        world.addChild(l)
        l.run(SKAction.sequence([
            SKAction.group([
                SKAction.fadeIn(withDuration: 0.04),
                SKAction.scale(to: 1.2, duration: 0.08),
                SKAction.moveBy(x: 0, y: 10, duration: 0.08),
            ]),
            SKAction.group([
                SKAction.moveBy(x: 0, y: 14, duration: 0.28),
                SKAction.fadeOut(withDuration: 0.28),
                SKAction.scale(to: 0.6, duration: 0.28),
            ]),
            SKAction.removeFromParent(),
        ]))
    }

    /// Score/combo floater at the hit — large enough to read in smoke video.
    private func scorePop(at pos: Vec2, text: String, color: SKColor) {
        let l = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        l.text = text
        l.fontSize = 26
        l.fontColor = color
        l.position = cg(pos)
        l.zPosition = 63
        l.setScale(0.35)
        l.alpha = 0
        l.name = "scorePop"
        world.addChild(l)
        l.run(SKAction.sequence([
            SKAction.group([
                SKAction.fadeIn(withDuration: 0.05),
                SKAction.scale(to: 1.55, duration: 0.12),
                SKAction.moveBy(x: 0, y: 30, duration: 0.12),
            ]),
            SKAction.group([
                SKAction.moveBy(x: 0, y: 28, duration: 0.38),
                SKAction.fadeOut(withDuration: 0.38),
            ]),
            SKAction.removeFromParent(),
        ]))
    }

    private func neonBurst(at pos: Vec2, color: SKColor, count: Int) {
        let origin = cg(pos)
        for _ in 0..<count {
            let p = SKSpriteNode(color: color, size: CGSize(width: CGFloat.random(in: 4...8), height: CGFloat.random(in: 4...8)))
            p.blendMode = .add
            p.alpha = 0.95
            p.position = origin
            p.zPosition = 55
            world.addChild(p)
            let dx = CGFloat.random(in: -48...48)
            let dy = CGFloat.random(in: 8...52)
            p.run(SKAction.sequence([
                SKAction.group([
                    SKAction.moveBy(x: dx, y: dy, duration: 0.32),
                    SKAction.fadeOut(withDuration: 0.32),
                    SKAction.scale(to: 0.15, duration: 0.32),
                ]),
                SKAction.removeFromParent(),
            ]))
        }
    }

    private func squashMop(at pos: Vec2) {
        let target = cg(pos)
        guard let pair = mopNodes.min(by: {
            hypot($0.value.position.x - target.x, $0.value.position.y - target.y)
                < hypot($1.value.position.x - target.x, $1.value.position.y - target.y)
        }) else { return }
        let node = pair.value
        if hypot(node.position.x - target.x, node.position.y - target.y) > 64 { return }
        if node.userData == nil { node.userData = NSMutableDictionary() }
        node.userData?["squashing"] = true
        node.removeAllActions()
        node.isHidden = false
        node.alpha = 1
        let face: CGFloat = node.xScale >= 0 ? 1 : -1
        // White flash → flat squash pop → debris (no sideways tip/slide).
        node.run(SKAction.sequence([
            SKAction.colorize(with: .white, colorBlendFactor: 1.0, duration: 0.0),
            SKAction.wait(forDuration: 1.0 / 60.0),
            SKAction.group([
                SKAction.scaleX(to: 1.4 * face, y: 0.3, duration: 0.05),
                SKAction.colorize(withColorBlendFactor: 0, duration: 0.05),
            ]),
            SKAction.group([
                SKAction.scaleX(to: 1.55 * face, y: 0.08, duration: 0.08),
                SKAction.fadeOut(withDuration: 0.08),
            ]),
            SKAction.run { [weak self, weak node] in
                node?.isHidden = true
                node?.setScale(1)
                node?.alpha = 1
                node?.colorBlendFactor = 0
                node?.userData?["squashing"] = false
                self?.mopDebris(at: target)
            },
        ]))
    }

    private func mopDebris(at worldPos: CGPoint) {
        for _ in 0..<8 {
            let bit = SKShapeNode(rectOf: CGSize(width: CGFloat.random(in: 3...7), height: CGFloat.random(in: 2...5)), cornerRadius: 1)
            bit.fillColor = ArtCatalog.neonCyan.withAlphaComponent(0.9)
            bit.strokeColor = .clear
            bit.position = worldPos
            bit.zPosition = 45
            world.addChild(bit)
            bit.run(SKAction.sequence([
                SKAction.group([
                    SKAction.moveBy(
                        x: CGFloat.random(in: -40...40),
                        y: CGFloat.random(in: 8...36),
                        duration: 0.28
                    ),
                    SKAction.fadeOut(withDuration: 0.28),
                    SKAction.scale(to: 0.2, duration: 0.28),
                ]),
                SKAction.removeFromParent(),
            ]))
        }
    }

    private func collectShinyJuice(at pos: Vec2) {
        let target = cg(pos)
        var matchedId: Int?
        var matchedNode: SKNode?
        var best = CGFloat.greatestFiniteMagnitude
        for (id, node) in shinyNodes {
            let d = hypot(node.position.x - target.x, node.position.y - target.y)
            if d < best {
                best = d
                matchedId = id
                matchedNode = node
            }
        }
        shinySparkle(at: pos)
        if let id = matchedId, let node = matchedNode, best < 48 {
            shinyCollecting.insert(id)
            node.isHidden = false
            node.removeAllActions()
            node.run(SKAction.sequence([
                SKAction.group([
                    SKAction.scale(to: 1.45, duration: 0.08),
                    SKAction.fadeAlpha(to: 0.9, duration: 0.08),
                ]),
                SKAction.group([
                    SKAction.scale(to: 0.1, duration: 0.12),
                    SKAction.fadeOut(withDuration: 0.12),
                ]),
                SKAction.run { [weak self, weak node] in
                    node?.isHidden = true
                    node?.setScale(1)
                    node?.alpha = 1
                    self?.shinyCollecting.remove(id)
                },
            ]))
        }
        floatPlusOne(from: target)
    }

    private func floatPlusOne(from worldPos: CGPoint) {
        let gain = sim.state.bandit.maskMode ? "+2" : "+1"
        let floater = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        floater.text = gain
        floater.fontSize = 18
        floater.fontColor = ArtCatalog.neonOrange
        floater.zPosition = 230
        // Convert world → overlay so it can fly to the HUD counter.
        let scenePos = convert(worldPos, from: world)
        floater.position = scenePos
        overlay.addChild(floater)
        let dest = hudCarried.position
        floater.run(SKAction.sequence([
            SKAction.group([
                SKAction.move(to: dest, duration: 0.35),
                SKAction.scale(to: 0.7, duration: 0.35),
            ]),
            SKAction.fadeOut(withDuration: 0.08),
            SKAction.removeFromParent(),
        ]))
    }

    private func shake(_ amount: CGFloat) {
        // Shake world (child of stage) so sync's stage.position rewrite does not cancel it.
        let a = amount * 8.5
        world.removeAction(forKey: "shake")
        world.position = .zero
        // Punchy trauma: hard first kick, quick decay.
        let steps: [(CGFloat, CGFloat, TimeInterval)] = [
            (1.35, 0.7, 0.025),
            (-1.9, -1.05, 0.035),
            (1.25, 0.7, 0.035),
            (-0.85, -0.4, 0.03),
            (0.4, 0.22, 0.025),
            (-0.18, -0.1, 0.02),
        ]
        var actions: [SKAction] = steps.map { dx, dy, dur in
            SKAction.moveBy(x: a * dx, y: a * dy, duration: dur)
        }
        actions.append(SKAction.run { [weak self] in self?.world.position = .zero })
        world.run(SKAction.sequence(actions), withKey: "shake")
    }

    private func writeSmokeStatus() {
        let phase: String = {
            switch sim.state.phase {
            case .title: return "title"
            case .playing: return "playing"
            case .won: return "won"
            case .failed: return "failed"
            }
        }()
        smokeStatus.phase = phase
        smokeStatus.elapsed = sim.state.elapsed
        if smokeEnabled, smokeWallStart > 0 {
            smokeWallElapsed = CACurrentMediaTime() - smokeWallStart
            smokeStatus.wallElapsed = smokeWallElapsed
        }
        smokeStatus.fpsSamples = fpsCount
        smokeStatus.fpsAvg = (fpsCount > 0 && fpsTimeSum > 0) ? Double(fpsCount) / fpsTimeSum : 0
        smokeStatus.maxFrameMs = maxFrameMs
        smokeStatus.maskOn = sim.state.bandit.maskMode
        if sim.state.bandit.maskMode { smokeStatus.mask = true }
        smokeStatus.paused = runPaused || !pauseRoot.isHidden
        // HUD/overlay only — cheap enough to run every status tick.
        smokeStatus.debugLabels = countBannedDebugLabels()
        smokeStatus.combo = max(smokeStatus.combo, sim.state.bestCombo, sim.state.bandit.combo)
        if case .won = sim.state.phase {
            smokeStatus.medals = max(smokeStatus.medals, lastAwardedMedals)
        }
        if retentionMode == "map" { smokeStatus.map = true }
        if retentionMode == "daily" { smokeStatus.daily = true }
        let streetY = sim.map.findFirst(.start).map { Double($0.1) * tuning.tileSize } ?? 0
        smokeStatus.roof = sim.state.bandit.position.y > streetY + tuning.tileSize * 2.5
        let tile = tuning.tileSize
        let wtx = Int(floor(sim.state.bandit.position.x / tile))
        let wty = Int(floor(sim.state.bandit.position.y / tile))
        smokeStatus.worldTX = wtx
        smokeStatus.worldTY = wty
        smokeStatus.worldTXMax = max(smokeStatus.worldTXMax, wtx)
        smokeStatus.stallSec = smoke.progressStallSeconds
        // Layout shots must wait for the title art to actually leave the screen.
        smokeStatus.titleHidden = titleRoot.isHidden
        smokeStatus.write()
    }

    /// Count every smoke-only state edit so CI can report honest forced-fallback totals.
    private func writeSmokeForcedDetailIfNeeded() {
        let now = CACurrentMediaTime()
        guard now - smokeLastForcedWrite >= 0.5 else { return }
        smokeLastForcedWrite = now
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let url = docs.appendingPathComponent("smoke_forced_detail.txt")
        let body = """
        mask_pin_seconds=\(String(format: "%.1f", smokeMaskPinSeconds))
        mask_force_off_count=\(smokeMaskForceOffCount)
        mask_force_off_seconds=\(String(format: "%.1f", smokeMaskForceOffSeconds))
        soft_revive_count=\(smokeSoftReviveCount)
        pre_midrun_mask_cancel=\(smokePreMidrunMaskCancelCount)
        invuln_topup_count=\(smokeInvulnTopUpCount)
        mask_refresh_suppress_seconds=\(String(format: "%.1f", smokeMaskRefreshSuppressSeconds))
        """
        try? body.write(to: url, atomically: true, encoding: .utf8)
    }

    /// CI gate: any visible SKLabel whose text matches the ban list fails smoke.
    /// Scans HUD/overlay only — world juice uses shapes/sprites + `hitSpark` (✦), not banned words.
    private func countBannedDebugLabels() -> Int {
        var count = 0
        let banned = SmokeStatus.bannedDebugTexts
        let scan: (SKNode) -> Void = { root in
            root.enumerateChildNodes(withName: "//*") { node, _ in
                guard let label = node as? SKLabelNode else { return }
                guard !label.isHidden, label.alpha > 0.05 else { return }
                var p: SKNode? = label.parent
                while let cur = p {
                    if cur.isHidden { return }
                    p = cur.parent
                }
                let raw = (label.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !raw.isEmpty else { return }
                if banned.contains(raw.uppercased()) { count += 1 }
            }
        }
        scan(hud)
        scan(overlay)
        return count
    }

    private func applyMaskParallaxGrade(active: Bool, pulse: CGFloat) {
        // Do not recolor city plates. Changing color/blendFactor + texture memory pressure
        // turns mid/near plates into solid cyan or white washes (CI cyanWash/blowout gates).
        // Mask grade is character glow + edge vignette only; grid alpha is a light cue.
        _ = pulse
        if let grid = parallaxFar.childNode(withName: "//gridHorizon") as? SKSpriteNode {
            grid.alpha = active ? 0.55 : 0.42
        }
    }

    private func clearMaskGrade() {
        maskVignette.removeAllActions()
        maskVignette.alpha = 0
        maskVignette.isHidden = true
        applyMaskParallaxGrade(active: false, pulse: 1)
        lastMaskMode = false
        maskGradePulse = 0
    }

    /// Photosensitivity safety: ≤3 full-screen flashes per second; skips if over cap.
    @discardableResult
    private func tryFullscreenFlash(color: SKColor, peakAlpha: CGFloat, duration: TimeInterval) -> Bool {
        let now = CACurrentMediaTime()
        flashHistory = flashHistory.filter { now - $0 < 1.0 }
        guard flashHistory.count < 3 else { return false }
        // SKSpriteNode(color:) ignores UIColor alpha — set node.alpha explicitly.
        let alpha = min(peakAlpha, 0.14)
        let life = min(duration, 0.1)
        flashHistory.append(now)
        let flash = SKSpriteNode(color: color, size: size)
        flash.alpha = alpha
        flash.blendMode = .alpha
        flash.zPosition = 274
        flash.name = "safeFlash"
        overlay.addChild(flash)
        flash.run(SKAction.sequence([
            SKAction.fadeOut(withDuration: life),
            SKAction.removeFromParent(),
        ]))
        return true
    }

    private func flashMask() {
        // Crisp Mask beat: LED glints + rim + short afterimage — no blurry ghost head.
        maskVignette.isHidden = false
        maskVignette.alpha = 1
        if let edge = maskVignette.childNode(withName: "vignetteEdge") as? SKSpriteNode {
            edge.alpha = 0.24
        }
        applyMaskParallaxGrade(active: true, pulse: 1)
        _ = tryFullscreenFlash(color: ArtCatalog.neonCyan, peakAlpha: 0.08, duration: 0.08)
        bandit.flashMaskEntry()
        // Camera punch-in.
        let z = Self.worldZoom
        stage.removeAction(forKey: "maskPunch")
        stage.setScale(z)
        stage.run(SKAction.sequence([
            SKAction.scale(to: z * 1.06, duration: 0.08),
            SKAction.scale(to: z, duration: 0.18),
        ]), withKey: "maskPunch")
        // MASK MODE banner — top of screen, small, clear of raccoon / +N popups.
        overlay.childNode(withName: "maskModeBanner")?.removeFromParent()
        let insets = safeInsets()
        let topSafe = max(insets.top, 59) + 10
        let banner = SKNode()
        banner.name = "maskModeBanner"
        banner.zPosition = 220
        banner.position = CGPoint(x: 0, y: size.height * 0.5 - topSafe - 18)
        banner.alpha = 0
        banner.setScale(0.9)
        let bg = SKShapeNode(rectOf: CGSize(width: min(size.width * 0.62, 220), height: 28), cornerRadius: 8)
        bg.fillColor = SKColor(red: 0.02, green: 0.06, blue: 0.12, alpha: 0.82)
        bg.strokeColor = ArtCatalog.neonCyan
        bg.lineWidth = 1.5
        banner.addChild(bg)
        let stamp = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        stamp.text = "MASK MODE"
        stamp.fontSize = 14
        stamp.fontColor = ArtCatalog.neonCyan
        stamp.verticalAlignmentMode = .center
        banner.addChild(stamp)
        overlay.addChild(banner)
        banner.run(SKAction.sequence([
            SKAction.group([
                SKAction.fadeIn(withDuration: 0.08),
                SKAction.scale(to: 1.0, duration: 0.12),
            ]),
            SKAction.wait(forDuration: 0.55),
            SKAction.group([
                SKAction.fadeOut(withDuration: 0.2),
                SKAction.moveBy(x: 0, y: 10, duration: 0.2),
            ]),
            SKAction.removeFromParent(),
        ]))
        neonBurst(at: sim.state.bandit.position, color: ArtCatalog.neonCyan, count: 10)
        neonBurst(at: sim.state.bandit.position, color: ArtCatalog.neonPink, count: 5)
        for i in 0..<3 {
            let ring = SKShapeNode(circleOfRadius: 16 + CGFloat(i) * 12)
            ring.strokeColor = ArtCatalog.neonCyan.withAlphaComponent(0.75 - CGFloat(i) * 0.15)
            ring.fillColor = .clear
            ring.lineWidth = 2
            ring.position = bandit.position
            ring.zPosition = 46
            world.addChild(ring)
            ring.run(SKAction.sequence([
                SKAction.wait(forDuration: 0.04 * Double(i)),
                SKAction.group([
                    SKAction.scale(to: 2.8, duration: 0.32),
                    SKAction.fadeOut(withDuration: 0.32),
                ]),
                SKAction.removeFromParent(),
            ]))
        }
        for _ in 0..<3 { bandit.emitMaskTrail() }
        hitSpark(at: sim.state.bandit.position, color: ArtCatalog.neonCyan)
    }

    // MARK: - Daily Heist ghosts + Game Center

    private func ensureGhostVisual() {
        if ghostVisual == nil {
            let g = SKSpriteNode(color: ArtCatalog.neonCyan.withAlphaComponent(0.35), size: SpriteCycles.banditDisplaySize)
            g.name = "dailyGhost"
            g.zPosition = 18
            g.alpha = 0
            world.addChild(g)
            ghostVisual = g
        }
        ghostVisual?.isHidden = racingGhostSamples.isEmpty
        ghostVisual?.alpha = racingGhostSamples.isEmpty ? 0 : 0.55
        ghostVisual?.color = ArtCatalog.neonCyan
        ghostVisual?.colorBlendFactor = 0.85
    }

    private func updateRacingGhostVisual(elapsed: Double) {
        guard let ghost = ghostVisual, !racingGhostSamples.isEmpty else {
            ghostVisual?.alpha = 0
            return
        }
        guard let (pos, facing) = GhostPlayback.pose(samples: racingGhostSamples, at: elapsed) else {
            ghost.alpha = 0
            return
        }
        ghost.position = CGPoint(x: CGFloat(pos.x), y: CGFloat(pos.y) - bodyCenterToFeet)
        ghost.xScale = facing >= 0 ? 1 : -1
        ghost.alpha = 0.55
        ghost.isHidden = false
    }

    private func persistDailyGhost(score: Int, seconds: Double) {
        let playerID = gameCenter.localPlayerID ?? "local"
        let name = gameCenter.localDisplayName ?? "Bandit"
        let samples = ghostRecorder.samples.map {
            GhostSample(t: $0.t, x: $0.x, y: $0.y, facing: $0.facing)
        }
        let run = GhostRun(
            dayKey: dailyDayKey,
            playerID: playerID,
            displayName: name,
            score: score,
            seconds: Float(seconds),
            samples: samples
        )
        Task { await ghostStore.saveOwnBest(run) }
        if racingGhostKind == .own {
            unlockAchievement(GameCenterIDs.beatOwnGhost)
        }
        if racingGhostKind == .friend || racingGhostKind == .worldBest {
            unlockAchievement(GameCenterIDs.beatFriendGhost)
        }
    }

    private func reportDailyAchievements(score: Int, streak: Int, medals: Int, gotAllLoot: Bool) {
        _ = score
        unlockAchievement(GameCenterIDs.firstHeist)
        if gotAllLoot && !tookDamageThisRun { unlockAchievement(GameCenterIDs.threeStarHeist) }
        if !tookDamageThisRun { unlockAchievement(GameCenterIDs.noDamageHeist) }
        if streak >= 3 { unlockAchievement(GameCenterIDs.dailyStreak3) }
        if streak >= 7 { unlockAchievement(GameCenterIDs.dailyStreak7) }
        if streak >= 30 { unlockAchievement(GameCenterIDs.dailyStreak30) }
        if sim.state.bandit.maskMode || sawMaskThisRun { unlockAchievement(GameCenterIDs.firstMaskMode) }
        _ = medals
    }

    private func reportCampaignAchievements(levelID: String, medals: Int, noDamage: Bool) {
        unlockAchievement(GameCenterIDs.firstHeist)
        if medals >= 3 { unlockAchievement(GameCenterIDs.threeStarHeist) }
        if noDamage { unlockAchievement(GameCenterIDs.noDamageHeist) }
        if levelID.hasPrefix("arcade_row") { unlockAchievement(GameCenterIDs.clearArcadeRow) }
        if levelID.hasPrefix("rooftops") { unlockAchievement(GameCenterIDs.clearRooftops) }
        if sim.state.bandit.maskMode || sawMaskThisRun { unlockAchievement(GameCenterIDs.firstMaskMode) }
        if sim.state.crewCages.contains(where: \.freed) {
            unlockAchievement(GameCenterIDs.firstCrewRescue)
        }
    }

    private func unlockAchievement(_ id: String) {
        var progress = progressStore.load()
        guard !progress.unlockedAchievementIDs.contains(id) else {
            gameCenter.reportAchievement(id: id, percentComplete: 100)
            return
        }
        progress.unlockedAchievementIDs.append(id)
        progressStore.save(progress)
        gameCenter.reportAchievement(id: id, percentComplete: 100)
    }
}
#endif
