import XCTest
@testable import NuvioTV

final class PlaybackIdlePolicyTests: XCTestCase {

    func testPlayingAndBufferingPreventSleep() {
        XCTAssertTrue(PlaybackIdlePolicy.preventsIdle(status: .playing))
        XCTAssertTrue(PlaybackIdlePolicy.preventsIdle(status: .buffering))
        XCTAssertTrue(PlaybackIdlePolicy.preventsIdle(status: .idle))
    }

    func testPausedEndedAndErrorAllowSleep() {
        XCTAssertFalse(PlaybackIdlePolicy.preventsIdle(status: .paused))
        XCTAssertFalse(PlaybackIdlePolicy.preventsIdle(status: .ended))
        XCTAssertFalse(PlaybackIdlePolicy.preventsIdle(status: .error("stream failed")))
    }

    func testSourceSwitchKeepsDeviceAwakeThroughPauseFlicker() {
        XCTAssertTrue(
            PlaybackIdlePolicy.preventsIdle(
                status: .paused,
                isSwitchingSource: true
            )
        )
        XCTAssertTrue(
            PlaybackIdlePolicy.preventsIdle(
                status: .error("expired"),
                isReloadingStream: true
            )
        )
        XCTAssertTrue(
            PlaybackIdlePolicy.preventsIdle(
                status: .paused,
                isAdvancingEpisode: true
            )
        )
    }
}
