// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

#if canImport(SpriteKit) && canImport(UIKit)
import GameCore
import ImageIO
import SpriteKit
import UIKit

@MainActor
public enum ArtCatalog {
    /// Bright magenta / teal neon night — Game Plan v1 “bright neon on dark”.
    public static let nightSky = SKColor(red: 0.08, green: 0.05, blue: 0.20, alpha: 1)
    public static let neonPink = SKColor(red: 1.0, green: 0.28, blue: 0.72, alpha: 1)
    public static let neonCyan = SKColor(red: 0.25, green: 0.98, blue: 1.0, alpha: 1)
    public static let neonLime = SKColor(red: 0.62, green: 1.0, blue: 0.42, alpha: 1)
    public static let neonOrange = SKColor(red: 1.0, green: 0.62, blue: 0.22, alpha: 1)
    public static let asphalt = SKColor(red: 0.28, green: 0.22, blue: 0.38, alpha: 1)
    public static let dockFill = SKColor(red: 0.09, green: 0.07, blue: 0.18, alpha: 1)

    private static var textureCache: [AssetKey: SKTexture] = [:]
    private static var tileCache: [Int: SKTexture] = [:]
    private static var sideMaskCache: [Int: SKTexture] = [:]
    private static var sidePropCache: [Int: SKTexture] = [:]
    private static var spriteAtlas: SKTextureAtlas?
    private static var tileAtlas: SKTextureAtlas?
    private static var didWarm = false
    private static var perspectiveGridTex: SKTexture?
    private static var trailSpeckTex: SKTexture?

    /// Warm atlases once — batches GPU uploads for raccoon / MOP / shiny / tiles.
    /// Platform tiles get a baked neon-grid + edge pass (no runtime shaders / SKEffectNode).
    public static func warmAtlases() {
        guard !didWarm else { return }
        didWarm = true
        var spriteDict: [String: UIImage] = [:]
        for key in AssetManifest.runCycle + AssetManifest.shinyFrames + [
            .raccoonIdle, .raccoonJump, .raccoonFall, .raccoonPounce, .raccoonBellyFlop, .raccoonMaskMode,
            .raccoonRigHead, .raccoonRigTorso, .raccoonRigArm, .raccoonRigLeg, .raccoonRigTail,
            .mopIdle, .mopPatrol, .mopAlert, .logo,
        ] {
            if let img = AssetManifest.image(for: key, preferScale: 2) {
                spriteDict[key.rawValue.replacingOccurrences(of: "/", with: "_")] = img
            }
        }
        if !spriteDict.isEmpty {
            spriteAtlas = SKTextureAtlas(dictionary: spriteDict)
        }
        var tileDict: [String: UIImage] = [:]
        for i in 1...27 {
            if let img = loadTileImage(index: i) {
                // Legacy prop sheets only — ground uses tiles_side autotiles (no outline bake).
                let baked = bakeNeonGrid(onto: img, style: .prop)
                tileDict[String(format: "tile_%02d", i)] = baked
            }
        }
        if !tileDict.isEmpty {
            tileAtlas = SKTextureAtlas(dictionary: tileDict)
        }
        warmSideAutotiles()
        warmSideProps()
        _ = motionTrailTexture()
        _ = softCircleTexture()
        _ = perspectiveGridTexture()
        _ = loadStorefrontSignTextures()
    }

    /// Preload level textures / atlases while the title screen is up so beginPlay stays
    /// within the 250ms transition freeze budget on a real phone.
    public static func preloadGameplayTextures() {
        warmAtlases()
        var warm: [SKTexture] = []
        for key in AssetManifest.runCycle + AssetManifest.shinyFrames + [
            .raccoonIdle, .raccoonJump, .raccoonFall, .raccoonPounce, .raccoonBellyFlop, .raccoonMaskMode,
            .mopIdle, .mopPatrol, .mopAlert, .logo,
        ] {
            if let tex = texture(key) { warm.append(tex) }
        }
        for i in 1...27 {
            if let tex = tileTexture(index: i) { warm.append(tex) }
        }
        warm.append(contentsOf: sidePropTextures())
        _ = background(.farSkyline, height: 920, maxPixel: 1024)
        _ = background(.midBuildings, height: 780, maxPixel: 1100)
        _ = background(.nearRooftops, height: 720, maxPixel: 1100)
        if !warm.isEmpty {
            SKTexture.preload(warm) {}
        }
    }

    public static func texture(_ key: AssetKey) -> SKTexture? {
        if let cached = textureCache[key] { return cached }
        let atlasName = key.rawValue.replacingOccurrences(of: "/", with: "_")
        if let atlas = spriteAtlas {
            let names = atlas.textureNames
            if names.contains(atlasName) {
                let tex = atlas.textureNamed(atlasName)
                tex.filteringMode = .linear
                textureCache[key] = tex
                return tex
            }
        }
        guard let img = AssetManifest.image(for: key, preferScale: 2) else { return nil }
        let tex = SKTexture(image: img)
        tex.filteringMode = .linear
        textureCache[key] = tex
        return tex
    }

    public static func textures(_ keys: [AssetKey]) -> [SKTexture] {
        keys.compactMap { texture($0) }
    }

    /// Despill disabled at runtime — glow is baked into the PNGs (Game Plan v1).
    public static func applyDespill(_ node: SKSpriteNode) {
        node.shader = nil
    }

    public static func makeBanditVisual() -> BanditVisual {
        BanditVisual()
    }

    /// Front-facing idle for title / menu / Hideout (`idle_front` sheet).
    public static func makeBanditFrontMascot(size: CGSize = CGSize(width: 96, height: 96)) -> SKSpriteNode {
        let cycle = SpriteCycles.bandit("idle_front")
        let tex = cycle?.textures.first ?? texture(.raccoonIdle) ?? SKTexture()
        let n = SKSpriteNode(texture: tex, size: size)
        n.name = "banditFront"
        n.anchorPoint = CGPoint(x: 0.5, y: cycle?.footAnchorY ?? 0.14)
        applyDespill(n)
        if let cycle, cycle.textures.count > 1 {
            n.run(SKAction.repeatForever(
                SKAction.animate(with: cycle.textures, timePerFrame: cycle.timePerFrame)
            ), withKey: "frames")
        }
        return n
    }

    /// Rig parts cropped from the project idle sheet (see `Assets/LICENSES.md`). No third-party art.
    public static func raccoonRigParts() -> (
        head: SKTexture, torso: SKTexture, arm: SKTexture, leg: SKTexture, tail: SKTexture
    ) {
        let fallback = texture(.raccoonIdle) ?? SKTexture()
        func load(_ key: AssetKey) -> SKTexture {
            texture(key) ?? fallback
        }
        return (
            head: load(.raccoonRigHead),
            torso: load(.raccoonRigTorso),
            arm: load(.raccoonRigArm),
            leg: load(.raccoonRigLeg),
            tail: load(.raccoonRigTail)
        )
    }

    /// Prefer Spriterrific ready frames, then legacy CC-BY folders.
    public static func licensedCycleTextures(_ name: String, maxFrames: Int = 24) -> [SKTexture] {
        if let cycle = SpriteCycles.bandit(name), !cycle.textures.isEmpty {
            return Array(cycle.textures.prefix(maxFrames))
        }
        let roots = [
            "sprites/spriterrific_ready/bandit/\(name)",
            "sprites/raccoon/spriterrific/\(name)",
            "sprites/raccoon/licensed_ccby/\(name)",
        ]
        for root in roots {
            var out: [SKTexture] = []
            for i in 1...maxFrames {
                let rel = String(format: "%@/%02d", root, i)
                guard let url = AssetManifest.fileURLPublic(relative: rel, extensions: ["png"]),
                      let data = try? Data(contentsOf: url),
                      let img = UIImage(data: data) else { break }
                let tex = SKTexture(image: img)
                tex.filteringMode = .linear
                out.append(tex)
            }
            if out.count >= 2 { return out }
        }
        return []
    }

    public static func makeMopNode() -> MopVisual {
        MopVisual()
    }

    /// Lightweight idle MOP sprite for title atmosphere (not a live sim enemy).
    public static func makeMopIdleSprite(size: CGSize) -> SKSpriteNode? {
        let cycle = SpriteCycles.mopBot("walk") ?? SpriteCycles.mopBot("idle")
        guard let tex = cycle?.textures.first ?? texture(.mopIdle) else { return nil }
        let n = SKSpriteNode(texture: tex, size: size)
        n.name = "mopIdleTitle"
        n.anchorPoint = CGPoint(x: 0.5, y: 0.12)
        applyDespill(n)
        if let cycle, cycle.textures.count > 1 {
            n.run(SKAction.repeatForever(
                SKAction.animate(with: Array(cycle.textures.prefix(6)), timePerFrame: 0.14)
            ), withKey: "frames")
        }
        return n
    }

    public static func makeBossNode() -> BossVisual {
        BossVisual()
    }

    public static func makeShinyNode() -> SKNode {
        let root = SKNode()
        root.name = "shiny"
        // Prefer Higgsfield loot gem / coin; fall back to legacy shiny frames.
        let libraryTex: SKTexture? = {
            for name in ["gem", "gem-shard", "coin-magenta", "coin-gold"] {
                if let t = downsampledTexture(relative: "sprites/library/loot/\(name)", maxPixel: 128) {
                    return t
                }
            }
            return nil
        }()
        let frames = textures(AssetManifest.shinyFrames)
        let tex = libraryTex ?? frames.first
        let n = SKSpriteNode(texture: tex, size: CGSize(width: 28, height: 28))
        n.name = "shinySprite"
        applyDespill(n)
        if libraryTex == nil, frames.count > 1 {
            n.run(SKAction.repeatForever(SKAction.animate(with: frames, timePerFrame: 0.16)))
        }
        root.addChild(n)
        // Higgsfield neon glow loop (frames 2–6) — additive, behind the gear.
        JuiceFX.attachPickupGlow(to: root, size: 52)
        return root
    }

    public static func makeLogoNode(lite: Bool = false) -> SKNode {
        // Title art is path-swappable — drop a PNG at any TitleArt.logoCandidates path.
        // Callers MUST `fitTitleLogo` before pulse actions (scale(to:) is absolute).
        let maxPx: CGFloat = lite ? 768 : 1400
        let tex: SKTexture? = {
            for rel in TitleArt.logoCandidates {
                if let t = downsampledTexture(relative: rel, maxPixel: maxPx) { return t }
            }
            return texture(.logo)
        }()
        if let tex {
            let s = SKSpriteNode(texture: tex)
            s.name = "logo"
            s.setScale(1)
            return s
        }
        // Fallback label uses the working title string (still not ASC / bundle rename).
        let t = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        t.text = TitleArt.fallbackWordmark
        t.fontSize = 36
        t.fontColor = neonCyan
        t.name = "logo"
        t.numberOfLines = 2
        t.preferredMaxLayoutWidth = 360
        return t
    }

