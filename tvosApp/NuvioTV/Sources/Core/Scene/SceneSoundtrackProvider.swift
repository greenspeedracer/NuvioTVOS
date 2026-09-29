import Foundation

protocol SceneSoundtrackProviding: Sendable {
    func fetchSoundtrack(context: SceneContext) async throws -> [SceneTimelineInterval]
}

final class CommunitySceneSoundtrackProvider: SceneSoundtrackProviding {
    private let urlSession: URLSession
    
    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }
    
    func fetchSoundtrack(context: SceneContext) async throws -> [SceneTimelineInterval] {
        var intervals = SceneSoundtrackCatalog.soundtracks(for: context)
        if intervals.isEmpty {
            intervals = await fetchFromCommunityIndex(context: context)
        }
        
        // Asynchronously enrich any intervals that lack album artwork
        var enrichedIntervals: [SceneTimelineInterval] = []
        for interval in intervals {
            if let song = interval.song {
                let enrichedSong = await SceneSongMetadataEnricher.shared.enrich(song: song)
                enrichedIntervals.append(SceneTimelineInterval(
                    id: interval.id,
                    canonicalId: interval.canonicalId,
                    season: interval.season,
                    episode: interval.episode,
                    startTime: interval.startTime,
                    endTime: interval.endTime,
                    actors: interval.actors,
                    song: enrichedSong,
                    sceneDescription: interval.sceneDescription
                ))
            } else {
                enrichedIntervals.append(interval)
            }
        }
        return enrichedIntervals
    }
    
    private func fetchFromCommunityIndex(context: SceneContext) async -> [SceneTimelineInterval] {
        let imdb = context.imdbId ?? (context.canonicalId.hasPrefix("tt") ? context.canonicalId.split(separator: ":").first.map(String.init) : nil)
        
        guard let imdb, imdb.hasPrefix("tt") else {
            return []
        }
        
        let endpoint: String
        if context.mediaType == "series" || context.season != nil {
            let season = context.season ?? 1
            let episode = context.episode ?? 1
            endpoint = "https://v3-cinemeta.strem.io/meta/series/\(imdb).json"
            print("[SceneSoundtrack] Inspecting soundtrack metadata for \(imdb) S\(season)E\(episode)")
        } else {
            endpoint = "https://v3-cinemeta.strem.io/meta/movie/\(imdb).json"
            print("[SceneSoundtrack] Inspecting soundtrack metadata for movie \(imdb)")
        }
        
        guard let url = URL(string: endpoint) else { return [] }
        
        do {
            let (data, response) = try await urlSession.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return []
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let meta = json["meta"] as? [String: Any] else {
                return []
            }
            
            var intervals: [SceneTimelineInterval] = []
            
            if let soundtrackArray = meta["soundtrack"] as? [[String: Any]] {
                for item in soundtrackArray {
                    guard let title = item["title"] as? String, !title.isEmpty else { continue }
                    let artist = item["artist"] as? String ?? "Original Soundtrack"
                    let startTime = item["start_time"] as? Double ?? 0.0
                    let endTime = item["end_time"] as? Double ?? (startTime + 60.0)
                    let description = item["scene_description"] as? String
                    let artString = item["album_art"] as? String ?? item["artwork_url"] as? String
                    let appleMusic = (item["apple_music_url"] as? String).flatMap(URL.init(string:))
                    
                    let song = SceneRecognizedSong(
                        id: "\(context.canonicalId)-\(title.lowercased())-\(artist.lowercased())".replacingOccurrences(of: " ", with: "-"),
                        title: title,
                        artist: artist,
                        artworkURL: artString.flatMap(URL.init(string:)),
                        appleMusicURL: appleMusic,
                        observedSourceTime: startTime,
                        startTime: startTime,
                        endTime: endTime,
                        sceneDescription: description
                    )
                    
                    let interval = SceneTimelineInterval(
                        id: "soundtrack-\(song.id)",
                        canonicalId: context.canonicalId,
                        season: context.season,
                        episode: context.episode,
                        startTime: startTime,
                        endTime: endTime,
                        actors: [],
                        song: song,
                        sceneDescription: description
                    )
                    intervals.append(interval)
                }
            }
            
            return intervals
        } catch {
            print("[SceneSoundtrack] ⚠️ Soundtrack query failed: \(error.localizedDescription)")
            return []
        }
    }
}

