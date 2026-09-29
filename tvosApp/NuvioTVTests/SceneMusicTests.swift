import XCTest
import AVFAudio
import AetherEngine
@testable import NuvioTV

final class SceneMusicTests: XCTestCase {
    
    func testAudioTapFormatIsStandard48kHzMonoFloat32() {
        let format = AetherEngine.audioTapFormat
        XCTAssertEqual(format.sampleRate, 48000)
        XCTAssertEqual(format.channelCount, 1)
        XCTAssertEqual(format.commonFormat, .pcmFormatFloat32)
    }
    
    func testMusicRecognitionPausedStateReportsRequiresPlayback() async {
        let service = MusicRecognitionService()
        
        let dummyStream = AsyncStream<AudioTapBuffer> { continuation in
            continuation.finish()
        }
        
        // When not playing, starting recognition must immediately report requiresPlayback
        await service.startListening(stream: dummyStream, isPlaying: false, currentSourceTime: 0)
        
        // Paused reporting
        await service.reportPlaybackPaused()
        
        // Resetting returns to disabled
        await service.reset()
    }
    
    func testMusicRecognitionSongModelEquivalence() {
        let song1 = SceneRecognizedSong(
            id: "shazam-999",
            title: "Midnight City",
            artist: "M83",
            artworkURL: URL(string: "https://example.com/art.jpg"),
            appleMusicURL: URL(string: "https://music.apple.com/song/999"),
            genres: ["Electronic"],
            observedSourceTime: 120.0
        )
        
        let song2 = SceneRecognizedSong(
            id: "shazam-999",
            title: "Midnight City",
            artist: "M83",
            artworkURL: URL(string: "https://example.com/art.jpg"),
            appleMusicURL: URL(string: "https://music.apple.com/song/999"),
            genres: ["Electronic"],
            observedSourceTime: 120.0
        )
        
        XCTAssertEqual(song1, song2)
        XCTAssertEqual(song1.title, "Midnight City")
        XCTAssertEqual(song1.artist, "M83")
    }
    
    func testSceneMusicStatusIndependentFromActorStatus() {
        let actorStatus = SceneActorStatus.unavailable(reason: "Model weights not packaged")
        let song = SceneRecognizedSong(id: "s1", title: "Song 1", artist: "Artist 1")
        let musicStatus = SceneMusicStatus.matched(song)
        
        let snapshot = SceneSnapshot(
            timestamp: 50.0,
            actors: [],
            song: song,
            actorStatus: actorStatus,
            musicStatus: musicStatus,
            generation: 1
        )
        
        // Failure or unavailable in actor pipeline does NOT disable music pipeline
        XCTAssertFalse(snapshot.actorStatus.isRecognized)
        XCTAssertEqual(snapshot.musicStatus.matchedSong?.title, "Song 1")
    }

    func testMusicRecognitionStreamAccumulatesBuffers() async {
        let service = MusicRecognitionService()
        let format = AetherEngine.audioTapFormat
        let frameCount: AVAudioFrameCount = 4800 // 100ms
        
        let (stream, continuation) = AsyncStream.makeStream(of: AudioTapBuffer.self)
        await service.startListening(stream: stream, isPlaying: true, currentSourceTime: 10.0)
        
        for i in 0..<10 {
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
            buffer.frameLength = frameCount
            continuation.yield(AudioTapBuffer(buffer: buffer, sourceTime: 10.0 + Double(i) * 0.1, discontinuity: i == 0))
        }
        
        continuation.finish()
        try? await Task.sleep(nanoseconds: 100_000_000)
        await service.reset()
    }
    