    /// Compact B1 lockup for pause / results headers.
    public static func makeCompactLogoNode(maxWidth: CGFloat = 160) -> SKNode {
        let tex: SKTexture? = {
            for rel in TitleArt.compactLogoCandidates {
                if let t = downsampledTexture(relative: rel, maxPixel: 512) { return t }
            }
            return nil
        }()
        if let tex {
            let s = SKSpriteNode(texture: tex)
            s.name = "compactLogo"
            let scale = maxWidth / max(tex.size().width, 1)
            s.setScale(scale)
            return s
        }
        let t = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        t.text = "BANDIT"
        t.fontSize = 18
        t.fontColor = neonCyan
        t.name = "compactLogo"
        return t
    }

    /// True when none of the frames pairwise intersect (title chrome non-overlap gate).
    public static func framesNonOverlapping(_ frames: [CGRect], gap: CGFloat = 2) -> Bool {
        guard frames.count >= 2 else { return true }
        for i in 0..<frames.count {
            for j in (i + 1)..<frames.count {
                if frames[i].insetBy(dx: -gap, dy: -gap).intersects(frames[j]) {
                    return false
                }
            }
        }
        return true
    }

    /// Far-parallax perspective grid horizon — dim/blurred so it never reads as walkable floor.
    public static func makePerspectiveGridHorizon(width: CGFloat, height: CGFloat) -> SKSpriteNode {
        let tex = perspectiveGridTexture()
        let n = SKSpriteNode(texture: tex, size: CGSize(width: width, height: height))
        n.name = "gridHorizon"
        n.blendMode = .add
        n.alpha = 0.12
        n.zPosition = -28
        n.color = SKColor(red: 0.2, green: 0.15, blue: 0.35, alpha: 1)
        n.colorBlendFactor = 0.55
        return n
    }

    private static var softCircleTex: SKTexture?