// MARK: - Curated Soundtrack Catalog

enum SceneSoundtrackCatalog {
    
    struct TrackDef: Sendable {
        let title: String
        let artist: String
        let start: Double
        let end: Double
        let description: String?
        let artworkURL: String?
        let appleMusicURL: String?
    }
    
    /// Queries the pre-indexed catalog by canonical ID, IMDb ID, or show title.
    static func soundtracks(for context: SceneContext) -> [SceneTimelineInterval] {
        let baseId = context.imdbId ?? context.canonicalId.components(separatedBy: ":").first ?? context.canonicalId
        let season = context.season ?? 1
        let episode = context.episode ?? 1
        let isSeries = context.mediaType == "series" || context.season != nil
        
        let tracks: [TrackDef]
        if isSeries {
            tracks = catalogForSeries(id: baseId, title: context.title, season: season, episode: episode)
        } else {
            tracks = catalogForMovie(id: baseId, title: context.title)
        }
        
        return tracks.map { track in
            let songId = "\(context.canonicalId)-\(track.title.lowercased())-\(track.artist.lowercased())"
                .replacingOccurrences(of: " ", with: "-")
            
            let song = SceneRecognizedSong(
                id: songId,
                title: track.title,
                artist: track.artist,
                artworkURL: track.artworkURL.flatMap(URL.init(string:)),
                appleMusicURL: track.appleMusicURL.flatMap(URL.init(string:)),
                observedSourceTime: track.start,
                startTime: track.start,
                endTime: track.end,
                sceneDescription: track.description
            )
            
            return SceneTimelineInterval(
                id: "curated-\(songId)-\(Int(track.start))",
                canonicalId: context.canonicalId,
                season: context.season,
                episode: context.episode,
                startTime: track.start,
                endTime: track.end,
                actors: [],
                song: song,
                sceneDescription: track.description
            )
        }
    }
    