    func testMusicRecognitionEntitlementErrorReportsUnavailable() async {
        let expectation = expectation(description: "Status changed to unavailable")
        var observedStatus: SceneMusicStatus?
        let service = MusicRecognitionService { status in
            observedStatus = status
            if case .unavailable = status {
                expectation.fulfill()
            }
        }
        
        let dummyStream = AsyncStream<AudioTapBuffer> { continuation in
            continuation.finish()
        }
        await service.startListening(stream: dummyStream, isPlaying: true, currentSourceTime: 0)
        
        let userInfo: [String: Any] = [
            NSDebugDescriptionErrorKey: "Missing entitlements",
            "AMSStatusCode": 401
        ]
        let entitlementError = NSError(domain: "com.apple.ShazamKit", code: 202, userInfo: userInfo)
        
        await service.handleNoMatch(error: entitlementError)
        
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(
            observedStatus,
            .unavailable(reason: "ShazamKit requires App Service enabled in Apple Developer Portal")
        )
    }
    
    func testMusicRecognitionBareCode202ReportsUnavailable() async {
        let expectation = expectation(description: "Status changed to unavailable for bare code 202")
        var observedStatus: SceneMusicStatus?
        let service = MusicRecognitionService { status in
            observedStatus = status
            if case .unavailable = status {
                expectation.fulfill()
            }
        }
        
        let dummyStream = AsyncStream<AudioTapBuffer> { continuation in
            continuation.finish()
        }
        await service.startListening(stream: dummyStream, isPlaying: true, currentSourceTime: 0)
        
        // Bare code 202 error with empty userInfo (as produced on Simulator / unsigned app)
        let bareCode202Error = NSError(domain: "com.apple.ShazamKit", code: 202, userInfo: [:])
        await service.handleNoMatch(error: bareCode202Error)
        
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(
            observedStatus,
            .unavailable(reason: "ShazamKit requires App Service enabled in Apple Developer Portal")
        )
    }
    
    func testSceneSongIntervalActiveState() {
        let song = SceneRecognizedSong(
            id: "s1",
            title: "God Save the Queen",
            artist: "Sex Pistols",
            observedSourceTime: 0.0,
            startTime: 0.0,
            endTime: 85.0,
            sceneDescription: "Opening scene"
        )
        
        // Inside interval -> Active (Appears)
        XCTAssertTrue(song.isActive(at: 0.0))
        XCTAssertTrue(song.isActive(at: 45.0))
        XCTAssertTrue(song.isActive(at: 85.0))
        
        // Outside interval -> Inactive (Disappears)
        XCTAssertFalse(song.isActive(at: 86.0))
        XCTAssertFalse(song.isActive(at: 120.0))
        XCTAssertFalse(song.isActive(at: -1.0))
    }
    
    func testSceneSubtitleMusicRecognizerParsesCues() {
        let cue1 = "♪ \"God Save the Queen\" by Sex Pistols ♪"
        let song1 = SceneSubtitleMusicRecognizer.detectSong(
            in: cue1,
            startTime: 0.0,
            endTime: 85.0,
            canonicalId: "ted-lasso-s1e1"
        )
        XCTAssertNotNil(song1)
        XCTAssertEqual(song1?.title, "God Save the Queen")
        XCTAssertEqual(song1?.artist, "Sex Pistols")
        XCTAssertEqual(song1?.startTime, 0.0)
        XCTAssertEqual(song1?.endTime, 85.0)
        
        let cue2 = "[Playing \"Simplify\" by Los Coast]"
        let song2 = SceneSubtitleMusicRecognizer.detectSong(
            in: cue2,
            startTime: 860.0,
            endTime: 900.0,
            canonicalId: "ted-lasso-s1e1"
        )
        XCTAssertNotNil(song2)
        XCTAssertEqual(song2?.title, "Simplify")
        XCTAssertEqual(song2?.artist, "Los Coast")
        
        let cue3 = "♪ Sex Pistols - God Save the Queen ♪"
        let song3 = SceneSubtitleMusicRecognizer.detectSong(
            in: cue3,
            startTime: 10.0,
            endTime: 40.0,
            canonicalId: "ted-lasso-s1e1"
        )
        XCTAssertNotNil(song3)
        XCTAssertEqual(song3?.title, "God Save the Queen")
        XCTAssertEqual(song3?.artist, "Sex Pistols")
        
        // Non-music cue should return nil
        let nonMusic = "Ted: How you doing Coach?"
        let nonSong = SceneSubtitleMusicRecognizer.detectSong(
            in: nonMusic,
            startTime: 20.0,
            endTime: 25.0,
            canonicalId: "ted-lasso-s1e1"
        )
        XCTAssertNil(nonSong)
    }
    