    /// Soft white circle for particle emitters (land dust, sparks).
    public static func softCircleTexture() -> SKTexture {
        if let softCircleTex { return softCircleTex }
        let size = CGSize(width: 16, height: 16)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 2
        let img = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            let colors = [
                UIColor.white.withAlphaComponent(1).cgColor,
                UIColor.white.withAlphaComponent(0).cgColor,
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                cg.drawRadialGradient(
                    gradient,
                    startCenter: CGPoint(x: 8, y: 8), startRadius: 0,
                    endCenter: CGPoint(x: 8, y: 8), endRadius: 8,
                    options: []
                )
            }
        }
        let tex = SKTexture(image: img)
        tex.filteringMode = .linear
        softCircleTex = tex
        return tex
    }

    public static func motionTrailTexture() -> SKTexture {
        if let trailSpeckTex { return trailSpeckTex }
        let size = CGSize(width: 16, height: 28)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 2
        let img = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            let colors = [
                UIColor(red: 0.25, green: 0.98, blue: 1.0, alpha: 0.0).cgColor,
                UIColor(red: 0.25, green: 0.98, blue: 1.0, alpha: 0.85).cgColor,
                UIColor(red: 1.0, green: 0.28, blue: 0.72, alpha: 0.55).cgColor,
                UIColor(red: 1.0, green: 0.28, blue: 0.72, alpha: 0.0).cgColor,
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.35, 0.7, 1]) {
                cg.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: size.width * 0.5, y: 0),
                    end: CGPoint(x: size.width * 0.5, y: size.height),
                    options: []
                )
            }
        }
        let tex = SKTexture(image: img)
        tex.filteringMode = .linear
        trailSpeckTex = tex
        return tex
    }

    /// Scale the title wordmark to `fraction` of scene width (default 85%). Stores `baseScale` for pulse actions.
    @discardableResult
    public static func fitTitleLogo(_ node: SKNode, sceneWidth: CGFloat, fraction: CGFloat = 0.85) -> CGFloat {
        let target = max(120, sceneWidth * fraction)
        if let sprite = node as? SKSpriteNode {
            sprite.setScale(1)
            let scale = target / max(sprite.size.width, 1)
            sprite.setScale(scale)
            if sprite.userData == nil { sprite.userData = NSMutableDictionary() }
            sprite.userData?["baseScale"] = scale
            return scale
        }
        if let label = node as? SKLabelNode {
            label.setScale(1)
            let width = max(label.frame.width, 1)
            let scale = target / width
            label.setScale(scale)
            if label.userData == nil { label.userData = NSMutableDictionary() }
            label.userData?["baseScale"] = scale
            return scale
        }
        return 1
    }

    /// True when `frame` (scene space, anchor center) sits fully inside the safe playfield.
    public static func logoFrameInsideSafeArea(
        logoFrame: CGRect,
        sceneSize: CGSize,
        topSafe: CGFloat,
        bottomSafe: CGFloat
    ) -> Bool {
        let hw = sceneSize.width * 0.5
        let hh = sceneSize.height * 0.5
        let safe = CGRect(
            x: -hw + 4,
            y: -hh + bottomSafe + 4,
            width: sceneSize.width - 8,
            height: sceneSize.height - topSafe - bottomSafe - 8
        )
        return safe.contains(logoFrame)
    }

    /// Backgrounds: ImageIO thumbnail decode to ≤ maxPixel (never upload 2560 masters).
    public static func background(_ key: AssetKey, height: CGFloat, maxPixel: CGFloat = 1280) -> SKSpriteNode? {
        let rel = AssetManifest.relativePath(for: key)
        guard let tex = downsampledTexture(relative: rel, maxPixel: maxPixel) else { return nil }
        let aspect = tex.size().width / max(tex.size().height, 1)
        let h = min(height, 780)
        let n = SKSpriteNode(texture: tex, size: CGSize(width: h * aspect, height: h))
        n.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        // Brighten toward Game Plan magenta/teal neon read.
        n.color = SKColor(red: 1.15, green: 0.95, blue: 1.2, alpha: 1)
        n.colorBlendFactor = 0.18
        return n
    }

    public static func tileTexture(index: Int) -> SKTexture? {
        if let cached = tileCache[index] { return cached }
        let name = String(format: "tile_%02d", index)
        if let atlas = tileAtlas, atlas.textureNames.contains(name) {
            let tex = atlas.textureNamed(name)
            tex.filteringMode = .nearest
            tileCache[index] = tex
            return tex
        }
        guard let img = loadTileImage(index: index) else { return nil }
        let tex = SKTexture(image: img)
        tex.filteringMode = .nearest
        tileCache[index] = tex
        return tex
    }

    public static func allTileTextures() -> [SKTexture] {
        (1...27).compactMap { tileTexture(index: $0) }
    }

    /// 16-mask side-view ground autotile set.
    /// Bits: N=1 E=2 S=4 W=8 (solid neighbour present).
    /// Uses a **clean** dark fill + bright top lip so busy district crate art never
    /// walls the playfield — gameplay sprites stay the highest-contrast layer.
    public static func makePlatformTileSet(
        tileSize: CGSize,
        district: DistrictID? = nil
    ) -> SKTileSet {
        _ = district // reserved for future lip tint per district
        warmSideAutotiles()
        var groups: [SKTileGroup] = []
        groups.reserveCapacity(16)
        for mask in 0..<16 {
            // Prefer clean plate for solids; side autotiles only for thin edge cases.
            let isSolidFill = mask == 15 || mask == 14 || mask == 13 || mask == 11 || mask == 7 || mask == 0
            let tex: SKTexture
            if isSolidFill {
                tex = cleanPlatformTexture(tileSize: tileSize, mask: mask)
            } else {
                tex = sideAutotileTexture(mask: mask)
                    ?? cleanPlatformTexture(tileSize: tileSize, mask: mask)
            }
            let def = SKTileDefinition(texture: tex, size: tileSize)
            def.name = String(format: "side_mask_%02d", mask)
            let group = SKTileGroup(tileDefinition: def)
            group.name = def.name
            groups.append(group)
        }
        return SKTileSet(tileGroups: groups)
    }

    /// Solid filled top + bright lit edge. Interior fills stay matte so BG never reads as floor.
    private static var cleanPlateCache: [Int: SKTexture] = [:]

    public static func cleanPlatformTexture(tileSize: CGSize, mask: Int) -> SKTexture {
        // Bump cache key when look changes so CI/simulators don't keep stale plates.
        let key = (mask & 0x1F) | 0x100
        if let cached = cleanPlateCache[key] { return cached }
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 2
        let img = UIGraphicsImageRenderer(size: tileSize, format: format).image { ctx in
            let cg = ctx.cgContext
            let w = tileSize.width
            let h = tileSize.height
            // Opaque slate fill — reads as real ground, not a neon grid plate.
            cg.setFillColor(UIColor(red: 0.10, green: 0.09, blue: 0.16, alpha: 1).cgColor)
            cg.fill(CGRect(origin: .zero, size: tileSize))
            cg.setFillColor(UIColor(red: 0.14, green: 0.13, blue: 0.22, alpha: 1).cgColor)
            cg.fill(CGRect(x: 1, y: 1, width: w - 2, height: h - 2))
            // Always paint a bright walkable top edge on exposed tops.
            let openTop = (mask & 1) == 0
            if openTop || mask == 15 || mask == 14 || mask == 13 || mask == 11 || mask == 7 || mask == 0 {
                // Soft under-glow
                cg.setFillColor(UIColor(red: 1.0, green: 0.35, blue: 0.75, alpha: 0.45).cgColor)
                cg.fill(CGRect(x: 0, y: h - 7, width: w, height: 3))
                // Hot lit lip
                cg.setFillColor(UIColor(red: 0.55, green: 1.0, blue: 0.95, alpha: 1).cgColor)
                cg.fill(CGRect(x: 0, y: h - 5, width: w, height: 5))
                cg.setFillColor(UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.85).cgColor)
                cg.fill(CGRect(x: 0, y: h - 2, width: w, height: 2))
            }
            // Soft side seam when open east/west.
            if (mask & 2) == 0 {
                cg.setFillColor(UIColor(red: 0.22, green: 0.20, blue: 0.32, alpha: 1).cgColor)
                cg.fill(CGRect(x: w - 2, y: 0, width: 2, height: h))
            }
            if (mask & 8) == 0 {
                cg.setFillColor(UIColor(red: 0.22, green: 0.20, blue: 0.32, alpha: 1).cgColor)
                cg.fill(CGRect(x: 0, y: 0, width: 2, height: h))
            }
        }
        let tex = SKTexture(image: img)
        tex.filteringMode = .nearest
        cleanPlateCache[key] = tex
        return tex
    }

    public static func sideAutotileTexture(mask: Int) -> SKTexture? {
        let m = max(0, min(15, mask))
        if let cached = sideMaskCache[m] { return cached }
        warmSideAutotiles()
        return sideMaskCache[m]
    }

    /// Kenney Industrial CC0 props for decoration only (crates / pipes).
    public static func sidePropTexture(index: Int) -> SKTexture? {
        if let cached = sidePropCache[index] { return cached }
        warmSideProps()
        return sidePropCache[index]
    }

    public static func sidePropTextures() -> [SKTexture] {
        warmSideProps()
        return sidePropCache.keys.sorted().compactMap { sidePropCache[$0] }
    }

    private static func warmSideAutotiles() {
        if sideMaskCache.count >= 16 { return }
        for mask in 0..<16 {
            let name = String(format: "mask_%02d", mask)
            let rel = "sprites/tiles_side/\(name)"
            guard let url = AssetManifest.fileURLPublic(relative: rel, extensions: ["png"]),
                  let img = downsampledUIImage(url: url, maxPixel: 128) else { continue }
            let tex = SKTexture(image: img)
            tex.filteringMode = .nearest
            sideMaskCache[mask] = tex
        }
    }

    private static func warmSideProps() {
        if !sidePropCache.isEmpty { return }
        for i in 20...59 {
            let name = String(format: "prop_%03d", i)
            let rel = "sprites/props_side/\(name)"
            guard let url = AssetManifest.fileURLPublic(relative: rel, extensions: ["png"]),
                  let img = downsampledUIImage(url: url, maxPixel: 128) else { continue }
            let tex = SKTexture(image: img)
            tex.filteringMode = .nearest
            sidePropCache[i] = tex
        }
    }

    private static func solidFallbackTexture(tileSize: CGSize) -> SKTexture {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 2
        let img = UIGraphicsImageRenderer(size: tileSize, format: format).image { ctx in
            let cg = ctx.cgContext
            let w = tileSize.width
            let h = tileSize.height
            // Neon dock plate — not a flat grey placeholder.
            cg.setFillColor(UIColor(red: 0.08, green: 0.07, blue: 0.16, alpha: 1).cgColor)
            cg.fill(CGRect(origin: .zero, size: tileSize))
            cg.setFillColor(UIColor(red: 0.14, green: 0.12, blue: 0.24, alpha: 1).cgColor)
            cg.fill(CGRect(x: 1, y: 1, width: w - 2, height: h - 2))
            // Magenta edge + teal top lip.
            cg.setStrokeColor(UIColor(red: 1.0, green: 0.28, blue: 0.72, alpha: 0.55).cgColor)
            cg.setLineWidth(1)
            cg.stroke(CGRect(x: 0.5, y: 0.5, width: w - 1, height: h - 1))
            cg.setFillColor(UIColor(red: 0.25, green: 0.98, blue: 1.0, alpha: 0.9).cgColor)
            cg.fill(CGRect(x: 0, y: h - 3.5, width: w, height: 3.5))
            // Rivet dots.
            cg.setFillColor(UIColor(red: 0.55, green: 0.9, blue: 1.0, alpha: 0.45).cgColor)
            for (x, y) in [(4.0, 6.0), (w - 4, 6.0), (4.0, h - 8), (w - 4, h - 8)] {
                cg.fillEllipse(in: CGRect(x: x - 1.2, y: y - 1.2, width: 2.4, height: 2.4))
            }
        }
        let tex = SKTexture(image: img)
        tex.filteringMode = .nearest
        return tex
    }

    public static func rainEmitter(sceneSize: CGSize) -> SKEmitterNode {
        let e = SKEmitterNode()
        // Keep rain readable without crushing simulator FPS (smoke gate ≥55).
        e.particleBirthRate = 28
        e.numParticlesToEmit = 0
        e.particleLifetime = 0.95
        e.particleSize = CGSize(width: 1.5, height: 9)
        e.particleColor = neonCyan.withAlphaComponent(0.5)
        e.particleColorBlendFactor = 1
        e.particleAlpha = 0.55
        e.particleAlphaRange = 0.25
        e.particleSpeed = 280
        e.particleSpeedRange = 70
        e.emissionAngle = -.pi / 2 - 0.25
        e.emissionAngleRange = 0.08
        e.particleRotation = -.pi / 2 - 0.25
        e.position = CGPoint(x: 0, y: sceneSize.height * 0.55)
        e.particlePositionRange = CGVector(dx: sceneSize.width * 1.1, dy: 16)
        e.zPosition = 70
        return e
    }

    /// Twinkling apartment windows on the far skyline (original procedural).
    public static func livingWindowLights(width: CGFloat, height: CGFloat) -> SKNode {
        let root = SKNode()
        root.name = "livingWindows"
        let cols = max(8, Int(width / 70))
        let rows = 4
        for c in 0..<cols {
            for r in 0..<rows {
                if (c + r) % 3 == 0 { continue }
                let w = SKSpriteNode(
                    color: (c + r) % 2 == 0 ? neonCyan : neonOrange,
                    size: CGSize(width: 3.5, height: 4.5)
                )
                w.alpha = CGFloat.random(in: 0.25...0.7)
                w.blendMode = .add
                w.position = CGPoint(
                    x: -width * 0.42 + CGFloat(c) * (width * 0.84 / CGFloat(max(cols - 1, 1))),
                    y: -height * 0.08 + CGFloat(r) * (height * 0.18)
                )
                w.zPosition = 1
                root.addChild(w)
                w.run(SKAction.repeatForever(SKAction.sequence([
                    SKAction.wait(forDuration: Double.random(in: 0.4...2.8)),
                    SKAction.fadeAlpha(to: CGFloat.random(in: 0.15...0.95), duration: 0.12),
                    SKAction.wait(forDuration: Double.random(in: 0.6...3.5)),
                    SKAction.fadeAlpha(to: CGFloat.random(in: 0.2...0.55), duration: 0.18),
                ])))
            }
        }
        return root
    }

    /// Soft street steam drifting up from vents (original procedural).
    public static func streetSteamEmitter(width: CGFloat) -> SKEmitterNode {
        let e = SKEmitterNode()
        e.name = "streetSteam"
        e.particleTexture = softCircleTexture()
        e.particleBirthRate = 6
        e.numParticlesToEmit = 0
        e.particleLifetime = 2.2
        e.particleLifetimeRange = 0.6
        e.particleSize = CGSize(width: 18, height: 18)
        e.particleScale = 0.55
        e.particleScaleRange = 0.35
        e.particleScaleSpeed = 0.35
        e.particleAlpha = 0.22
        e.particleAlphaSpeed = -0.1
        e.particleColor = SKColor(white: 0.75, alpha: 1)
        e.particleColorBlendFactor = 1
        e.particleBlendMode = .add
        e.particleSpeed = 22
        e.particleSpeedRange = 10
        e.emissionAngle = .pi / 2
        e.emissionAngleRange = 0.35
        e.particlePositionRange = CGVector(dx: width * 0.55, dy: 4)
        e.zPosition = 3
        return e
    }

    /// Slow silhouette transit on the far skyline (original procedural — no external art).
    public static func skylineTransit(width: CGFloat, y: CGFloat) -> SKNode {
        let root = SKNode()
        root.name = "skylineTransit"
        root.zPosition = -28
        let car = SKShapeNode(rectOf: CGSize(width: 28, height: 8), cornerRadius: 2)
        car.fillColor = SKColor(red: 0.05, green: 0.08, blue: 0.14, alpha: 0.85)
        car.strokeColor = neonCyan.withAlphaComponent(0.35)
        car.lineWidth = 0.8
        car.position = CGPoint(x: -width * 0.4, y: y)
        root.addChild(car)
        let light = SKSpriteNode(color: neonOrange, size: CGSize(width: 4, height: 3))
        light.alpha = 0.7
        light.blendMode = .add
        light.position = CGPoint(x: 12, y: 0)
        car.addChild(light)
        let span = width * 0.95
        car.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x: span, y: 0, duration: 18),
            SKAction.run { car.position.x = -width * 0.45 },
            SKAction.wait(forDuration: 2.5),
        ])))
        return root
    }

    /// Diagonal neon searchlight sweep across the mid band (original procedural).
    public static func neonSearchlight(height: CGFloat) -> SKNode {
        let root = SKNode()
        root.name = "neonSearchlight"
        let beam = SKSpriteNode(color: neonCyan.withAlphaComponent(0.08), size: CGSize(width: 36, height: height * 0.7))
        beam.blendMode = .add
        beam.zRotation = -0.35
        beam.alpha = 0.55
        root.addChild(beam)
        beam.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.group([
                SKAction.fadeAlpha(to: 0.85, duration: 1.4),
                SKAction.rotate(byAngle: 0.25, duration: 1.4),
            ]),
            SKAction.group([
                SKAction.fadeAlpha(to: 0.25, duration: 1.6),
                SKAction.rotate(byAngle: -0.25, duration: 1.6),
            ]),
        ])))
        return root
    }

    /// Short confetti burst for a perfect (3★) results card — original procedural.
    public static func resultsConfettiEmitter() -> SKEmitterNode {
        let e = SKEmitterNode()
        e.particleTexture = softCircleTexture()
        e.particleBirthRate = 90
        e.numParticlesToEmit = 48
        e.particleLifetime = 1.1
        e.particleLifetimeRange = 0.35
        e.particleSize = CGSize(width: 5, height: 5)
        e.particleScale = 0.7
        e.particleScaleRange = 0.45
        e.particleAlpha = 0.95
        e.particleAlphaSpeed = -0.7
        e.particleColorSequence = SKKeyframeSequence(keyframeValues: [
            neonLime, neonCyan, neonOrange, neonPink, neonLime,
        ], times: [0, 0.25, 0.5, 0.75, 1.0])
        e.particleColorBlendFactor = 1
        e.particleBlendMode = .add
        e.particleSpeed = 160
        e.particleSpeedRange = 80
        e.emissionAngle = .pi / 2
        e.emissionAngleRange = .pi
        e.yAcceleration = -220
        e.particleRotationRange = .pi
        e.particleRotationSpeed = 4
        e.particlePositionRange = CGVector(dx: 120, dy: 8)
        e.zPosition = 8
        return e
    }

    /// Storefront sign crops from mid_buildings.png (SPOTLESS / GLOW MART / FIZZ / etc.).
    private static var storefrontSignTextures: [SKTexture]?

    private static func loadStorefrontSignTextures() -> [SKTexture] {
        if let storefrontSignTextures { return storefrontSignTextures }
        guard let img = AssetManifest.image(for: .midBuildings, preferScale: 1),
              let cg = img.cgImage
        else {
            storefrontSignTextures = []
            return []
        }
        // Normalized crops covering neon storefront bands in the 2560×1440 plate.
        let boxes: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (0.12, 0.42, 0.22, 0.12),
            (0.38, 0.48, 0.18, 0.10),
            (0.58, 0.40, 0.20, 0.11),
            (0.78, 0.46, 0.16, 0.10),
            (0.22, 0.62, 0.18, 0.09),
            (0.52, 0.66, 0.20, 0.10),
        ]
        var out: [SKTexture] = []
        let iw = CGFloat(cg.width)
        let ih = CGFloat(cg.height)
        for (nx, ny, nw, nh) in boxes {
            let rect = CGRect(x: nx * iw, y: ny * ih, width: nw * iw, height: nh * ih)
            guard let slice = cg.cropping(to: rect) else { continue }
            let tex = SKTexture(cgImage: slice)
            tex.filteringMode = .linear
            out.append(tex)
        }
        // Fallback solid neon plates if crops failed (still magenta+teal).
        if out.isEmpty {
            for color in [neonPink, neonCyan, neonPink, neonCyan] {
                let size = CGSize(width: 64, height: 24)
                let format = UIGraphicsImageRendererFormat()
                format.opaque = false
                format.scale = 2
                let baked = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                    color.setFill()
                    UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 3).fill()
                }
                out.append(SKTexture(image: baked))
            }
        }
        storefrontSignTextures = out
        return out
    }

    /// Bright neon storefront signs for the mid parallax band (real art + glow, not flat rectangles).
    public static func neonSignageStrip(width: CGFloat, height: CGFloat) -> SKNode {
        let root = SKNode()
        root.name = "neonSignageStrip"
        let textures = loadStorefrontSignTextures()
        let accents: [SKColor] = [neonPink, neonCyan, neonPink, neonCyan, neonPink, neonCyan]
        var x: CGFloat = -width * 0.42
        var i = 0
        while x < width * 0.48 {
            let w = CGFloat(52 + (i % 4) * 18)
            let h = CGFloat(18 + (i % 3) * 8)
            let accent = accents[i % accents.count]
            let glow = SKSpriteNode(texture: softCircleTexture(), size: CGSize(width: w * 1.8, height: h * 2.6))
            glow.position = CGPoint(x: x, y: CGFloat((i % 4) * 24) - 8)
            glow.color = accent
            glow.colorBlendFactor = 1
            glow.alpha = 0.55
            glow.blendMode = .add
            glow.zPosition = 0
            root.addChild(glow)

            // Dark backing only — never flat hot-pink slabs.
            let backing = SKSpriteNode(
                color: SKColor(red: 0.08, green: 0.05, blue: 0.12, alpha: 1),
                size: CGSize(width: w * 1.02, height: h * 1.05)
            )
            backing.name = "storefrontBacking"
            backing.position = glow.position
            backing.alpha = 0.85
            backing.zPosition = 0.4
            root.addChild(backing)

            let sign: SKSpriteNode
            if !textures.isEmpty {
                let tex = textures[i % textures.count]
                sign = SKSpriteNode(texture: tex, size: CGSize(width: w, height: h))
            } else {
                sign = SKSpriteNode(color: accent, size: CGSize(width: w, height: h))
            }
            sign.name = "storefrontSign"
            sign.position = glow.position
            sign.alpha = 1
            sign.zPosition = 1
            let isPink = i % 2 == 0
            if isPink {
                sign.color = neonPink
                sign.colorBlendFactor = 0.4
                sign.blendMode = .add
                glow.alpha = 0.4
            } else {
                sign.color = neonCyan
                sign.colorBlendFactor = 0.28
                sign.blendMode = .add
            }
            root.addChild(sign)

            let rim = SKShapeNode(rectOf: CGSize(width: w * 1.08, height: h * 1.12), cornerRadius: 2)
            rim.name = "storefrontRim"
            rim.position = glow.position
            rim.fillColor = .clear
            rim.strokeColor = accent
            rim.lineWidth = isPink ? 1.4 : 1.1
            rim.glowWidth = isPink ? 1.8 : 1.0
            rim.alpha = isPink ? 0.7 : 0.5
            rim.zPosition = 1.5
            root.addChild(rim)

            if i % 5 == 0 {
                let flicker = SKAction.sequence([
                    SKAction.fadeAlpha(to: 0.55, duration: 0.08),
                    SKAction.fadeAlpha(to: 1.0, duration: 0.12),
                    SKAction.wait(forDuration: 2.2 + Double(i % 3) * 0.4),
                ])
                sign.run(SKAction.repeatForever(flicker))
            }
            x += w + CGFloat(12 + (i % 4) * 6)
            i += 1
        }
        root.zPosition = -19
        return root
    }

    /// World-layer storefront crops along the play corridor (real sign art + soft glow; no solid pink plates).
    public static func worldStorefrontSigns(mapWidth: CGFloat, tile: CGFloat) -> SKNode {
        let root = SKNode()
        root.name = "worldStorefronts"
        // Above facade panels (~2.4) / shafts (~2.6); below actors (≥20).
        root.zPosition = 7.5
        let textures = loadStorefrontSignTextures()
        // Varied pinks so additive glow doesn't collapse into one flat 8-bit magenta bin.
        let pinks: [SKColor] = [
            SKColor(red: 1.0, green: 0.22, blue: 0.66, alpha: 1),
            SKColor(red: 1.0, green: 0.34, blue: 0.78, alpha: 1),
            SKColor(red: 0.92, green: 0.18, blue: 0.72, alpha: 1),
        ]
        let accents: [SKColor] = [pinks[0], neonCyan, pinks[1], neonCyan, pinks[2], neonCyan]
        // Neon Docks street deck sits near tile y≈7. Hang 4–6 real signs above it,
        // starting early enough that midrun (worldTX≈20–28) frames at least two.
        // Soft glow + thin neon rim — never opaque hot-pink slabs for a CI gate.
        let count = min(6, max(4, textures.isEmpty ? 4 : textures.count))
        let span = mapWidth * 0.42
        let startX = tile * 10
        for i in 0..<count {
            let x = startX + CGFloat(i) * (span / CGFloat(max(count - 1, 1)))
            guard x < mapWidth * 0.72 else { break }
            let w = tile * (2.6 + CGFloat(i % 3) * 0.4)
            let h = tile * (1.15 + CGFloat(i % 2) * 0.3)
            let accent = accents[i % accents.count]
            let isPink = i % 2 == 0
            // Hang above camera (hero+56 ≈ tile*8–9) so midrun upper-band (12–48% screen) catches neon.
            let y = tile * (12.8 + CGFloat(i % 3) * 0.55)

            // Two smaller coronas (not one huge uniform blob) — readable neon, split bins.
            for (j, off) in [CGPoint(x: -w * 0.18, y: h * 0.12), CGPoint(x: w * 0.2, y: -h * 0.08)].enumerated() {
                let glow = SKSpriteNode(
                    texture: softCircleTexture(),
                    size: CGSize(width: w * 0.95, height: h * 1.35)
                )
                glow.name = "storefrontGlow"
                glow.position = CGPoint(x: x + off.x, y: y + off.y)
                glow.color = isPink ? pinks[(i + j) % pinks.count] : accent
                glow.colorBlendFactor = 1
                glow.alpha = isPink ? 0.58 : 0.38
                glow.blendMode = .add
                glow.zPosition = 0
                root.addChild(glow)
            }

            // Subtle dark plate behind the crop — not a flat magenta fill.
            let backing = SKSpriteNode(
                color: SKColor(red: 0.07, green: 0.04, blue: 0.11, alpha: 1),
                size: CGSize(width: w * 1.05, height: h * 1.08)
            )
            backing.name = "storefrontBacking"
            backing.position = CGPoint(x: x, y: y)
            backing.alpha = 0.9
            backing.zPosition = 0.4
            root.addChild(backing)

            let sign: SKSpriteNode
            if !textures.isEmpty {
                sign = SKSpriteNode(texture: textures[i % textures.count], size: CGSize(width: w, height: h))
            } else {
                // Fallback: thin neon rim only (not a solid slab).
                sign = SKSpriteNode(color: accent.withAlphaComponent(0.55), size: CGSize(width: w, height: h * 0.35))
            }
            sign.name = "storefrontSign"
            sign.position = CGPoint(x: x, y: y)
            sign.zPosition = 1
            if isPink {
                sign.color = pinks[i % pinks.count]
                sign.colorBlendFactor = 0.42
            } else {
                sign.color = neonCyan
                sign.colorBlendFactor = 0.28
            }
            sign.blendMode = .add
            root.addChild(sign)

            // Thin neon tube rim (stroke only — never a filled slab).
            let rim = SKShapeNode(rectOf: CGSize(width: w * 1.06, height: h * 1.1), cornerRadius: 3)
            rim.name = "storefrontRim"
            rim.position = CGPoint(x: x, y: y)
            rim.fillColor = .clear
            rim.strokeColor = accent
            rim.lineWidth = isPink ? 1.8 : 1.2
            rim.glowWidth = isPink ? 2.2 : 1.2
            rim.alpha = isPink ? 0.85 : 0.55
            rim.zPosition = 1.5
            root.addChild(rim)

            let puddle = SKSpriteNode(texture: softCircleTexture(), size: CGSize(width: w * 0.9, height: tile * 0.32))
            puddle.name = "storefrontWet"
            puddle.position = CGPoint(x: x, y: tile * 7.35)
            puddle.color = accent
            puddle.colorBlendFactor = 1
            puddle.alpha = 0.28
            puddle.blendMode = .add
            puddle.zPosition = -1
            root.addChild(puddle)

            if isPink {
                sign.run(SKAction.repeatForever(SKAction.sequence([
                    SKAction.fadeAlpha(to: 0.65, duration: 0.12),
                    SKAction.fadeAlpha(to: 1.0, duration: 0.16),
                    SKAction.wait(forDuration: 2.6 + Double(i) * 0.35),
                ])))
            }
        }
        return root
    }

    /// Palette anchors for smoke side-by-side check (Game Plan bright magenta + teal).
    public static let paletteMagenta = (r: 1.0, g: 0.28, b: 0.72)
    public static let paletteTeal = (r: 0.25, g: 0.98, b: 1.0)

    public static var expectedNodesPerSolidTile: Int { 1 }

    // MARK: - Neon grid bake (Grid-inspired, original magenta/teal)

    private enum NeonBakeStyle {
        case platform
        case prop
    }

    /// Composite thin glowing grid + crisp neon edges onto a tile PNG (CPU once at warm).
    private static func bakeNeonGrid(onto image: UIImage, style: NeonBakeStyle) -> UIImage {
        let size = image.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            image.draw(in: CGRect(origin: .zero, size: size))
            let cg = ctx.cgContext
            let w = size.width
            let h = size.height
            let line = max(1.0 / image.scale, 0.75)

            if style == .platform {
                // Thin grid over dark floor/wall slabs.
                cg.setStrokeColor(UIColor(red: 0.25, green: 0.98, blue: 1.0, alpha: 0.32).cgColor)
                cg.setLineWidth(line)
                let step = max(5, w / 4)
                var x: CGFloat = step
                while x < w - 1 {
                    cg.move(to: CGPoint(x: x, y: 2))
                    cg.addLine(to: CGPoint(x: x, y: h - 2))
                    x += step
                }
                var y: CGFloat = step
                while y < h - 1 {
                    cg.move(to: CGPoint(x: 2, y: y))
                    cg.addLine(to: CGPoint(x: w - 2, y: y))
                    y += step
                }
                cg.strokePath()

                // Crisp cyan top edge + magenta bottom lip.
                cg.setStrokeColor(UIColor(red: 0.25, green: 0.98, blue: 1.0, alpha: 0.9).cgColor)
                cg.setLineWidth(line * 2.2)
                cg.move(to: CGPoint(x: 0, y: 1.5))
                cg.addLine(to: CGPoint(x: w, y: 1.5))
                cg.strokePath()
                cg.setStrokeColor(UIColor(red: 1.0, green: 0.28, blue: 0.72, alpha: 0.65).cgColor)
                cg.setLineWidth(line * 1.6)
                cg.move(to: CGPoint(x: 0, y: h - 1.5))
                cg.addLine(to: CGPoint(x: w, y: h - 1.5))
                cg.strokePath()
            } else {
                // Props: neon rim only (no dense grid).
                cg.setStrokeColor(UIColor(red: 0.25, green: 0.98, blue: 1.0, alpha: 0.55).cgColor)
                cg.setLineWidth(line * 1.8)
                cg.stroke(CGRect(x: 1, y: 1, width: w - 2, height: h - 2))
                cg.setStrokeColor(UIColor(red: 1.0, green: 0.28, blue: 0.72, alpha: 0.35).cgColor)
                cg.setLineWidth(line)
                cg.stroke(CGRect(x: 3, y: 3, width: w - 6, height: h - 6))
            }
        }
    }

    private static func perspectiveGridTexture() -> SKTexture {
        if let perspectiveGridTex { return perspectiveGridTex }
        let size = CGSize(width: 512, height: 280)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = false
        let img = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            let w = size.width
            let h = size.height
            let vanishing = CGPoint(x: w * 0.5, y: h * 0.18)
            // Horizon bar
            cg.setStrokeColor(UIColor(red: 1.0, green: 0.28, blue: 0.72, alpha: 0.35).cgColor)
            cg.setLineWidth(1.2)
            cg.move(to: CGPoint(x: 0, y: vanishing.y))
            cg.addLine(to: CGPoint(x: w, y: vanishing.y))
            cg.strokePath()
            // Perspective spokes (floor grid vanishing into the skyline — not a Tron copy).
            cg.setStrokeColor(UIColor(red: 0.25, green: 0.98, blue: 1.0, alpha: 0.28).cgColor)
            cg.setLineWidth(1)
            let spokes = 11
            for i in 0..<spokes {
                let t = CGFloat(i) / CGFloat(spokes - 1)
                let x = t * w
                cg.move(to: vanishing)
                cg.addLine(to: CGPoint(x: x, y: h))
            }
            cg.strokePath()
            // Horizontal depth rings
            cg.setStrokeColor(UIColor(red: 1.0, green: 0.28, blue: 0.72, alpha: 0.22).cgColor)
            for i in 1...7 {
                let t = CGFloat(i) / 8.0
                let y = vanishing.y + (h - vanishing.y) * (t * t)
                let inset = (1 - t) * w * 0.42
                cg.move(to: CGPoint(x: inset, y: y))
                cg.addLine(to: CGPoint(x: w - inset, y: y))
            }
            cg.strokePath()
        }
        let tex = SKTexture(image: img)
        tex.filteringMode = .linear
        perspectiveGridTex = tex
        return tex
    }

    // MARK: - Loaders

    private static func loadTileImage(index: Int) -> UIImage? {
        let name = String(format: "tile_%02d", index)
        let rel = "sprites/tiles/\(name)"
        guard let url = AssetManifest.fileURLPublic(relative: rel, extensions: ["png"]) else { return nil }
        return downsampledUIImage(url: url, maxPixel: 256)
    }

    /// Public for ArtLibrary district / drop-in packs (still ImageIO downsampled).
    public static func downsampledTexture(relative: String, maxPixel: CGFloat) -> SKTexture? {
        guard let url = AssetManifest.fileURLPublic(relative: relative, extensions: ["png"]),
              let img = downsampledUIImage(url: url, maxPixel: maxPixel) else { return nil }
        let tex = SKTexture(image: img)
        tex.filteringMode = .linear
        return tex
    }

    /// Memory-safe downsample via ImageIO thumbnails (no full-res bitmap spike).
    public static func downsampledUIImage(url: URL, maxPixel: CGFloat) -> UIImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// Title art hooks — logo PNGs + strings. Bundle ID / Magpie target names stay unchanged.