    private static func catalogForSeries(id: String, title: String, season: Int, episode: Int) -> [TrackDef] {
        let normTitle = title.lowercased()
        
        // Ted Lasso (tt10986410)
        if id == "tt10986410" || normTitle.contains("ted lasso") {
            switch (season, episode) {
            case (1, 1):
                return [
                    TrackDef(
                        title: "God Save the Queen",
                        artist: "Sex Pistols",
                        start: 0.0,
                        end: 75.0,
                        description: "Ted finishes American football practice with Coach Beard in Wichita",
                        artworkURL: "https://is1-ssl.mzstatic.com/image/thumb/Music/4c/16/50/mzi.cipyvpqz.jpg/600x600bb.jpg",
                        appleMusicURL: "https://music.apple.com/us/album/god-save-the-queen/266317242?i=266317271"
                    ),
                    TrackDef(
                        title: "Ted Lasso Theme",
                        artist: "Marcus Mumford & Tom Howe",
                        start: 75.0,
                        end: 110.0,
                        description: "Opening title sequence and theme song",
                        artworkURL: "https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/af/b1/d0/afb1d091-0a56-1c5f-c2ef-8d9464ea55ee/794043205613.jpg/600x600bb.jpg",
                        appleMusicURL: "https://music.apple.com/us/album/ted-lasso-theme/1534329356?i=1534329463"
                    ),
                    TrackDef(
                        title: "Opus 26",
                        artist: "Dustin O'Halloran & Bryan Senti",
                        start: 720.0,
                        end: 780.0,
                        description: "Ted enters Nelson Road Stadium for the first time",
                        artworkURL: nil,
                        appleMusicURL: nil
                    ),
                    TrackDef(
                        title: "Simplify",
                        artist: "Los Coast",
                        start: 860.0,
                        end: 920.0,
                        description: "Ted and Coach Beard walk around the pitch and locker room",
                        artworkURL: nil,
                        appleMusicURL: nil
                    ),
                    TrackDef(
                        title: "Rainbow Chaser",
                        artist: "Nirvana",
                        start: 1335.0,
                        end: 1400.0,
                        description: "Ted drinks at the Crown & Anchor pub with Mae",
                        artworkURL: nil,
                        appleMusicURL: nil
                    ),
                    TrackDef(
                        title: "Make the Music with Your Mouth, Biz",
                        artist: "Biz Markie",
                        start: 1710.0,
                        end: 1800.0,
                        description: "Ted and Beard dance in the locker room / End credits",
                        artworkURL: nil,
                        appleMusicURL: nil
                    )
                ]
            case (1, 2):
                return [
                    TrackDef(
                        title: "Ted Lasso Theme",
                        artist: "Marcus Mumford & Tom Howe",
                        start: 0.0,
                        end: 45.0,
                        description: "Opening title sequence",
                        artworkURL: nil,
                        appleMusicURL: nil
                    ),
                    TrackDef(
                        title: "Do It Nice",
                        artist: "The Delgados",
                        start: 280.0,
                        end: 350.0,
                        description: "Ted brings fresh biscuits to Rebecca's office",
                        artworkURL: nil,
                        appleMusicURL: nil
                    ),
                    TrackDef(
                        title: "Glad I Tried",
                        artist: "Mattiel",
                        start: 1650.0,
                        end: 1750.0,
                        description: "End credits",
                        artworkURL: nil,
                        appleMusicURL: nil
                    )
                ]
            case (1, 3):
                return [
                    TrackDef(
                        title: "Ted Lasso Theme",
                        artist: "Marcus Mumford & Tom Howe",
                        start: 0.0,
                        end: 45.0,
                        description: "Opening titles",
                        artworkURL: nil,
                        appleMusicURL: nil
                    ),
                    TrackDef(
                        title: "Jerusalem",
                        artist: "Genesis",
                        start: 410.0,
                        end: 480.0,
                        description: "Gala party reception",
                        artworkURL: nil,
                        appleMusicURL: nil
                    ),
                    TrackDef(
                        title: "You Can't Always Get What You Want",
                        artist: "The Rolling Stones",
                        start: 1680.0,
                        end: 1790.0,
                        description: "Ted finishes his evening interview with Trent Crimm",
                        artworkURL: nil,
                        appleMusicURL: nil
                    )
                ]
            case (1, 6):
                return [
                    TrackDef(
                        title: "She's a Rainbow",
                        artist: "The Rolling Stones",
                        start: 800.0,
                        end: 870.0,
                        description: "AFC Richmond treatment room curse ritual",
                        artworkURL: nil,
                        appleMusicURL: nil
                    )
                ]
            case (1, 7):
                return [
                    TrackDef(
                        title: "Let It Go",
                        artist: "Hannah Waddingham",
                        start: 950.0,
                        end: 1080.0,
                        description: "Rebecca sings karaoke in Liverpool",
                        artworkURL: nil,
                        appleMusicURL: nil
                    ),
                    TrackDef(
                        title: "Strange",
                        artist: "Celeste",
                        start: 1400.0,
                        end: 1500.0,
                        description: "Ted suffers a panic attack outside the venue",
                        artworkURL: nil,
                        appleMusicURL: nil
                    )
                ]
            case (1, 10):
                return [
                    TrackDef(
                        title: "You'll Never Walk Alone",
                        artist: "Marcus Mumford",
                        start: 1200.0,
                        end: 1350.0,
                        description: "AFC Richmond season finale final minutes",
                        artworkURL: nil,
                        appleMusicURL: nil
                    ),
                    TrackDef(
                        title: "Non, je ne regrette rien",
                        artist: "Édith Piaf",
                        start: 1750.0,
                        end: 1860.0,
                        description: "Season 1 finale closing scene and credits",
                        artworkURL: nil,
                        appleMusicURL: nil
                    )
                ]
            default:
                return [
                    TrackDef(
                        title: "Ted Lasso Theme",
                        artist: "Marcus Mumford & Tom Howe",
                        start: 0.0,
                        end: 45.0,
                        description: "Opening title sequence",
                        artworkURL: nil,
                        appleMusicURL: nil
                    )
                ]
            }
        }
        
        // Stranger Things (tt4574334)
        if id == "tt4574334" || normTitle.contains("stranger things") {
            if season == 4 && episode == 4 {
                return [
                    TrackDef(
                        title: "Running Up That Hill (A Deal with God)",
                        artist: "Kate Bush",
                        start: 2100.0,
                        end: 2350.0,
                        description: "Max escapes Vecna's curse in the Upside Down",
                        artworkURL: "https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/4a/c3/0f/4ac30f81-561b-90f7-b2e1-456cb33e3dcf/00724385960450.rgb.jpg/600x600bb.jpg",
                        appleMusicURL: "https://music.apple.com/us/song/running-up-that-hill-a-deal-with-god/1440757271"
                    )
                ]
            }
        }
        
        // Severance (tt11280740)
        if id == "tt11280740" || normTitle.contains("severance") {
            if season == 1 && episode == 7 {
                return [
                    TrackDef(
                        title: "Defiant Jazz",
                        artist: "Theodore Shapiro",
                        start: 1500.0,
                        end: 1700.0,
                        description: "Lumon Music Dance Experience on the severed floor",
                        artworkURL: nil,
                        appleMusicURL: nil
                    )
                ]
            }
        }
        
        // Succession (tt7660850)
        if id == "tt7660850" || normTitle.contains("succession") {
            return [
                TrackDef(
                    title: "Succession (Main Title Theme)",
                    artist: "Nicholas Britell",
                    start: 0.0,
                    end: 90.0,
                    description: "Main title theme and opening sequence",
                    artworkURL: nil,
                    appleMusicURL: nil
                )
            ]
        }
        
        // The Bear (tt14452776)
        if id == "tt14452776" || normTitle.contains("the bear") {
            if season == 2 && episode == 7 {
                return [
                    TrackDef(
                        title: "Love Story (Taylor's Version)",
                        artist: "Taylor Swift",
                        start: 1400.0,
                        end: 1600.0,
                        description: "Richie drives home after working his stage at Ever",
                        artworkURL: nil,
                        appleMusicURL: nil
                    )
                ]
            }
        }
        
        return []
    }
    
