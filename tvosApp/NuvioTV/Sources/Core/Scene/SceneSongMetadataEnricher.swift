import Foundation

actor SceneSongMetadataEnricher {
    static let shared = SceneSongMetadataEnricher()
    
    private let urlSession: URLSession
    private var cache: [String: SceneRecognizedSong] = [:]
    
    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }
    
    /// Asynchronously enriches a song with live album artwork, Apple Music URL, and genre from the free iTunes Search API.
    func enrich(song: SceneRecognizedSong) async -> SceneRecognizedSong {
        if let cached = cache[song.id], cached.artworkURL != nil {
            return cached
        }
        
        if song.artworkURL != nil {
            cache[song.id] = song
            return song
        }
        
        let query = "\(song.artist) \(song.title)"
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "Original Soundtrack", with: "")
            .replacingOccurrences(of: "Scene Music", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !query.isEmpty,
              let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&entity=song&limit=1") else {
            return song
        }
        
        do {
            let (data, response) = try await urlSession.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return song
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  let first = results.first else {
                return song
            }
            
            var artworkURL: URL? = nil
            if let art100 = first["artworkUrl100"] as? String {
                let highRes = art100.replacingOccurrences(of: "100x100bb.jpg", with: "600x600bb.jpg")
                artworkURL = URL(string: highRes) ?? URL(string: art100)
            }
            
            let appleMusicURL = (first["trackViewUrl"] as? String).flatMap(URL.init(string:))
            let genre = first["primaryGenreName"] as? String
            var genres = song.genres
            if let genre, !genres.contains(genre) {
                genres.append(genre)
            }
            
            let enriched = SceneRecognizedSong(
                id: song.id,
                title: song.title,
                artist: (song.artist == "Original Soundtrack" || song.artist == "Scene Music")
                    ? (first["artistName"] as? String ?? song.artist)
                    : song.artist,
                artworkURL: artworkURL ?? song.artworkURL,
                appleMusicURL: appleMusicURL ?? song.appleMusicURL,
                shazamURL: song.shazamURL,
                genres: genres,
                observedSourceTime: song.observedSourceTime,
                startTime: song.startTime,
                endTime: song.endTime,
                sceneDescription: song.sceneDescription
            )
            
            cache[song.id] = enriched
            print("[SceneMetadata] 🎨 Enriched artwork for \"\(enriched.title)\" by \(enriched.artist): \(artworkURL?.absoluteString ?? "none")")
            return enriched
        } catch {
            print("[SceneMetadata] ⚠️ Failed to enrich metadata for \(song.title): \(error.localizedDescription)")
            return song
        }
    }
}
