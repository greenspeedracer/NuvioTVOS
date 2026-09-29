import XCTest
@testable import NuvioTV

@MainActor
private final class CountingSceneFrameProvider: SceneFrameProviding {
    var isSupported: Bool { false }
    var capabilityMessage: String? { "Test frame unavailable" }
    var onCapture: (() -> Void)?

    func captureCurrentFrame(maxWidth: Int, context: SceneContext) -> SceneFrame? {
        onCapture?()
        return nil
    }
}

@MainActor
private final class PausedFrameSceneProvider: SceneFrameProviding {
    let isSupported = true
    let capabilityMessage: String? = nil
    var onCapture: (() -> Void)?
    private(set) var captureCount = 0
    private let image: CGImage

    init() {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: 100,
            height: 100,
            bitsPerComponent: 8,
            bytesPerRow: 400,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        self.image = context.makeImage()!
    }

    func captureCurrentFrame(maxWidth: Int, context: SceneContext) -> SceneFrame? {
        captureCount += 1
        onCapture?()
        return SceneFrame(
            image: image,
            sourceTime: 10.0,
            sessionID: context.sessionID,
            generation: context.timelineGeneration
        )
    }
}

private struct EmptySceneCastProvider: SceneCastProviding {
    func fetchCast(context: SceneContext) async throws -> [SceneCastCandidate] { [] }
}

@MainActor
final class SceneLifecycleTests: XCTestCase {
    
    func testSceneContextInitializationAndEquivalence() {
        let sessionID = UUID()
        let context1 = SceneContext(
            canonicalId: "movie-123",
            mediaType: "movie",
            title: "Test Movie",
            sessionID: sessionID,
            timelineGeneration: 1
        )
        let context2 = SceneContext(
            canonicalId: "movie-123",
            mediaType: "movie",
            title: "Test Movie",
            sessionID: sessionID,
            timelineGeneration: 1
        )
        
        XCTAssertEqual(context1, context2)
        XCTAssertEqual(context1.canonicalId, "movie-123")
        XCTAssertEqual(context1.timelineGeneration, 1)
    }
    
    func testCoordinatorGenerationIncrementsOnSeekAndReset() {
        let coordinator = SceneCoordinator(
            frameProvider: UnsupportedSceneFrameProvider()
        )
        
        coordinator.openPanel()
        XCTAssertTrue(coordinator.isPanelOpen)
        
        // Seek increments generation
        coordinator.handleSeek()
        XCTAssertEqual(coordinator.currentSnapshot.actors, [])
        
        // Reset session on new source
        coordinator.resetSession()
        XCTAssertFalse(coordinator.isPanelOpen)
        XCTAssertEqual(coordinator.currentSnapshot, .empty)
    }

    func testActorResultsClearWhenCurrentSceneHasNoMatch() {
        let coordinator = SceneCoordinator(frameProvider: UnsupportedSceneFrameProvider())
        let actor = SceneRecognizedActor(id: "1", name: "Actor")

        coordinator.updateActorStatus(.recognized([actor]))
        XCTAssertEqual(coordinator.currentSnapshot.actors, [actor])

        coordinator.updateActorStatus(.noMatch)
        XCTAssertTrue(coordinator.currentSnapshot.actors.isEmpty)
        XCTAssertEqual(coordinator.currentSnapshot.actorStatus, .noMatch)

        coordinator.updateActorStatus(.recognized([actor]))
        coordinator.openPanel()
        XCTAssertTrue(coordinator.currentSnapshot.actors.isEmpty)
        XCTAssertEqual(coordinator.currentSnapshot.actorStatus, .analyzing)
        coordinator.closePanel()
    }

    func testSeekRestartsSceneSamplingWhilePanelIsOpen() async {
        let frameProvider = CountingSceneFrameProvider()
        let coordinator = SceneCoordinator(
            frameProvider: frameProvider,
            castProvider: EmptySceneCastProvider()
        )
        coordinator.updateContext(SceneContext(canonicalId: "movie-1", mediaType: "movie", title: "Movie"))
        coordinator.setPlaybackProviders(isPlaying: { true }, sourceTime: { 10 })
        coordinator.openPanel()

        let capturedAfterSeek = expectation(description: "Frame sampled after seek")
        frameProvider.onCapture = { capturedAfterSeek.fulfill() }
        coordinator.handleSeek()

        await fulfillment(of: [capturedAfterSeek], timeout: 2)
        coordinator.closePanel()
    }