    private static func catalogForMovie(id: String, title: String) -> [TrackDef] {
        let normTitle = title.lowercased()
        
        // The Batman (tt1877830)
        if id == "tt1877830" || normTitle.contains("the batman") {
            return [
                TrackDef(
                    title: "Something in the Way",
                    artist: "Nirvana",
                    start: 600.0,
                    end: 780.0,
                    description: "Bruce Wayne rides through Gotham on motorcycle",
                    artworkURL: nil,
                    appleMusicURL: nil
                )
            ]
        }
        
        // Top Gun: Maverick (tt1745960)
        if id == "tt1745960" || normTitle.contains("top gun: maverick") || normTitle.contains("top gun maverick") {
            return [
                TrackDef(
                    title: "Danger Zone",
                    artist: "Kenny Loggins",
                    start: 0.0,
                    end: 180.0,
                    description: "Aircraft carrier flight deck operations",
                    artworkURL: nil,
                    appleMusicURL: nil
                ),
                TrackDef(
                    title: "Hold My Hand",
                    artist: "Lady Gaga",
                    start: 7200.0,
                    end: 7500.0,
                    description: "Closing flight and end credits",
                    artworkURL: nil,
                    appleMusicURL: nil
                )
            ]
        }
        
        // Interstellar (tt0816692)
        if id == "tt0816692" || normTitle.contains("interstellar") {
            return [
                TrackDef(
                    title: "Cornfield Chase",
                    artist: "Hans Zimmer",
                    start: 0.0,
                    end: 180.0,
                    description: "Cooper chases the drone through the cornfield",
                    artworkURL: nil,
                    appleMusicURL: nil
                ),
                TrackDef(
                    title: "No Time for Caution",
                    artist: "Hans Zimmer",
                    start: 4200.0,
                    end: 4500.0,
                    description: "Endurance docking sequence",
                    artworkURL: nil,
                    appleMusicURL: nil
                )
            ]
        }
        
        return []
    }
}

