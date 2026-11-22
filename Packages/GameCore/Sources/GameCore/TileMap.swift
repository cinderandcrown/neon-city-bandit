// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import Foundation

public enum Tile: UInt8, Equatable, Sendable {
    case empty = 0
    case ground = 1
    case wall = 2
    case water = 3
    case crate = 4
    case spike = 5
    case checkpoint = 6
    case stash = 7
    case shinySpawn = 8
    case mopSpawn = 9
    case start = 10
    case exit = 11
    case latch = 12
    /// Jump-through from below; solid only when landing from above. Drop through by holding down.
    case oneWay = 13
    /// Caged crew member — exploration rescue beat.
    case crewCage = 14
}

public struct TileMap: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let tiles: [Tile]

    public init(width: Int, height: Int, tiles: [Tile]) {
        precondition(tiles.count == width * height)
        self.width = width
        self.height = height
        self.tiles = tiles
    }

    public func tile(atX x: Int, y: Int) -> Tile {
        guard x >= 0, y >= 0, x < width, y < height else { return .wall }
        return tiles[y * width + x]
    }

    public func worldCenter(ofX x: Int, y: Int, tileSize: Double) -> Vec2 {
        Vec2((Double(x) + 0.5) * tileSize, (Double(y) + 0.5) * tileSize)
    }

    /// Snap spawn markers (MOP) so feet sit on the solid tile top below the marker cell.
    /// Tile y grows upward; "below" means decreasing y.
    public func worldStandOnDeckBelow(ofX x: Int, markerY y: Int, tileSize: Double) -> Vec2 {
        var scan = y - 1
        while scan >= 0 {
            let t = tile(atX: x, y: scan)
            if isSolid(t) {
                let footY = Double(scan + 1) * tileSize
                return Vec2((Double(x) + 0.5) * tileSize, footY)
            }
            scan -= 1
        }
        return worldCenter(ofX: x, y: y, tileSize: tileSize)
    }

    public func isSolid(_ tile: Tile) -> Bool {
        switch tile {
        case .ground, .wall, .crate, .latch: return true
        // oneWay is NOT universally solid — Sim collide treats it as land-only.
        default: return false
        }
    }

    /// Tops the bandit can stand on (including one-ways).
    public func isStandable(_ tile: Tile) -> Bool {
        switch tile {
        case .ground, .wall, .crate, .latch, .oneWay: return true
        default: return false
        }
    }

    public func findFirst(_ kind: Tile) -> (Int, Int)? {
        for y in 0..<height {
            for x in 0..<width where tile(atX: x, y: y) == kind {
                return (x, y)
            }
        }
        return nil
    }

    public func findAll(_ kind: Tile) -> [(Int, Int)] {
        var out: [(Int, Int)] = []
        for y in 0..<height {
            for x in 0..<width where tile(atX: x, y: y) == kind {
                out.append((x, y))
            }
        }
        return out
    }

    /// Side-view legend (row 0 = bottom).
    /// `#` wall/ground  `.` air  `=` solid platform  `-` one-way  `~` water  `^` spike
    /// `C` crate  `P` checkpoint  `S` stash  `*` shiny  `M` MOP  `@` start  `E` exit
    /// `L` latch/pole  `R` crew cage
    public static func parse(_ ascii: String) throws -> TileMap {
        let rows = ascii.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
        guard let width = rows.first?.count, width > 0 else { throw MapError.empty }
        guard rows.allSatisfy({ $0.count == width }) else { throw MapError.ragged }
        var tiles: [Tile] = []
        tiles.reserveCapacity(width * rows.count)
        for row in rows.reversed() {
            for ch in row {
                tiles.append(try tile(from: ch))
            }
        }
        return TileMap(width: width, height: rows.count, tiles: tiles)
    }

    private static func tile(from ch: Character) throws -> Tile {
        switch ch {
        case ".", " ": return .empty
        case "#", "=": return .ground
        case "-": return .oneWay
        case "|": return .wall
        case "~": return .water
        case "^": return .spike
        case "C": return .crate
        case "P": return .checkpoint
        case "S": return .stash
        case "*": return .shinySpawn
        case "M": return .mopSpawn
        case "@": return .start
        case "E": return .exit
        case "L": return .latch
        case "R": return .crewCage
        default: throw MapError.unknown(ch)
        }
    }

    public enum MapError: Error, Equatable {
        case empty, ragged, unknown(Character)
    }
}