public enum TitleArt {
    /// Prefer Nicholas-approved B1 holo glass, then legacy wordmarks.
    public static let logoCandidates: [String] = [
        "ui/logo_b1_holo_glass@1024",
        "ui/logo_b1_holo_glass",
        "ui/logo_neon_city_bandit@1024",
        "ui/logo_neon_city_bandit",
        "ui/logo_title@1024",
        "ui/logo_title",
    ]
    public static let compactLogoCandidates: [String] = [
        "ui/logo_b1_holo_glass_compact",
        "ui/logo_b1_holo_glass",
    ]
    /// Official title/start key art (Higgsfield leap still) — aspect-fill behind chrome.
    public static let titleKeyArtCandidates: [String] = [
        "ui/title_leap@1024",
        "ui/title_leap",
    ]
    public static let displayTitle = "The Neon City Bandit"
    public static let fallbackWordmark = "THE NEON CITY\nBANDIT"
    /// In-game credits. Spriterrific steampunk-neon bandit / MOP sheets owned by Cinder & Crown.
    public static let assetCredits = "Art: Spriterrific (Cinder & Crown)"
}

/// Bandit raccoon — Spriterrific sheets (west-facing); feet sit IN the ground art.
@MainActor
public final class BanditVisual: SKNode {
    public let sprite: SKSpriteNode
    private let body: SKNode
    private let rig: SKNode
    private let head: SKSpriteNode
    private let torso: SKSpriteNode
    private let armF: SKSpriteNode
    private let armB: SKSpriteNode
    private let legF: SKSpriteNode
    private let legB: SKSpriteNode
    private let tail: SKSpriteNode
    private let shadow: SKShapeNode
    private let maskGlow: SKSpriteNode
    private let rimLight: SKSpriteNode
    private var cycles: [String: SpriteCycle] = [:]
    private var runTextures: [SKTexture] = []
    private var walkTextures: [SKTexture] = []
    private var idleTextures: [SKTexture] = []
    private var jumpTextures: [SKTexture] = []
    private var attackTextures: [SKTexture] = []
    private var hurtTextures: [SKTexture] = []
    private var deathTextures: [SKTexture] = []
    private var pickUpTextures: [SKTexture] = []
    private var headAnchorsByAnim: [BanditAnim: [HeadAnchor]] = [:]
    private var idleTex: SKTexture?
    private var jumpTex: SKTexture?
    private var fallTex: SKTexture?
    private var pounceTex: SKTexture?
    private var flopTex: SKTexture?
    private var maskTex: SKTexture?
    private var bobPhase: CGFloat = 0
    /// World facing: +1 = right/east. Source run/idle sheets face WEST (muzzle left).
    private var facingSign: CGFloat = 1
    private var usesWestSheets = true
    private var footAnchorY: CGFloat = 0.14
    private var currentAnim: BanditAnim = .idle
    private var trailPool: [SKSpriteNode] = []
    private var trailCursor: Int = 0
    private var trailAcc: CGFloat = 0
    private let trailPoolSize = 6
    private var lastTrailWorldX: CGFloat = 0
    private var sheetDriven = false
    /// Manual sheet driver so fps can track |vx| and LEDs can follow the head frame.
    private var driveTextures: [SKTexture] = []
    private var driveAnchors: [HeadAnchor] = []
    private var driveIndex: CGFloat = 0
    private var driveFPS: CGFloat = 12
    private var driveLoop = true
    private var driveSpeed: CGFloat = 1

