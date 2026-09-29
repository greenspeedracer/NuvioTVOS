import Foundation

actor SceneResultCache {
    private struct CacheKey: Hashable {
        let canonicalId: String
        let season: Int?
        let episode: Int?
        let timeBucket: Int // 5-second window
    }
    
    private struct CacheEntry {
        let snapshot: SceneSnapshot
        let recordedAt: Date
    }
    
    // Dynamic local bucket observations
    private var entries: [CacheKey: CacheEntry] = [:]
    
    // Pre-indexed or verified Scene Timeline intervals (start - end time ranges)
    private var timelineIntervalsByTitle: [String: [SceneTimelineInterval]] = [:]
    
    private let maxEntries: Int = 200
    private let bucketSizeSeconds: Double = 5.0
    
    init() {}
    
    // MARK: - Scene Timeline Database Querying & Storage
    
    /// Queries the scene timeline database for verified actor and song appearances
    /// across exact time ranges (e.g. 00:45:31 - 00:46:07 -> Robert Pattinson).
    func findTimelineInterval(for context: SceneContext, sourceTime: Double) -> SceneTimelineInterval? {
        let lists = candidateIntervalLists(for: context)
        for list in lists {
            if let match = list.first(where: { interval in
                if let season = context.season, let intervalSeason = interval.season, season != intervalSeason {
                    return false
                }
                if let episode = context.episode, let intervalEpisode = interval.episode, episode != intervalEpisode {
                    return false
                }
                return interval.contains(timestamp: sourceTime)
            }) {
                return match
            }
        }
        return nil
    }
    
    /// Queries the scene timeline database for an active song at the specified source time.
    func findTimelineSong(for context: SceneContext, sourceTime: Double) -> SceneRecognizedSong? {
        let lists = candidateIntervalLists(for: context)
        for list in lists {
            for interval in list {
                if let season = context.season, let intervalSeason = interval.season, season != intervalSeason {
                    continue
                }
                if let episode = context.episode, let intervalEpisode = interval.episode, episode != intervalEpisode {
                    continue
                }
                if interval.contains(timestamp: sourceTime), let song = interval.song {
                    return song
                }
                if let song = interval.song, song.isActive(at: sourceTime) {
                    return song
                }
            }
        }
        return nil
    }
    
    /// Returns all soundtrack timeline intervals for the given media context.
    func allTimelineSongs(for context: SceneContext) -> [SceneTimelineInterval] {
        var results: [SceneTimelineInterval] = []
        var seenSongIds: Set<String> = []
        
        let lists = candidateIntervalLists(for: context)
        for list in lists {
            for interval in list {
                if let season = context.season, let intervalSeason = interval.season, season != intervalSeason {
                    continue
                }
                if let episode = context.episode, let intervalEpisode = interval.episode, episode != intervalEpisode {
                    continue
                }
                guard let song = interval.song else { continue }
                if seenSongIds.insert(song.id).inserted {
                    results.append(interval)
                }
            }
        }
        return results
    }
    
    private func candidateIntervalLists(for context: SceneContext) -> [[SceneTimelineInterval]] {
        var keys: [String] = [context.canonicalId]
        if let imdb = context.imdbId {
            keys.append(imdb)
        }
        let baseId = context.canonicalId.components(separatedBy: ":").first ?? context.canonicalId
        if !keys.contains(baseId) {
            keys.append(baseId)
        }
        if !keys.contains(context.title) {
            keys.append(context.title)
        }
        return keys.compactMap { timelineIntervalsByTitle[$0] }
    }
    
    /// Stores or imports verified timeline intervals.
    func storeTimelineInterval(_ interval: SceneTimelineInterval) {
        var list = timelineIntervalsByTitle[interval.canonicalId] ?? []
        list.removeAll { $0.id == interval.id }
        list.append(interval)
        timelineIntervalsByTitle[interval.canonicalId] = list
    }
    
    /// Batch stores verified timeline intervals.
    func storeTimelineIntervals(_ intervals: [SceneTimelineInterval]) {
        for interval in intervals {
            storeTimelineInterval(interval)
        }
    }
    
    // MARK: - Dynamic Snapshot Bucket Cache
    
    func snapshot(for context: SceneContext, sourceTime: Double) -> SceneSnapshot? {
        let key = makeKey(context: context, sourceTime: sourceTime)
        guard let entry = entries[key] else { return nil }
        
        // Expire dynamic observations older than 30 minutes
        if Date().timeIntervalSince(entry.recordedAt) > 1800 {
            entries.removeValue(forKey: key)
            return nil
        }
        return entry.snapshot
    }
    
    func store(snapshot: SceneSnapshot, context: SceneContext, sourceTime: Double) {
        if entries.count >= maxEntries {
            if let oldestKey = entries.min(by: { $0.value.recordedAt < $1.value.recordedAt })?.key {
                entries.removeValue(forKey: oldestKey)
            }
        }
        let key = makeKey(context: context, sourceTime: sourceTime)
        entries[key] = CacheEntry(snapshot: snapshot, recordedAt: Date())
    }
    
    func invalidate(for canonicalId: String) {
        entries = entries.filter { $0.key.canonicalId != canonicalId }
        timelineIntervalsByTitle.removeValue(forKey: canonicalId)
    }
    
    func clear() {
        entries.removeAll()
        timelineIntervalsByTitle.removeAll()
    }
    
    private func makeKey(context: SceneContext, sourceTime: Double) -> CacheKey {
        let bucket = Int(max(0, sourceTime) / bucketSizeSeconds)
        return CacheKey(
            canonicalId: context.canonicalId,
            season: context.season,
            episode: context.episode,
            timeBucket: bucket
        )
    }
}
