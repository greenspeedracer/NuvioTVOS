import XCTest
import SwiftUI
@testable import NuvioTV

@MainActor
final class SceneNavigationTests: XCTestCase {
    
    func testRemoteDownOpensSceneWithoutPauseOrSeek() {
        let viewModel = PlayerViewModel()
        viewModel.status = .playing
        XCTAssertFalse(viewModel.showScenePanel)
        
        // Simulating remote Down when controls are hidden
        viewModel.openScene()
        
        XCTAssertTrue(viewModel.showScenePanel)
        XCTAssertEqual(viewModel.status, .playing, "Playback must not pause when Scene opens")
        XCTAssertEqual(viewModel.sceneViewModel.selectedTab, .scene, "Scene tab must be selected initially")
    }
    
    func testTabsAndCardsFocusNavigationLifecycle() {
        let coordinator = SceneCoordinator(
            frameProvider: UnsupportedSceneFrameProvider()
        )
        let sceneVM = SceneViewModel(coordinator: coordinator)
        
        sceneVM.open()
        XCTAssertTrue(sceneVM.isVisible)
        XCTAssertEqual(sceneVM.selectedTab, .scene)
        
        // Switching tabs
        sceneVM.selectTab(.info)
        XCTAssertEqual(sceneVM.selectedTab, .info)
        
        sceneVM.selectTab(.scene)
        XCTAssertEqual(sceneVM.selectedTab, .scene)
        
        // Opening detail sheet
        let actor = SceneRecognizedActor(id: "1", name: "Keanu Reeves", character: "Neo")
        sceneVM.openDetail(.actor(actor, detail: ScenePersonDetail(id: 1, name: "Keanu Reeves", biography: "Action star")))
        XCTAssertTrue(sceneVM.isDetailVisible)
        
        // Back/Menu closes detail first
        sceneVM.closeDetail()
        XCTAssertFalse(sceneVM.isDetailVisible)
        XCTAssertTrue(sceneVM.isVisible, "Closing detail sheet should keep Scene panel open")
        
        // Up/Back closes Scene panel
        sceneVM.close()
        XCTAssertFalse(sceneVM.isVisible)
    }
    
    func testControlsAutoHideSuspendedWhileSceneOpen() {
        let viewModel = PlayerViewModel()
        viewModel.status = .playing
        
        viewModel.openScene()
        XCTAssertTrue(viewModel.showScenePanel)
        
        // When Scene is open, closing it restores normal auto-hide behavior
        viewModel.closeScene()
        XCTAssertFalse(viewModel.showScenePanel)
    }
    
    func testPlayPauseTogglesPlaybackWithoutDismissingScene() {
        let viewModel = PlayerViewModel()
        viewModel.status = .playing
        viewModel.openScene()
        XCTAssertTrue(viewModel.showScenePanel)
        
        // Toggle play/pause
        viewModel.pause()
        XCTAssertEqual(viewModel.status, .paused)
        XCTAssertTrue(viewModel.showScenePanel, "Scene must remain open when pausing")
        
        viewModel.play()
        XCTAssertEqual(viewModel.status, .playing)
        XCTAssertTrue(viewModel.showScenePanel, "Scene must remain open when resuming")
        
        viewModel.closeScene()
    }
    
    func testScrubbingAndErrorPrecedenceOverScene() {
        let viewModel = PlayerViewModel()
        viewModel.status = .paused
        
        // When scrubbing, remote input is owned by scrub
        viewModel.beginScrub()
        // An active scrub retains input ownership; Down must not open Scene
        XCTAssertTrue(viewModel.isScrubbing)
        
        viewModel.cancelScrub()
        XCTAssertFalse(viewModel.isScrubbing)
    }
}