    public override init() {
        ArtCatalog.warmAtlases()
        // ArtLibrary prefers sprites/library/bandit (Higgsfield shared) then spriterrific.
        let idleC = ArtLibrary.banditCycle(.idle)
        let walkC = ArtLibrary.banditCycle(.walk)
        let runC = ArtLibrary.banditCycle(.run)
        let jumpC = ArtLibrary.banditCycle(.jump)
        let attackC = ArtLibrary.banditCycle(.pounce) // pounce → attack fallback
        let hurtC = ArtLibrary.banditCycle(.hurt)
        let deathC = ArtLibrary.banditCycle(.death)
        let pickC = ArtLibrary.banditCycle(.pickUp)
        let victoryC = ArtLibrary.banditCycle(.victory)
        sheetDriven = (runC?.textures.count ?? 0) >= 6 && (idleC?.textures.count ?? 0) >= 2
        if let idleC {
            cycles["idle"] = idleC; idleTextures = idleC.textures; footAnchorY = idleC.footAnchorY
            headAnchorsByAnim[.idle] = idleC.headAnchors
        }
        if let walkC {
            cycles["walk"] = walkC; walkTextures = walkC.textures
            headAnchorsByAnim[.walk] = walkC.headAnchors
        }
        if let runC {
            cycles["run"] = runC; runTextures = runC.textures
            headAnchorsByAnim[.run] = runC.headAnchors
        }
        if let jumpC {
            cycles["jump"] = jumpC; jumpTextures = jumpC.textures
            headAnchorsByAnim[.jump] = jumpC.headAnchors
            headAnchorsByAnim[.apex] = jumpC.headAnchors
            headAnchorsByAnim[.fall] = jumpC.headAnchors
            headAnchorsByAnim[.wallSlide] = jumpC.headAnchors
        }
        if let attackC {
            cycles["attack"] = attackC; attackTextures = attackC.textures
            headAnchorsByAnim[.pounce] = attackC.headAnchors
        }
        if let hurtC {
            cycles["hurt"] = hurtC; hurtTextures = hurtC.textures
            headAnchorsByAnim[.hurt] = hurtC.headAnchors
        }
        if let deathC {
            cycles["death"] = deathC; deathTextures = deathC.textures
            headAnchorsByAnim[.death] = deathC.headAnchors
        }
        if let pickC {
            cycles["pick_up"] = pickC; pickUpTextures = pickC.textures
            headAnchorsByAnim[.pickUp] = pickC.headAnchors
        }
        if let victoryC {
            cycles["victory"] = victoryC
        }
        // CI + playtest evidence: with west-flip the raccoon still faces left while
        // running right (backpack/cyan tubes on the right). Treat shipping sheets as
        // east-facing so body.xScale = +sign(vx) puts the muzzle forward.
        usesWestSheets = false

        if !sheetDriven {
            let licensedRun = ArtCatalog.licensedCycleTextures("run", maxFrames: 12)
            runTextures = licensedRun.count >= 6 ? licensedRun : ArtCatalog.textures(AssetManifest.runCycle)
            idleTextures = ArtCatalog.licensedCycleTextures("idle", maxFrames: 8)
            jumpTextures = ArtCatalog.licensedCycleTextures("jump", maxFrames: 8)
            usesWestSheets = false
        }

        idleTex = idleTextures.first ?? ArtCatalog.texture(.raccoonIdle)
        jumpTex = jumpTextures.first ?? ArtCatalog.texture(.raccoonJump)
        fallTex = jumpTextures.dropFirst(jumpTextures.count * 2 / 3).first ?? ArtCatalog.texture(.raccoonFall)
        pounceTex = attackTextures.first ?? ArtCatalog.texture(.raccoonPounce)
        flopTex = attackTextures.last ?? ArtCatalog.texture(.raccoonBellyFlop)
        maskTex = ArtCatalog.texture(.raccoonMaskMode)

        let parts = ArtCatalog.raccoonRigParts()

        body = SKNode()
        body.name = "body"
        rig = SKNode()
        rig.name = "rig"

        // Anchor at normalized foot baseline so soles sit IN the ground art.
        sprite = SKSpriteNode(texture: idleTex, size: SpriteCycles.banditDisplaySize)
        sprite.name = "sprite"
        sprite.anchorPoint = CGPoint(x: 0.5, y: footAnchorY)
        sprite.zPosition = 1
        ArtCatalog.applyDespill(sprite)

        torso = SKSpriteNode(texture: parts.torso, size: CGSize(width: 36, height: 34))
        torso.name = "torso"
        torso.position = CGPoint(x: 0, y: -2)
        torso.alpha = 0
        ArtCatalog.applyDespill(torso)

        head = SKSpriteNode(texture: parts.head, size: CGSize(width: 40, height: 36))
        head.name = "head"
        head.position = CGPoint(x: 2, y: 20)
        head.alpha = 0
        ArtCatalog.applyDespill(head)

        armB = SKSpriteNode(texture: parts.arm, size: CGSize(width: 18, height: 26))
        armB.name = "armB"
        armB.anchorPoint = CGPoint(x: 0.5, y: 1.0)
        armB.position = CGPoint(x: -14, y: 10)
        armB.alpha = 0
        ArtCatalog.applyDespill(armB)

        armF = SKSpriteNode(texture: parts.arm, size: CGSize(width: 18, height: 26))
        armF.name = "armF"
        armF.anchorPoint = CGPoint(x: 0.5, y: 1.0)
        armF.position = CGPoint(x: 14, y: 10)
        armF.xScale = -1
        armF.alpha = 0
        ArtCatalog.applyDespill(armF)

        legB = SKSpriteNode(texture: parts.leg, size: CGSize(width: 20, height: 28))
        legB.name = "legB"
        legB.anchorPoint = CGPoint(x: 0.5, y: 1.0)
        legB.position = CGPoint(x: -8, y: -14)
        legB.alpha = 0
        ArtCatalog.applyDespill(legB)

        legF = SKSpriteNode(texture: parts.leg, size: CGSize(width: 20, height: 28))
        legF.name = "legF"
        legF.anchorPoint = CGPoint(x: 0.5, y: 1.0)
        legF.position = CGPoint(x: 8, y: -14)
        legF.alpha = 0
        ArtCatalog.applyDespill(legF)

        tail = SKSpriteNode(texture: parts.tail, size: CGSize(width: 36, height: 24))
        tail.name = "tail"
        tail.anchorPoint = CGPoint(x: 0.9, y: 0.5)
        tail.position = CGPoint(x: -16, y: -2)
        tail.zPosition = -0.3
        tail.alpha = sheetDriven ? 0 : 1
        ArtCatalog.applyDespill(tail)

        shadow = SKShapeNode(ellipseOf: CGSize(width: 40, height: 10))
        shadow.fillColor = SKColor(white: 0, alpha: 0.4)
        shadow.strokeColor = .clear
        shadow.zPosition = -1
        shadow.position = CGPoint(x: 0, y: -2)

        // Mask LED glints — one profile goggle lens by default; twin only for front idle.
        maskGlow = SKSpriteNode(color: .clear, size: CGSize(width: 28, height: 16))
        maskGlow.alpha = 0
        maskGlow.isHidden = true
        maskGlow.zPosition = 3
        maskGlow.position = CGPoint(x: 2, y: SpriteCycles.banditDisplaySize.height * 0.52)
        let eyeL = SKShapeNode(circleOfRadius: 2.2)
        eyeL.name = "maskEyeL"
        eyeL.fillColor = ArtCatalog.neonCyan
        eyeL.strokeColor = .white
        eyeL.lineWidth = 0.5
        eyeL.glowWidth = 1.6
        eyeL.position = CGPoint(x: -5, y: 1)
        eyeL.isHidden = true
        let eyeR = SKShapeNode(circleOfRadius: 3.0)
        eyeR.name = "maskEyeR"
        eyeR.fillColor = ArtCatalog.neonCyan
        eyeR.strokeColor = .white
        eyeR.lineWidth = 0.6
        eyeR.glowWidth = 2.0
        // Profile: sit on the forward goggle lens, not the muzzle.
        eyeR.position = CGPoint(x: 5, y: 3)
        maskGlow.addChild(eyeL)
        maskGlow.addChild(eyeR)

        // Soft magenta/cyan rim behind the sheet (readable against dark alley mid-tones).
        rimLight = SKSpriteNode(texture: idleTex, size: SpriteCycles.banditDisplaySize)
        rimLight.name = "rimLight"
        rimLight.anchorPoint = CGPoint(x: 0.5, y: footAnchorY)
        rimLight.zPosition = 0.4
        rimLight.color = ArtCatalog.neonPink
        rimLight.colorBlendFactor = 0.85
        rimLight.alpha = 0
        rimLight.blendMode = .add

        super.init()
        addChild(shadow)
        addChild(body)
        body.addChild(rimLight)
        body.addChild(sprite)
        body.addChild(maskGlow)
        body.addChild(rig)
        for n in [tail, armB, legB, torso, legF, armF, head] as [SKNode] {
            rig.addChild(n)
        }
        name = "bandit"
        applyFacingScale()

        for i in 0..<trailPoolSize {
            let speck = SKSpriteNode(texture: idleTex, size: SpriteCycles.banditDisplaySize)
            speck.name = "trail_\(i)"
            speck.anchorPoint = CGPoint(x: 0.5, y: footAnchorY)
            speck.blendMode = .add
            speck.alpha = 0
            speck.isHidden = true
            speck.zPosition = -0.2
            trailPool.append(speck)
            addChild(speck)
        }
        startIdleMotion()
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError() }

