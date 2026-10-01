import SwiftUI

struct ScenePanelView: View {
    @ObservedObject var viewModel: SceneViewModel
    let onDismiss: () -> Void
    let onPlayNextEpisode: (() -> Void)?
    
    @FocusState private var focusedTab: SceneTab?
    @FocusState private var focusedCardID: String?
    
    init(
        viewModel: SceneViewModel,
        onDismiss: @escaping () -> Void,
        onPlayNextEpisode: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.onDismiss = onDismiss
        self.onPlayNextEpisode = onPlayNextEpisode
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Bottom third panel
            VStack(alignment: .leading, spacing: 14) {
                // Tab Header Bar
                tabHeaderBar
                    .padding(.top, 10)
                
                // Active Tab Content
                Group {
                    switch viewModel.selectedTab {
                    case .scene:
                        sceneTabContent
                    case .info:
                        infoTabContent
                    case .upNext:
                        upNextTabContent
                    }
                }
                .frame(height: 248)
                .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onExitCommand {
            onDismiss()
        }
        .onAppear {
            if focusedTab == nil {
                focusedTab = viewModel.selectedTab
            }
        }
        .onChange(of: focusedTab) { _, newTab in
            if let newTab, viewModel.selectedTab != newTab {
                withAnimation(.easeInOut(duration: 0.18)) {
                    viewModel.selectTab(newTab)
                }
            }
        }
        .defaultFocus($focusedTab, .scene)
    }
    
    // MARK: - Tab Header Bar
    
    private var tabHeaderBar: some View {
        HStack(spacing: 16) {
            ForEach(viewModel.availableTabs) { tab in
                let isSelected = viewModel.selectedTab == tab
                let isTabFocused = focusedTab == tab
                let isFilled = isSelected || isTabFocused
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        viewModel.selectTab(tab)
                    }
                }) {
                    Text(tab.localizedTitle)
                        .font(.system(size: 20, weight: isFilled ? .bold : .semibold))
                        .foregroundColor(isFilled ? .black : .white.opacity(0.85))
                        .padding(.horizontal, 24)
                        .frame(height: 48)
                        .modifier(TvDetailsGlassBackground(filled: isFilled, shape: Capsule()))
                }
                .buttonStyle(PosterCardButtonStyle())
                .focused($focusedTab, equals: tab)
                .focusEffectDisabledIfAvailable()
                .scaleEffect(isTabFocused ? 1.05 : 1.0)
                .animation(.easeOut(duration: 0.14), value: isTabFocused)
                .onExitCommand(perform: onDismiss)
                .onMoveCommand { direction in
                    switch direction {
                    case .up:
                        onDismiss()
                    case .down:
                        focusFirstCard()
                    default:
                        break
                    }
                }
            }
        }
        .padding(.horizontal, 60)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Scene Tab Content
    
    private var sceneTabContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .center, spacing: 20) {
                let recognizedActors = viewModel.snapshot.actors
                let playingSong = viewModel.snapshot.song
                
                if recognizedActors.isEmpty, let song = playingSong {
                    // When music is playing but no cast is detected, music is in first place!
                    SceneSongCard(song: song) {
                        viewModel.openDetail(.song(song))
                    }
                    .focused($focusedCardID, equals: "song-\(song.id)")
                    .onExitCommand(perform: onDismiss)
                    .onMoveCommand { direction in
                        if direction == .up {
                            focusedCardID = nil
                            focusedTab = viewModel.selectedTab
                        }
                    }
                } else if !recognizedActors.isEmpty {
                    // Live detected actors in current scene
                    ForEach(recognizedActors) { actor in
                        SceneActorCard(
                            actor: actor,
                            isLiveRecognized: true
                        ) {
                            viewModel.openDetail(.actor(actor, detail: nil))
                        }
                        .focused($focusedCardID, equals: "actor-\(actor.id)")
                        .onExitCommand(perform: onDismiss)
                        .onMoveCommand { direction in
                            if direction == .up {
                                focusedCardID = nil
                                focusedTab = viewModel.selectedTab
                            }
                        }
                    }
                    
                    // Accompanied by playing music if present
                    if let song = playingSong {
                        SceneSongCard(song: song) {
                            viewModel.openDetail(.song(song))
                        }
                        .focused($focusedCardID, equals: "song-\(song.id)")
                        .onExitCommand(perform: onDismiss)
                        .onMoveCommand { direction in
                            if direction == .up {
                                focusedCardID = nil
                                focusedTab = viewModel.selectedTab
                            }
                        }
                    }
                } else {
                    // No detected actors and no music: show clean scanning / status card
                    statusCard
                }
            }
            .padding(.horizontal, 60)
            .padding(.vertical, 16)
        }
    }
    
    @ViewBuilder
    private var statusCard: some View {
        VStack(spacing: 8) {
            switch viewModel.snapshot.actorStatus {
            case .analyzing, .preparingReferences:
                ProgressView()
                    .scaleEffect(1.1)
                    .padding(.bottom, 4)
                Text(viewModel.isAnime ? "Loading cast…" : "Scanning scene…")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            case .unavailable(let reason):
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 32))
                    .foregroundColor(.white.opacity(0.35))
                    .padding(.bottom, 2)
                Text(reason.isEmpty ? (viewModel.isAnime ? "No cast available" : "No actors in this shot") : reason)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            default:
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 32))
                    .foregroundColor(.white.opacity(0.35))
                    .padding(.bottom, 2)
                Text(viewModel.isAnime ? "No cast for this episode" : "No actors in this shot")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .frame(width: 174, height: 188)
        .modifier(TvCardGlassBackground(isFocused: false, shape: RoundedRectangle(cornerRadius: 24, style: .continuous)))
    }
    
    // MARK: - Info Tab Content
    
    private var infoTabContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Text(viewModel.infoTitle)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.white)
                
                if let year = viewModel.infoYear {
                    Text(year)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                
                if let runtime = viewModel.infoRuntime {
                    Text(runtime)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            
            if !viewModel.infoOverview.isEmpty {
                Text(viewModel.infoOverview)
                    .font(.system(size: 19, weight: .regular))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(4)
                    .frame(maxWidth: 900, alignment: .leading)
            }
        }
        .padding(.horizontal, 60)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Up Next Tab Content
    
    @ViewBuilder
    private var upNextTabContent: some View {
        if let next = viewModel.nextEpisode {
            Button(action: {
                onPlayNextEpisode?()
            }) {
                HStack(spacing: 24) {
                    // Thumbnail
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 240, height: 140)
                        
                        if let thumb = next.thumbnail, let url = URL(string: thumb) {
                            AsyncImage(url: url) { phase in
                                if let img = phase.image {
                                    img.resizable().scaledToFill()
                                        .frame(width: 240, height: 140)
                                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                }
                            }
                        }
                        
                        Image(systemName: "play.fill")
                            .font(.system(size: 26))
                            .foregroundColor(.white)
                            .padding(14)
                            .background(Circle().fill(Color.black.opacity(0.6)))
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Up Next")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color(red: 0.10, green: 0.68, blue: 1.0))
                            .textCase(.uppercase)
                        
                        Text("S\(next.season) · E\(next.episode): \(next.title)")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        if let overview = next.overview, !overview.isEmpty {
                            Text(overview)
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(2)
                        }
                        
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 14))
                            Text("Play Next Episode")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(focusedCardID == "upNext" ? Color.black : Color.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(focusedCardID == "upNext" ? Color.white : Color.white.opacity(0.2))
                        )
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: 500, alignment: .leading)
                }
                .padding(14)
                .modifier(TvCardGlassBackground(isFocused: focusedCardID == "upNext", shape: RoundedRectangle(cornerRadius: 24, style: .continuous)))
                .shadow(color: focusedCardID == "upNext" ? Color.white.opacity(0.25) : Color.black.opacity(0.3), radius: focusedCardID == "upNext" ? 14 : 6, y: 3)
            }
            .buttonStyle(PosterCardButtonStyle())
            .focused($focusedCardID, equals: "upNext")
            .focusEffectDisabledIfAvailable()
            .scaleEffect(focusedCardID == "upNext" ? 1.03 : 1.0)
            .animation(.easeOut(duration: 0.14), value: focusedCardID == "upNext")
            .onExitCommand(perform: onDismiss)
            .onMoveCommand { direction in
                if direction == .up {
                    focusedCardID = nil
                    focusedTab = viewModel.selectedTab
                }
            }
            .padding(.horizontal, 60)
        } else {
            Text("No upcoming episode")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, 60)
        }
    }
    
    // MARK: - Focus Management
    
    private func focusFirstCard() {
        switch viewModel.selectedTab {
        case .scene:
            if viewModel.snapshot.actors.isEmpty, let song = viewModel.snapshot.song {
                focusedCardID = "song-\(song.id)"
            } else if let firstActor = viewModel.snapshot.actors.first {
                focusedCardID = "actor-\(firstActor.id)"
            } else if let song = viewModel.snapshot.song {
                focusedCardID = "song-\(song.id)"
            } else {
                focusedTab = viewModel.selectedTab
            }
        case .upNext:
            if viewModel.nextEpisode != nil {
                focusedCardID = "upNext"
            } else {
                focusedTab = viewModel.selectedTab
            }
        case .info:
            focusedTab = viewModel.selectedTab
        }
    }
}