    func testPauseDuringAnalysisQueuesOneStillCapture() async {
        let frameProvider = PausedFrameSceneProvider()
        let coordinator = SceneCoordinator(
            frameProvider: frameProvider,
            castProvider: EmptySceneCastProvider()
        )
        coordinator.updateContext(SceneContext(
            canonicalId: "movie-paused",
            mediaType: "movie",
            title: "Paused Movie",
            sessionID: UUID(),
            timelineGeneration: 1
        ))
        var isPlaying = true
        coordinator.setPlaybackProviders(isPlaying: { isPlaying }, sourceTime: { 10.0 })

        let pausedCapture = expectation(description: "One still is captured after analysis finishes")
        frameProvider.onCapture = {
            if frameProvider.captureCount == 2 {
                pausedCapture.fulfill()
            }
        }

        coordinator.openPanel()
        XCTAssertEqual(frameProvider.captureCount, 1)
        isPlaying = false
        coordinator.handlePlaybackPaused()
        XCTAssertEqual(frameProvider.captureCount, 1, "Pause during analysis should queue rather than overlap a capture")

        await fulfillment(of: [pausedCapture], timeout: 3)
        XCTAssertEqual(frameProvider.captureCount, 2)
        coordinator.closePanel()
    }

    func testPausedReopenQueuesCaptureAfterOlderAnalysisFinishes() async {
        let frameProvider = PausedFrameSceneProvider()
        let coordinator = SceneCoordinator(
            frameProvider: frameProvider,
            castProvider: EmptySceneCastProvider()
        )
        coordinator.updateContext(SceneContext(
            canonicalId: "movie-reopened-paused",
            mediaType: "movie",
            title: "Paused Reopen Movie",
            sessionID: UUID(),
            timelineGeneration: 1
        ))
        var isPlaying = true
        coordinator.setPlaybackProviders(isPlaying: { isPlaying }, sourceTime: { 10.0 })

        let reopenedCapture = expectation(description: "Paused reopened panel captures after prior analysis")
        frameProvider.onCapture = {
            if frameProvider.captureCount == 2 {
                reopenedCapture.fulfill()
            }
        }

        coordinator.openPanel()
        XCTAssertEqual(frameProvider.captureCount, 1)
        coordinator.closePanel()
        isPlaying = false
        coordinator.openPanel()
        XCTAssertEqual(frameProvider.captureCount, 1, "Reopen should queue while the old analysis still owns capture")

        await fulfillment(of: [reopenedCapture], timeout: 3)
        XCTAssertEqual(frameProvider.captureCount, 2)
        coordinator.closePanel()
    }
    
    func testResultCacheStorageAndRetrieval() async {
        let cache = SceneResultCache()
        let context = SceneContext(
            canonicalId: "movie-456",
            mediaType: "movie",
            title: "Inception",
            timelineGeneration: 1
        )
        
        let actor = SceneRecognizedActor(id: "1", name: "Leonardo DiCaprio", character: "Cobb")
        let snapshot = SceneSnapshot(
            timestamp: 10.5,
            actors: [actor],
            song: nil,
            actorStatus: .recognized([actor]),
            musicStatus: .disabled,
            generation: 1
        )
        
        // Store in cache
        await cache.store(snapshot: snapshot, context: context, sourceTime: 10.5)
        
        // Retrieve within the same 5-second bucket (10.0 - 15.0)
        let cached = await cache.snapshot(for: context, sourceTime: 12.0)
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.actors.first?.name, "Leonardo DiCaprio")
        
        // Retrieval in distant bucket returns nil
        let missed = await cache.snapshot(for: context, sourceTime: 45.0)
        XCTAssertNil(missed)
        