    /// Force GPU residency for KO / Mask / hurt sheets before first combat beat (cuts hitch).
    public func prewarmCombatTextures() {
        var warm: [SKTexture] = deathTextures + hurtTextures + attackTextures
        if let maskTex { warm.append(maskTex) }
        if let flopTex { warm.append(flopTex) }
        if !warm.isEmpty {
            SKTexture.preload(warm) {}
        }
        // Touch glow nodes so first Mask frame doesn't allocate them cold.
        maskGlow.alpha = 0.001
        rimLight.alpha = 0.001
    }

    public func setFacing(_ facing: Double) {
        facingSign = facing >= 0 ? 1 : -1
        applyFacingScale()
        sprite.xScale = abs(sprite.xScale)
    }

    /// Apply facing from travel velocity every frame (moonwalk fix).
    /// Source art faces west; body.xScale = −sign(vx) so the muzzle leads travel.
    public func setFacingFromVelocity(_ velocityX: Double, fallbackFacing: Double) {
        if abs(velocityX) > 0.01 {
            facingSign = velocityX >= 0 ? 1 : -1
        } else {
            facingSign = fallbackFacing >= 0 ? 1 : -1
        }
        applyFacingScale()
        sprite.xScale = abs(sprite.xScale)
        // Kill any leftover squash action that could leave the wrong sign mid-drop.
        if body.action(forKey: "sq") == nil {
            body.xScale = bodyFaceScale()
        }
    }

    /// Testable: west sheets flip when velocity/facing points east (+1).
    public static func bodyXScale(facingSign: CGFloat, sheetsFaceWest: Bool) -> CGFloat {
        sheetsFaceWest ? -facingSign : facingSign
    }

    private func bodyFaceScale() -> CGFloat {
        Self.bodyXScale(facingSign: facingSign, sheetsFaceWest: usesWestSheets)
    }

    private func applyFacingScale() {
        // Always assert from velocity/facing sign — never leave a stale squash sign.
        body.xScale = bodyFaceScale()
    }

    /// Keep west-sheet flip correct without clobbering an in-flight squash magnitude.
    private func refreshFacingScalePreservingSquash() {
        let face = bodyFaceScale()
        if body.action(forKey: "sq") != nil {
            let mag = abs(body.xScale)
            body.xScale = (face < 0 ? -1 : 1) * max(mag, 0.01)
        } else {
            body.xScale = face
        }
    }

