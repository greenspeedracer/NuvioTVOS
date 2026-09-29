import SwiftUI

struct SceneSongCard: View {
    let song: SceneRecognizedSong
    let onSelect: () -> Void
    
    @FocusState private var isFocused: Bool
    
    init(song: SceneRecognizedSong, onSelect: @escaping () -> Void) {
        self.song = song
        self.onSelect = onSelect
    }
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 20) {
                // Album artwork
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 140, height: 140)
                    
                    if let url = song.artworkURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 140, height: 140)
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            case .failure, .empty:
                                musicPlaceholder
                            @unknown default:
                                musicPlaceholder
                            }
                        }
                    } else {
                        musicPlaceholder
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(isFocused ? Color.white : Color.white.opacity(0.18), lineWidth: isFocused ? 2.5 : 1)
                )
                
                // Song Title, Artist, & Shazam/Music info
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "music.note")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.blue)
                        Text("Music")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                            .textCase(.uppercase)
                    }
                    
                    Text(song.title)
                        .font(.system(size: 21, weight: .bold))
                        .foregroundColor(isFocused ? .white : .white.opacity(0.95))
                        .lineLimit(2)
                    
                    Text(song.artist)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)
                    
                    if let desc = song.sceneDescription, !desc.isEmpty {
                        Text(desc)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.white.opacity(0.65))
                            .lineLimit(1)
                    } else if let genre = song.genres.first, !genre.isEmpty {
                        Text(genre)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(width: 440, height: 188)
            .modifier(TvCardGlassBackground(isFocused: isFocused, shape: RoundedRectangle(cornerRadius: 24, style: .continuous)))
            .shadow(color: isFocused ? Color.white.opacity(0.25) : Color.black.opacity(0.3), radius: isFocused ? 14 : 6, y: 3)
        }
        .buttonStyle(PosterCardButtonStyle())
        .focused($isFocused)
        .focusEffectDisabledIfAvailable()
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.easeOut(duration: 0.14), value: isFocused)
        .accessibilityLabel("\(song.title), \(song.artist)")
    }
    
    private var musicPlaceholder: some View {
        Image(systemName: "music.quarternote.3")
            .resizable()
            .scaledToFit()
            .frame(width: 54, height: 54)
            .foregroundColor(.white.opacity(0.4))
    }
}
