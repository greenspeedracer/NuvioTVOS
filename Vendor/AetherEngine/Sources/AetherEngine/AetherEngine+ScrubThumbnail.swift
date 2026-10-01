import Foundation
import CoreGraphics

extension AetherEngine {

    /// The 2026-09-02 Whole Title trace opened 30 software decoders in 20 seconds while
    /// scrubbing three resident 100 MB segments and back. Six keeps that small working set
    /// warm; each extractor maps its segment file (audit SEG-2), so the entries hold clean
    /// file-backed pages rather than heap copies, and the bound remains fixed.
    nonisolated static let scrubThumbnailExtractorLimit = 6

    /// Cache-backed scrub still for the active native session (live or VOD). Decodes from
    /// already-produced SegmentCache bytes, so it never opens a second connection and works
    /// on single-connection sources (debrid/torrent HTTP links, #106) where the
    /// FrameExtractor's second demuxer is refused. Returns nil when there is no native
    /// session, the segment is not resident (not yet produced far ahead of the playhead, or
    /// evicted past the retention budget), or decode fails; a nil is the correct
    /// "not available yet" and hosts show time-only.  is session-timeline
    /// (seekableLiveRange axis) for live, playlist/output seconds for VOD.
    public func scrubThumbnail(
        atSeconds seconds: Double,
        maxWidth: Int = 320,
        precise: Bool = true
    ) async -> CGImage? {
        if isLive {
            return await liveScrubThumbnail(atSessionSeconds: seconds, maxWidth: maxWidth)
        }
        return await vodScrubThumbnail(atSeconds: seconds, maxWidth: maxWidth, precise: precise)
    }

    /// VOD arm of `scrubThumbnail`. `!isLive` guards direct callers: `nativeVideoSession` is
    /// non-nil for live too, and `scrubThumbnailSource` no longer self-gates on isLiveSession,
    /// so a VOD decode must not run against a live session (whose seam-shift axis differs).
    /// Hands the extractor exactly one segment (init + the seg containing `seconds`) and seeks
    /// to 0: thumbnail mode returns the first frame after the seek, so 0 lands on that segment's
    /// first keyframe whether its fMP4 tfdt is absolute or zero-based (post-restart). This makes
    /// the decode axis-independent and correct by construction. Per-segment granularity.
    ///
    /// A software session (AE#605) has no segments; it decodes the still out of the packet cache
    /// its seeks already land in, keyframe to target, on the same session axis `seek(to:)` takes.
    public func vodScrubThumbnail(
        atSeconds seconds: Double,
        maxWidth: Int = 320,
        precise: Bool = true
    ) async -> CGImage? {
        guard !isLive else { return nil }
        guard let session = nativeVideoSession else {
            guard let host = softwareHost else { return nil }
            let gen = loadGeneration
            let image = await host.vodScrubStill(atSessionSeconds: seconds, maxWidth: maxWidth)
            return loadGeneration == gen ? image : nil
        }
        let gen = loadGeneration
        let source = await Task.detached(priority: .userInitiated) { [session] in
            session.scrubThumbnailSource(atSeconds: seconds)
        }.value
        // Guard against zap/stop clearing the LRU: a stale extractor's segment indices
        // collide with the next source's.
        guard let source, loadGeneration == gen else { return nil }
        let extractor: FrameExtractor
        if let idx = scrubThumbnailExtractors.firstIndex(where: { $0.segmentIndex == source.segmentIndex }) {
            let hit = scrubThumbnailExtractors.remove(at: idx)
            scrubThumbnailExtractors.append(hit)
            extractor = hit.extractor
        } else {
            guard let reader = source.makeReader() else { return nil }
            extractor = FrameExtractor(reader: reader, formatHint: "mp4")
            scrubThumbnailExtractors.append((source.segmentIndex, extractor))
            trimScrubThumbnailExtractors()
        }
        if precise {
            return await extractor.preciseThumbnail(
                at: max(0, seconds - source.startSeconds),
                maxWidth: maxWidth
            )
        }
        return await extractor.thumbnail(at: 0, maxWidth: maxWidth)
    }

    /// Enforce the cache-backed still LRU after a miss. Kept internal so the exact six-entry
    /// eviction boundary can be pinned without opening a playback session.
    func trimScrubThumbnailExtractors() {
        while scrubThumbnailExtractors.count > Self.scrubThumbnailExtractorLimit {
            _ = scrubThumbnailExtractors.removeFirst()
        }
    }

    /// True while a native or software session exists to serve scrub thumbnails.
    public var supportsCacheBackedStills: Bool { nativeVideoSession != nil || softwareHost != nil }
}