    public func squash(x: CGFloat, y: CGFloat) {
        body.removeAction(forKey: "sq")
        let face = bodyFaceScale()
        body.xScale = face
        body.yScale = 1
        // Harder impact pose, quicker rebound — reads on a phone screen.
        body.run(SKAction.sequence([
            SKAction.group([
                SKAction.scaleX(to: x * face, duration: 0.028),
                SKAction.scaleY(to: y, duration: 0.028),
            ]),
            SKAction.group([
                SKAction.scaleX(to: 1.12 * face, duration: 0.045),
                SKAction.scaleY(to: 0.88, duration: 0.045),
            ]),
            SKAction.group([
                SKAction.scaleX(to: face, duration: 0.06),
                SKAction.scaleY(to: 1, duration: 0.06),
            ]),
        ]), withKey: "sq")
    }

    public func show(
        anim: BanditAnim,
        maskMode: Bool,
        dt: CGFloat,
        moveSpeed: CGFloat = 0,
        runSpeed: CGFloat = 1,
        smokeLite: Bool = false
    ) {
        if anim != currentAnim {
            currentAnim = anim
            applyPose(anim)
        }
        // Animation rate tracks horizontal speed for walk/run (clamped); one-shots stay at authored fps.
        // Floor at ~1× so a slow walk never reads as a frozen idle cutout sliding across the street.
        let speedRatio: CGFloat = {
            switch anim {
            case .walk:
                let denom = max(runSpeed * 0.55, 0.1)
                return max(1.0, min(1.55, abs(moveSpeed) / denom))
            case .run:
                let denom = max(runSpeed, 0.1)
                return max(1.05, min(1.65, abs(moveSpeed) / denom * 1.15))
            default:
                return 1
            }
        }()
        driveSpeed = speedRatio
        bobPhase += dt * speedRatio
        // Personality: idle breathe + locomotion bob (even on sheet-driven packs).
        // Never call body.setScale — that resets xScale and wipes facing (moonwalk bug).
        if anim == .idle {
            sprite.position.y = sin(bobPhase * 2.4) * 1.6
            let breathe = 1.0 + sin(bobPhase * 2.1) * 0.018
            body.yScale = breathe
        } else if !sheetDriven, anim == .run || anim == .walk {
            let runLike = anim == .run
            sprite.position.y = sin(bobPhase * (runLike ? 15 : 3.2)) * (runLike ? 2.6 : 1.3)
            body.yScale = 1
        } else if sheetDriven, anim == .run || anim == .walk {
            sprite.position.y = sin(bobPhase * (anim == .run ? 18 : 12)) * (anim == .run ? 1.8 : 1.1)
            body.yScale = 1
        } else {
            sprite.position.y = 0
            body.yScale = 1
        }
        // Re-assert facing every frame; preserve squash magnitude if an impact pose is running.
        refreshFacingScalePreservingSquash()
        // Forward lean while moving — sells speed without needing a new sheet.
        if anim == .run || anim == .walk {
            let lean: CGFloat = anim == .run ? 0.11 : 0.06
            body.zRotation = facingSign * lean
        } else if abs(body.zRotation) > 0.001 {
            body.zRotation *= 0.7
        }
        tickSheetDriver(dt: dt)
        if maskMode {
            // Crisp cyan rim — not a blurry ghost head wash.
            sprite.color = ArtCatalog.neonCyan
            sprite.colorBlendFactor = sheetDriven ? 0.18 : 0.28
            tail.color = ArtCatalog.neonCyan
            tail.colorBlendFactor = 0.28
            maskGlow.isHidden = false
            maskGlow.alpha = 0.95
            rimLight.isHidden = false
            rimLight.alpha = 0.55
            rimLight.texture = sprite.texture
            rimLight.position = CGPoint(x: facingSign * 2.5, y: 1.5)
        } else {
            // Lift mid fur off the dark alley so the silhouette reads at a glance.
            sprite.color = SKColor(red: 0.92, green: 0.96, blue: 1.0, alpha: 1)
            sprite.colorBlendFactor = 0.18
            tail.color = SKColor(red: 0.92, green: 0.96, blue: 1.0, alpha: 1)
            tail.colorBlendFactor = 0.12
            maskGlow.isHidden = true
            maskGlow.alpha = 0
            rimLight.alpha = 0.48
            rimLight.isHidden = false
            rimLight.texture = sprite.texture
            rimLight.color = ArtCatalog.neonCyan
            rimLight.setScale(1.08)
            rimLight.position = CGPoint(x: -facingSign * 3.0, y: 2.0)
        }
        updateMaskGlowToHead()
        tickMotionTrail(anim: anim, maskMode: maskMode, dt: dt, smokeLite: smokeLite)
    }

    private func tpf(_ action: String, fallback: TimeInterval) -> TimeInterval {
        cycles[action]?.timePerFrame ?? fallback
    }

    private func beginDrive(
        textures: [SKTexture],
        anchors: [HeadAnchor],
        fps: CGFloat,
        loop: Bool
    ) {
        sprite.removeAction(forKey: "frames")
        driveTextures = textures
        driveAnchors = anchors
        driveFPS = max(fps, 1)
        driveLoop = loop
        driveIndex = 0
        if let first = textures.first {
            sprite.texture = first
            rimLight.texture = first
        }
        updateMaskGlowToHead()
    }

    private func tickSheetDriver(dt: CGFloat) {
        guard !driveTextures.isEmpty else { return }
        driveIndex += dt * driveFPS * driveSpeed
        if driveLoop {
            let count = CGFloat(driveTextures.count)
            if driveIndex >= count { driveIndex = driveIndex.truncatingRemainder(dividingBy: count) }
        } else {
            driveIndex = min(driveIndex, CGFloat(driveTextures.count - 1))
        }
        let i = max(0, min(driveTextures.count - 1, Int(driveIndex)))
        sprite.texture = driveTextures[i]
        rimLight.texture = driveTextures[i]
    }

    private func updateMaskGlowToHead() {
        let i = max(0, min(driveTextures.count - 1, Int(driveIndex)))
        let anchor: HeadAnchor = {
            if driveAnchors.indices.contains(i) { return driveAnchors[i] }
            if let list = headAnchorsByAnim[currentAnim], list.indices.contains(i) { return list[i] }
            return HeadAnchor(x: 0.02, y: 0.52)
        }()
        let w = sprite.size.width
        let h = sprite.size.height
        // Goggle offset above the muzzle/cheek so the glint sits on the lens in profile.
        let goggle = CGPoint(x: 0.06 * w, y: 0.06 * h)
        maskGlow.position = CGPoint(x: anchor.x * w + goggle.x, y: anchor.y * h + goggle.y)
        // Side-view sheets: one goggle-lens glint (front mascot uses a separate node).
        maskGlow.childNode(withName: "maskEyeL")?.isHidden = true
        maskGlow.childNode(withName: "maskEyeR")?.isHidden = false
    }

    private func playLoop(_ textures: [SKTexture], action: String, fallbackTPF: TimeInterval) {
        let fps = CGFloat(1.0 / tpf(action, fallback: fallbackTPF))
        let anchors = headAnchorsByAnim[currentAnim]
            ?? cycles[action]?.headAnchors
            ?? Array(repeating: HeadAnchor(x: 0, y: 0.48), count: textures.count)
        beginDrive(textures: textures, anchors: anchors, fps: fps, loop: true)
    }

    private func playOnce(_ textures: [SKTexture], action: String, fallbackTPF: TimeInterval) {
        let fps = CGFloat(1.0 / tpf(action, fallback: fallbackTPF))
        let anchors = headAnchorsByAnim[currentAnim]
            ?? cycles[action]?.headAnchors
            ?? Array(repeating: HeadAnchor(x: 0, y: 0.48), count: textures.count)
        beginDrive(textures: textures, anchors: anchors, fps: fps, loop: false)
    }

    private func applyPose(_ anim: BanditAnim) {
        stopLimbActions()
        sprite.removeAction(forKey: "frames")
        driveIndex = 0
        if sheetDriven { rig.alpha = 0 }
        switch anim {
        case .walk:
            if !sheetDriven { startRunCycle() }
            // Prefer walk sheet; fall back to run. Cap frames so a 29-frame loop doesn't crawl.
            let walkSrc = walkTextures.isEmpty ? runTextures : walkTextures
            let walkTrim = walkSrc.count > 16 ? Array(walkSrc.prefix(16)) : walkSrc
            playLoop(walkTrim, action: "walk", fallbackTPF: 0.05)
        case .run:
            if !sheetDriven { startRunCycle() }
            let runTrim = runTextures.count > 14 ? Array(runTextures.prefix(14)) : runTextures
            playLoop(runTrim, action: "run", fallbackTPF: 0.045)
        case .jump:
            if !sheetDriven { poseJump() }
            if jumpTextures.count > 2 {
                let ascent = Array(jumpTextures.prefix(max(2, jumpTextures.count / 2)))
                let anchors = Array((headAnchorsByAnim[.jump] ?? []).prefix(ascent.count))
                beginDrive(textures: ascent, anchors: anchors, fps: CGFloat(1.0 / tpf("jump", fallback: 0.06)), loop: false)
            } else {
                sprite.texture = jumpTex ?? idleTex
                driveTextures = []
            }
        case .apex:
            if !sheetDriven { poseApex() }
            let tex = jumpTextures.dropFirst(jumpTextures.count / 2).first ?? jumpTex ?? idleTex
            if let tex {
                sprite.texture = tex
                let anchors = headAnchorsByAnim[.apex] ?? []
                let mid = anchors.isEmpty ? 0 : min(anchors.count - 1, max(0, jumpTextures.count / 2))
                let head = anchors.isEmpty ? HeadAnchor(x: 0, y: 0.48) : anchors[mid]
                beginDrive(textures: [tex], anchors: [head], fps: 1, loop: false)
            } else {
                driveTextures = []
            }
        case .fall, .wallSlide:
            if !sheetDriven { poseFall() }
            if jumpTextures.count > 2 {
                let descent = Array(jumpTextures.suffix(max(2, jumpTextures.count / 2)))
                let all = headAnchorsByAnim[.fall] ?? []
                let anchors = Array(all.suffix(descent.count))
                beginDrive(textures: descent, anchors: anchors, fps: CGFloat(1.0 / tpf("jump", fallback: 0.08)), loop: true)
            } else {
                sprite.texture = fallTex ?? idleTex
                driveTextures = []
            }
        case .pounce:
            if !sheetDriven { posePounce() }
            if attackTextures.count > 2 {
                playOnce(attackTextures, action: "attack", fallbackTPF: 0.04)
            } else {
                sprite.texture = (flopTex ?? pounceTex) ?? idleTex
                driveTextures = []
            }
        case .hurt:
            playOnce(hurtTextures, action: "hurt", fallbackTPF: 0.04)
        case .death:
            playOnce(deathTextures, action: "death", fallbackTPF: 0.05)
        case .pickUp:
            playOnce(pickUpTextures, action: "pick_up", fallbackTPF: 0.04)
        case .slide:
            // DASH / slide burst — reuse run frames at a snappy rate when no dedicated sheet.
            if !sheetDriven { startRunCycle() }
            let slideSrc = runTextures.isEmpty ? walkTextures : runTextures
            let slideTrim = slideSrc.count > 10 ? Array(slideSrc.prefix(10)) : slideSrc
            if slideTrim.count > 1 {
                playLoop(slideTrim, action: "run", fallbackTPF: 0.035)
            } else {
                sprite.texture = runTextures.first ?? walkTextures.first ?? idleTex
                driveTextures = []
            }
        case .idle:
            if !sheetDriven { startIdleMotion() }
            playLoop(idleTextures, action: "idle", fallbackTPF: 0.12)
        }
    }