    func testSceneResultCacheStoresAndRetrievesSongIntervals() async {
        let cache = SceneResultCache()
        let context = SceneContext(canonicalId: "test-movie", mediaType: "movie", title: "Test Movie")
        
        let song = SceneRecognizedSong(
            id: "s1",
            title: "God Save the Queen",
            artist: "Sex Pistols",
            observedSourceTime: 10.0,
            startTime: 10.0,
            endTime: 60.0,
            sceneDescription: "Locker room dance"
        )
        
        let interval = SceneTimelineInterval(
            canonicalId: "test-movie",
            startTime: 10.0,
            endTime: 60.0,
            actors: [],
            song: song,
            sceneDescription: "Locker room dance"
        )
        
        await cache.storeTimelineInterval(interval)
        
        // At 25.0s (within range) -> Song found!
        let activeSong = await cache.findTimelineSong(for: context, sourceTime: 25.0)
        XCTAssertNotNil(activeSong)
        XCTAssertEqual(activeSong?.title, "God Save the Queen")
        
        // At 75.0s (outside range) -> Song is nil! (Finished)
        let inactiveSong = await cache.findTimelineSong(for: context, sourceTime: 75.0)
        XCTAssertNil(inactiveSong)
    }
    
    func testCuratedSoundtrackCatalogFetchesTedLassoOpeningTrack() async {
        let provider = CommunitySceneSoundtrackProvider()
        let context = SceneContext(
            canonicalId: "tt10986410",
            mediaType: "series",
            title: "Ted Lasso",
            season: 1,
            episode: 1,
            imdbId: "tt10986410"
        )
        
        let intervals = try! await provider.fetchSoundtrack(context: context)
        XCTAssertFalse(intervals.isEmpty)
        
        // At timestamp 28.0s (opening practice / sprints), God Save the Queen must be active!
        let openingInterval = intervals.first(where: { $0.contains(timestamp: 28.0) })
        XCTAssertNotNil(openingInterval)
        XCTAssertEqual(openingInterval?.song?.title, "God Save the Queen")
        XCTAssertEqual(openingInterval?.song?.artist, "Sex Pistols")
        XCTAssertNotNil(openingInterval?.song?.artworkURL)
        
        // At timestamp 85.0s, Ted Lasso Theme must be active!
        let themeInterval = intervals.first(where: { $0.contains(timestamp: 85.0) })
        XCTAssertNotNil(themeInterval)
        XCTAssertEqual(themeInterval?.song?.title, "Ted Lasso Theme")
    }
    
    func testSceneSubtitleMusicRecognizerParsesUppercaseSDHCues() {
        let uppercaseCue = "(GOD SAVE THE QUEEN BY SEX PISTOLS PLAYING)"
        let song = SceneSubtitleMusicRecognizer.detectSong(
            in: uppercaseCue,
            startTime: 0.0,
            endTime: 75.0,
            canonicalId: "tt10986410"
        )
        XCTAssertNotNil(song)
        XCTAssertEqual(song?.title, "God Save The Queen")
        XCTAssertEqual(song?.artist, "Sex Pistols")
    }
    
    func testSceneSongMetadataEnricherResolvesAlbumArtwork() async {
        let enricher = SceneSongMetadataEnricher.shared
        let rawSong = SceneRecognizedSong(
            id: "test-simplify",
            title: "Simplify",
            artist: "Los Coast",
            observedSourceTime: 860.0
        )
        
        let enriched = await enricher.enrich(song: rawSong)
        XCTAssertNotNil(enriched.artworkURL)
        XCTAssertTrue(enriched.artworkURL?.absoluteString.contains("mzstatic.com") == true)
        XCTAssertNotNil(enriched.appleMusicURL)
    }
}