        // Clear cache
        await cache.clear()
        let cleared = await cache.snapshot(for: context, sourceTime: 12.0)
        XCTAssertNil(cleared)
    }
    
    func testPlaybackAudioTapBrokerReferenceCounting() {
        let broker = PlaybackAudioTapBroker(engine: nil)
        XCTAssertFalse(broker.hasActiveSubscribers)
        
        let sub1 = broker.subscribe()
        XCTAssertTrue(broker.hasActiveSubscribers)
        
        let sub2 = broker.subscribe()
        XCTAssertTrue(broker.hasActiveSubscribers)
        
        broker.unsubscribe(id: sub1.id)
        XCTAssertTrue(broker.hasActiveSubscribers)
        
        broker.unsubscribe(id: sub2.id)
        XCTAssertFalse(broker.hasActiveSubscribers)
    }
    
    func testSceneTimelineDatabaseIntervalLookupAndMatching() async {
        let cache = SceneResultCache()
        let context = SceneContext(
            canonicalId: "the-batman",
            mediaType: "movie",
            title: "The Batman"
        )
        
        let actor = SceneRecognizedActor(
            id: "pattinson",
            name: "Robert Pattinson",
            character: "Bruce Wayne / Batman"
        )
        
        // 00:45:31 (2731.0s) to 00:46:07 (2767.0s)
        let interval = SceneTimelineInterval(
            id: "batman-scene-1",
            canonicalId: "the-batman",
            startTime: 2731.0,
            endTime: 2767.0,
            actors: [actor]
        )
        
        await cache.storeTimelineInterval(interval)
        
        // Query inside interval: 00:45:45 (2745.0s)
        let match = await cache.findTimelineInterval(for: context, sourceTime: 2745.0)
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.actors.first?.name, "Robert Pattinson")
        XCTAssertEqual(match?.actors.first?.character, "Bruce Wayne / Batman")
        
        // Query outside interval: 00:50:00 (3000.0s)
        let miss = await cache.findTimelineInterval(for: context, sourceTime: 3000.0)
        XCTAssertNil(miss)
    }
    
    func testDualPathSceneCoordinatorPrefersDatabaseWhenModelUnavailable() async {
        let cache = SceneResultCache()
        let context = SceneContext(
            canonicalId: "the-batman",
            mediaType: "movie",
            title: "The Batman"
        )
        
        let actor = SceneRecognizedActor(
            id: "pattinson",
            name: "Robert Pattinson",
            character: "Bruce Wayne / Batman"
        )
        let interval = SceneTimelineInterval(
            id: "batman-scene-1",
            canonicalId: "the-batman",
            startTime: 100.0,
            endTime: 120.0,
            actors: [actor]
        )
        await cache.storeTimelineInterval(interval)
        
        // Coordinator with unsupported frame provider (no local camera/model)
        let coordinator = SceneCoordinator(
            frameProvider: UnsupportedSceneFrameProvider(),
            resultCache: cache
        )
        coordinator.updateContext(context)
        coordinator.setPlaybackProviders(isPlaying: { true }, sourceTime: { 110.0 })
        
        coordinator.openPanel()
        
        // Allow async database task to populate snapshot
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        // Pre-indexed database supplies the actors even without a local ML model
        XCTAssertEqual(coordinator.currentSnapshot.actors.first?.name, "Robert Pattinson")
        XCTAssertEqual(coordinator.currentSnapshot.actors.first?.character, "Bruce Wayne / Batman")
    }
    
    func testDynamicPlayerSceneFrameProviderMPVFallback() {
        let currentBackend: PlayerBackendKind = .mpv
        let dynamicProvider = DynamicPlayerSceneFrameProvider(
            activeEngineKindProvider: { currentBackend },
            aetherControllerProvider: { nil }
        )
        
        // When running on MPV, reports honest unsupported status without crashing
        XCTAssertFalse(dynamicProvider.isSupported)
        XCTAssertEqual(
            dynamicProvider.capabilityMessage,
            "MPV backend does not support direct display pipeline frame capture."
        )
        
        let dummyContext = SceneContext(
            canonicalId: "movie-1",
            mediaType: "movie",
            title: "Movie"
        )
        XCTAssertNil(dynamicProvider.captureCurrentFrame(maxWidth: 960, context: dummyContext))
    }

    func testSceneCoordinatorPrewarmFetchesCastWithoutOpeningPanel() async throws {
        let candidate = SceneCastCandidate(
            id: "cast-1",
            name: "Cillian Murphy",
            character: "J. Robert Oppenheimer",
            profileURL: nil,
            tmdbId: 2037
        )
        let castProvider = StubSceneCastProvider(candidates: [candidate])
        let frameProvider = CountingSceneFrameProvider()
        var captureCount = 0
        frameProvider.onCapture = {
            captureCount += 1
        }
        
        let coordinator = SceneCoordinator(
            frameProvider: frameProvider,
            castProvider: castProvider
        )
        
        let context = SceneContext(
            canonicalId: "movie-oppenheimer",
            mediaType: "movie",
            title: "Oppenheimer"
        )
        
        coordinator.prewarm(context: context)
        
        // Allow async cast fetch task to finish
        for _ in 0..<20 {
            if !coordinator.castCandidates.isEmpty { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        
        // Assert pre-warmed state:
        XCTAssertFalse(coordinator.isPanelOpen)
        XCTAssertEqual(coordinator.castCandidates.count, 1)
        XCTAssertEqual(coordinator.castCandidates.first?.name, "Cillian Murphy")
        XCTAssertEqual(castProvider.fetchCount, 1)
        XCTAssertEqual(captureCount, 0, "Pre-warming must never capture video frames while panel is closed")
        
        // Subsequent openPanel should use pre-warmed cast without re-fetching
        coordinator.openPanel()
        XCTAssertTrue(coordinator.isPanelOpen)
        XCTAssertEqual(castProvider.fetchCount, 1, "Opening panel should not re-fetch already pre-warmed cast")
        XCTAssertGreaterThanOrEqual(captureCount, 1, "Opening panel should initiate frame capture")
    }
    
    func testAnimeContextPopulatesEpisodeCastAndBypassesFrameCapture() async throws {
        let animeCandidates = [
            SceneCastCandidate(id: "1", name: "Yuki Kaji", character: "Eren Yeager (voice)", tmdbId: 101),
            SceneCastCandidate(id: "2", name: "Yui Ishikawa", character: "Mikasa Ackerman (voice)", tmdbId: 102),
            SceneCastCandidate(id: "3", name: "Marina Inoue", character: "Armin Arlert (voice)", tmdbId: 103)
        ]
        let castProvider = StubSceneCastProvider(candidates: animeCandidates)
        let frameProvider = CountingSceneFrameProvider()
        var captureCount = 0
        frameProvider.onCapture = {
            captureCount += 1
        }
        
        let coordinator = SceneCoordinator(
            frameProvider: frameProvider,
            castProvider: castProvider
        )
        
        let animeContext = SceneContext(
            canonicalId: "kitsu:1234:1",
            mediaType: "series",
            title: "Attack on Titan",
            season: 1,
            episode: 1,
            isAnime: true
        )
        
        coordinator.updateContext(animeContext)
        XCTAssertTrue(coordinator.isAnime)
        
        coordinator.openPanel()
        XCTAssertTrue(coordinator.isPanelOpen)
        
        // Allow async cast fetch task to finish
        for _ in 0..<20 {
            if !coordinator.currentSnapshot.actors.isEmpty { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        
        // Assert: all anime episode voice actors are immediately populated and recognized!
        XCTAssertEqual(coordinator.currentSnapshot.actors.count, 3)
        XCTAssertEqual(coordinator.currentSnapshot.actors.map(\.name), ["Yuki Kaji", "Yui Ishikawa", "Marina Inoue"])
        XCTAssertEqual(coordinator.currentSnapshot.actors.first?.character, "Eren Yeager (voice)")
        XCTAssertEqual(coordinator.currentSnapshot.actorStatus, .recognized(coordinator.currentSnapshot.actors))
        
        // Frame capture for facial recognition must be bypassed for anime
        XCTAssertEqual(captureCount, 0, "Anime media must bypass visual face capture and directly show full episode cast")
        
        // Seeking in anime preserves the full episode cast
        coordinator.handleSeek()
        XCTAssertEqual(coordinator.currentSnapshot.actors.count, 3)
        XCTAssertEqual(coordinator.currentSnapshot.actors.map(\.name), ["Yuki Kaji", "Yui Ishikawa", "Marina Inoue"])
    }
}

private final class StubSceneCastProvider: SceneCastProviding, @unchecked Sendable {
    let candidates: [SceneCastCandidate]
    var fetchCount: Int = 0
    
    init(candidates: [SceneCastCandidate]) {
        self.candidates = candidates
    }
    
    func fetchCast(context: SceneContext) async throws -> [SceneCastCandidate] {
        fetchCount += 1
        return candidates
    }
}