    private func stopLimbActions() {
        for n in [armF, armB, legF, legB, tail, head, torso, rig, sprite, body] as [SKNode] {
            n.removeAction(forKey: "limb")
        }
    }

    private func startIdleMotion() {
        resetLimbBases()
        head.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x: 0, y: 1.6, duration: 0.5),
            SKAction.moveBy(x: 0, y: -1.6, duration: 0.5),
        ])), withKey: "limb")
        tail.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.rotate(toAngle: 0.45, duration: 0.4),
            SKAction.rotate(toAngle: -0.35, duration: 0.4),
        ])), withKey: "limb")
        armF.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.rotate(toAngle: 0.2, duration: 0.6),
            SKAction.rotate(toAngle: -0.15, duration: 0.6),
        ])), withKey: "limb")
        armB.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.rotate(toAngle: -0.16, duration: 0.6),
            SKAction.rotate(toAngle: 0.16, duration: 0.6),
        ])), withKey: "limb")
        torso.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.group([
                SKAction.scaleX(to: 1.05, duration: 0.5),
                SKAction.scaleY(to: 0.96, duration: 0.5),
            ]),
            SKAction.group([
                SKAction.scaleX(to: 1.0, duration: 0.5),
                SKAction.scaleY(to: 1.0, duration: 0.5),
            ]),
        ])), withKey: "limb")
    }

    private func startRunCycle() {
        resetLimbBases()
        let swing: CGFloat = 1.1
        let step: TimeInterval = 0.07
        func cycle(_ node: SKNode, a: CGFloat, b: CGFloat) {
            node.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.rotate(toAngle: a, duration: step),
                SKAction.rotate(toAngle: b, duration: step),
            ])), withKey: "limb")
        }
        cycle(legF, a: swing, b: -swing)
        cycle(legB, a: -swing, b: swing)
        cycle(armF, a: -swing * 0.9, b: swing * 0.9)
        cycle(armB, a: swing * 0.9, b: -swing * 0.9)
        tail.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.rotate(toAngle: 0.75, duration: step),
            SKAction.rotate(toAngle: -0.5, duration: step),
        ])), withKey: "limb")
        torso.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x: 0, y: 3.0, duration: step),
            SKAction.moveBy(x: 0, y: -3.0, duration: step),
        ])), withKey: "limb")
        head.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x: 1.4, y: 1.8, duration: step),
            SKAction.moveBy(x: -1.4, y: -1.8, duration: step),
        ])), withKey: "limb")
        // Whole-body squash pulse so the run never reads as a static cutout.
        let face = bodyFaceScale()
        body.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.group([
                SKAction.scaleX(to: 0.9 * face, duration: step),
                SKAction.scaleY(to: 1.12, duration: step),
            ]),
            SKAction.group([
                SKAction.scaleX(to: 1.08 * face, duration: step),
                SKAction.scaleY(to: 0.9, duration: step),
            ]),
        ])), withKey: "limb")
    }

    private func poseJump() {
        resetLimbBases()
        armF.zRotation = -1.05
        armB.zRotation = 0.9
        legF.zRotation = -0.65
        legB.zRotation = -0.45
        tail.zRotation = -0.6
        torso.yScale = 1.1
        torso.xScale = 0.9
        head.position = CGPoint(x: 2, y: 22)
        tail.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.rotate(toAngle: -0.35, duration: 0.11),
            SKAction.rotate(toAngle: -0.75, duration: 0.11),
        ])), withKey: "limb")
    }

    private func poseApex() {
        resetLimbBases()
        armF.zRotation = -0.4
        armB.zRotation = 0.4
        legF.zRotation = -0.2
        legB.zRotation = 0.2
        tail.zRotation = 0.2
        torso.yScale = 0.94
        torso.xScale = 1.08
    }

    private func poseFall() {
        resetLimbBases()
        armF.zRotation = 0.9
        armB.zRotation = -0.7
        legF.zRotation = 0.55
        legB.zRotation = 0.35
        tail.zRotation = 0.7
        torso.yScale = 1.14
        torso.xScale = 0.86
        head.zRotation = -0.1
        tail.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.rotate(toAngle: 0.4, duration: 0.1),
            SKAction.rotate(toAngle: 0.9, duration: 0.1),
        ])), withKey: "limb")
    }

    private func posePounce() {
        resetLimbBases()
        armF.zRotation = 1.1
        armB.zRotation = 0.95
        legF.zRotation = 1.0
        legB.zRotation = 0.8
        tail.zRotation = 1.0
        torso.yScale = 0.78
        torso.xScale = 1.22
        head.position = CGPoint(x: 4, y: 14)
    }

    private func resetLimbBases() {
        armF.zRotation = 0; armB.zRotation = 0
        legF.zRotation = 0; legB.zRotation = 0
        tail.zRotation = 0; head.zRotation = 0
        torso.xScale = 1; torso.yScale = 1
        torso.position = CGPoint(x: 0, y: -2)
        head.position = CGPoint(x: 2, y: 20)
        armB.position = CGPoint(x: -14, y: 10)
        armF.position = CGPoint(x: 14, y: 10)
        legB.position = CGPoint(x: -8, y: -14)
        legF.position = CGPoint(x: 8, y: -14)
        tail.position = CGPoint(x: -14, y: 0)
        sprite.position = .zero
        applyFacingScale()
        body.yScale = 1
    }

    private func tickMotionTrail(anim: BanditAnim, maskMode: Bool, dt: CGFloat, smokeLite: Bool) {
        let moving = maskMode || anim == .run || anim == .walk || anim == .pounce || anim == .jump || anim == .apex
        guard moving else { return }
        trailAcc += dt
        // Space Mask afterimages by travel (~velocity × 0.05s), not every frame — avoids cyan smear.
        let interval: CGFloat = {
            if maskMode { return smokeLite ? 0.12 : 0.09 }
            return smokeLite ? 0.14 : 0.09
        }()
        guard trailAcc >= interval else { return }
        trailAcc = 0
        emitPooledTrail(maskMode: maskMode, dash: anim == .pounce)
    }

    public func emitMaskTrail() {
        emitPooledTrail(maskMode: true, dash: false)
    }

    /// Mask Mode entry: LED pulse + 3 spaced afterimages (0.45 / 0.25 / 0.12).
    public func flashMaskEntry() {
        maskGlow.isHidden = false
        maskGlow.alpha = 1
        maskGlow.removeAllActions()
        maskGlow.setScale(1)
        maskGlow.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 1.35, duration: 0.08),
                SKAction.fadeAlpha(to: 1, duration: 0.05),
            ]),
            SKAction.scale(to: 1.0, duration: 0.12),
        ]))
        let alphas: [CGFloat] = [0.45, 0.25, 0.12]
        for i in 0..<3 {
            guard let tex = sprite.texture else { continue }
            let ghost = SKSpriteNode(texture: tex, size: sprite.size)
            ghost.anchorPoint = sprite.anchorPoint
            let spacing = CGFloat(22 + i * 28)
            ghost.position = CGPoint(x: -facingSign * spacing, y: 0)
            ghost.zPosition = -0.4 - CGFloat(i) * 0.05
            ghost.alpha = alphas[i]
            ghost.color = ArtCatalog.neonCyan
            ghost.colorBlendFactor = 0.5
            ghost.xScale = bodyFaceScale()
            addChild(ghost)
            ghost.run(SKAction.sequence([
                SKAction.group([
                    SKAction.fadeOut(withDuration: 0.34),
                    SKAction.moveBy(x: -facingSign * 14, y: 0, duration: 0.34),
                ]),
                SKAction.removeFromParent(),
            ]))
        }
    }

    private func emitPooledTrail(maskMode: Bool, dash: Bool) {
        guard !trailPool.isEmpty else { return }
        let speck = trailPool[trailCursor % trailPool.count]
        trailCursor += 1
        speck.removeAllActions()
        let face: CGFloat = facingSign
        // Raccoon-silhouette afterimage (current sheet frame), not a rectangle speck.
        speck.texture = sprite.texture ?? idleTex
        speck.size = sprite.size
        speck.anchorPoint = sprite.anchorPoint
        speck.xScale = bodyFaceScale()
        speck.yScale = 1
        let slot = (trailCursor - 1) % 3
        let spacing = maskMode ? CGFloat(24 + slot * 22) : CGFloat(14 + slot * 10)
        let alphas: [CGFloat] = maskMode ? [0.45, 0.25, 0.12] : [0.28, 0.18, 0.10]
        speck.position = CGPoint(x: -face * spacing, y: dash ? 1 : 0)
        speck.zRotation = 0
        speck.color = maskMode ? ArtCatalog.neonCyan : ArtCatalog.neonPink
        speck.colorBlendFactor = maskMode ? 0.75 : 0.65
        speck.alpha = alphas[slot]
        speck.isHidden = false
        let drift = -face * (maskMode ? 28 : 18)
        let life: TimeInterval = maskMode ? 0.32 : 0.2
        let endScaleX = bodyFaceScale() * (maskMode ? 0.9 : 0.75)
        speck.run(SKAction.sequence([
            SKAction.group([
                SKAction.fadeOut(withDuration: life),
                SKAction.scaleX(to: endScaleX, y: maskMode ? 1.02 : 0.9, duration: life),
                SKAction.moveBy(x: drift, y: 0, duration: life),
            ]),
            SKAction.run { speck.isHidden = true; speck.alpha = 0 },
        ]))
    }
}
#endif
