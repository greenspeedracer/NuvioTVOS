## tvOS Beta 3.3.9

> **Install:** [NuvioTV-3.3.9-unsigned-release.ipa](https://github.com/bobsupra/NuvioTVOS/releases/download/tvos-beta-3.3.9/NuvioTV-3.3.9-unsigned-release.ipa) requires a compatible tvOS development or sideloading signing workflow before installation.

> **New beta alerts:** [Manage notifications](https://github.com/bobsupra/NuvioTVOS/subscription) → choose **Custom → Releases** · [Report a bug or suggest an idea](https://github.com/bobsupra/NuvioTVOS/issues/new/choose)

> 🎉 **Thank you for 200+ GitHub Stars!** A huge thank you to everyone in the community for supporting NuvioTVOS and helping reach 200+ stars on GitHub! Your feedback, issue reports, and testing make this possible.

### Apple TV-Style Scene Insights & In-Scene Cast Recognition (CoreML AI)

- **On-Device CoreML Vision Models:** Integrated lightweight, high-performance on-device CoreML neural networks (**YuNet** face detection + **SFace** facial feature recognition) increasing the package footprint (~23MB to ~60MB) for 100% private, instantaneous on-device actor recognition.
- **In-Scene Real Actor Recognition:** Automatically extracts video frames in real time, scans live scenes for actor faces, and matches them against TMDB cast profiles to highlight the exact actors currently appearing in the scene.
- **Anime & Animated Content Cast Heuristics:** For anime and animated content where live facial recognition is inapplicable, Scene Insights automatically skips frame capture and immediately populates the full episode voice cast and character roles.
- **Real-Time Music & Subtitle Cue Recognition:** Detects soundtrack music and background songs in real time using audio recognition and subtitle music cue parsing, enriched with Apple Music and Shazam album art, artist, and track metadata.
- **Actor & Song Detail Cards:** Tap any actor or song card in the Scene panel to view detailed biographies, character roles, filmographies, and Apple Music track listings.

### Seamless Background Trailers in Details Screen

- **Enabled by Default:** Background trailers are now enabled by default across all movie and series Details pages (`SettingsKey.backgroundTrailersEnabled`).
- **Seamless Card-to-Fullscreen Transition:** Preview trailers directly inside poster cards on the Home screen; tapping a card seamlessly transitions playback into the Details background and expands into full-screen trailer playback with continuous audio and zero rebuffering.

### Production Browse & Catalog Enhancements

- **Production Company Browse:** Added dedicated production company rails and browse views (`ProductionBrowseView.swift`) with live movie/series collection counts and smooth grid focus navigation.
- **Standardized Stream Cache Sessions:** Standardized session path resolution in `PlaybackStreamDiskCache.swift` to prevent active playback titles from being misidentified in disk budget evictions (closes #124).

### Simkl & Trakt Sync Refinements

- **Scrobble & Episode Matching:** Enhanced Simkl scrobbling, anime episode matching, and continue-watching sync deduplication across multi-profile setups.
- **Immediate Settings Persistence:** Instant sync flushing upon navigation away from Settings to avoid remote sync race conditions.

### Diagnostics & Release Hardening

- **Main Thread Stall Watchdog:** `TVHomeDebugTrace` 25ms debug polling disabled by default for zero UI overhead.
- **Release Diagnostics Cleanup:** Verbose diagnostic dumps (`[ScreensaverDebug]`, `[TVTrace]`, `[LagDiag]`) cleaned and guarded for release builds.
- **Resilient Watchdogs Active:** Maintained 30-second stream load watchdog (`loadWatchdogTask`) with automatic source failover and AetherEngine buffer stall recovery.

### Tests & Stability

- Comprehensive automated test suite passing with 0 failures across scene recognition pipelines, subtitle music scraping, trailer handoff, Simkl sync, and stream caching.

### Known issues

- Picture in Picture requires a supported Apple TV 4K / tvOS 15+ device.
- Physical Apple TV playback, HDMI/HDR/Dolby Vision, AirPlay receivers, Atmos hardware, and live-TV paths still need real-device validation; the Apple TV Simulator cannot play AV1.