/// Downtown Heist 1 — short auto-runner (~60–90s) with a beat every 2–3s ending at the vault.
public enum NeonDocksLevel {
    /// Downtown Heist 1 — teaching runway, then a dense street MOP pack, short end hop to vault.
    /// Closed solid under/past the vault so finish can't fall into the void.
    public static let ascii = """
    ################################################################
    #..............................................................#
    #..............................................................#
    #............................*..........*......................#
    #......................................====....................#
    #............................----..............................#
    #.@......................*.M.M.M.M.P.M.M.M.M.*.R.M.M.*.M...E####
    #############################################====###############
    #############################################~~~~###############
    ################################################################
    ################################################################
"""

    public static func load() throws -> TileMap {
        try TileMap.parse(ascii)
    }
}

public enum SmokeDemoLevel {
    /// Compact rooftop route: continuous deck, canal pit, EXIT.
    /// Floating `====` ledges are collision platforms only — HeistScene draws pipes/scaffolds under them.
    /// A short `||` pillar gives the midrun wall-slide beat without climbable stilts trapping finishPush.
    public static let ascii = """
    ##################################################
    #................................................#
    #......====....====..............==....====......#
    #................||..............................#
    #...*............||.*...........*.......*........#
    #........@.*.M.*.M.*.M.*P.................*....E.#
    #=======================..=======================#
    #.......................~~.......................#
    ##################################################
    """

    public static func load() throws -> TileMap {
        try TileMap.parse(ascii)
    }
}






public enum ArcadeRowLevel {
    /// Heist 2 — denser Downtown after a safe open runway.
    public static let ascii = """
    ################################################################
    #..............................................................#
    #............................*.....*.....*.....................#
    #..........................====...====...====..................#
    #..............................................................#
    #.@......................M.*.M.*.P.M.*.M.*.M.P.*.M.R...E.......#
    ############################...#####...#####...###...###########
    ############################~~~#####~~~#####~~~###~~~###########
    #..................----............----........................#
    ################################################################
"""

    public static func load() throws -> TileMap {
        try TileMap.parse(ascii)
    }
}

public enum RooftopsLevel {
    /// Heist 3 — rooftop pressure after a safe open runway.
    public static let ascii = """
    ################################################################
    #..............................*........*........*.............#
    #............................====......====......====..........#
    #......................*.......................................#
    #....................====....*....====....*....................#
    #.@.....................M.*.M.P.*.M.*.M.*.M.P.*.M.R...E........#
    ###########################...#####...#####...###...############
    ###########################~~~#####~~~#####~~~###~~~############
    #................----..........----..........----..............#
    ################################################################
"""

    public static func load() throws -> TileMap {
        try TileMap.parse(ascii)
    }
}

public enum SewerGridLevel {
    public static let ascii = """
    ################################################################################################
    #..............................................................................................#
    #..............................................................................................#
    #.............................*..*....*........................................................#
    #..........................===============...*.................................................#
    #...........................L.----.........======...*..........*...............................#
    #...........................L.....................=================............................#
    #...........................L.----..........................=.....=..M*........................#
    #...........................L...............................=.....=.=====...*S.................#
    #...........................L.----..........................=.....=.......=====..P*............#
    #...........................L...............................=======.............=====..........#
    #.........*.................L.----..........*.M.............=======............................#
    #.......=====...............L...........========............=======..................----......#
    #...........===.CCC*........L.----.====.....................=======....................----....#
    #..............========.....L.----...................----...=======......................---*-.#
    #.......................====..........................====..=======.......................=====#
    #..@....M.M.M.M.*.*.P.M.M.M.*.M...M.*.M....*..........M.*.M...M.....M...*.M.....M.......S.P.E..#
    #############################################....###############################################
    #######################################......~~~################################################
    #######################################.R.*..~~~################################################
    #######################################=========################################################
    ################################################################################################
    ################################################################################################
    ################################################################################################
    """

    public static func load() throws -> TileMap {
        try TileMap.parse(ascii)
    }
}

public enum DistrictLevels {
    public static func load(_ id: DistrictID) throws -> TileMap {
        switch id {
        case .neonDocks: return try NeonDocksLevel.load()
        case .arcadeRow: return try ArcadeRowLevel.load()
        case .rooftops: return try RooftopsLevel.load()
        case .sewerGrid: return try SewerGridLevel.load()
        }
    }
}
