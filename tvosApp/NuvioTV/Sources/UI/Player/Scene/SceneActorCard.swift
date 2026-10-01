import SwiftUI

struct SceneActorCard: View {
    let actor: SceneRecognizedActor
    let isLiveRecognized: Bool
    let onSelect: () -> Void
    
    @Environment(\.isFocused) private var isFocused: Bool
    
    init(actor: SceneRecognizedActor, isLiveRecognized: Bool = false, onSelect: @escaping () -> Void) {
        self.actor = actor
        self.isLiveRecognized = isLiveRecognized
        self.onSelect = onSelect
    }
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 12) {
                // Circular portrait with optional active glowing ring
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 76, height: 76)
                    
                    if let url = actor.profileURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 76, height: 76)
                                    .clipShape(Circle())
                            case .failure, .empty:
                                placeholderAvatar
                            @unknown default:
                                placeholderAvatar
                            }
                        }
                    } else {
                        placeholderAvatar
                    }
                }
                .overlay(
                    Circle()
                        .stroke(
                            isFocused ? Color.white.opacity(0.9) : Color.white.opacity(0.18),
                            lineWidth: isFocused ? 2 : 1
                        )
                )
                
                // Name & Character labels
                VStack(spacing: 3) {
                    Text(actor.name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                    
                    if let character = actor.character, !character.isEmpty {
                        Text(character)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white.opacity(0.72))
                            .lineLimit(1)
                            .multilineTextAlignment(.center)
                    } else {
                        Text(" ")
                            .font(.system(size: 15, weight: .medium))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 10)
            .frame(width: 174, height: 188)
            .modifier(TvCardGlassBackground(isFocused: isFocused, shape: RoundedRectangle(cornerRadius: 24, style: .continuous)))
            .shadow(color: isFocused ? Color.white.opacity(0.25) : Color.black.opacity(0.3), radius: isFocused ? 14 : 6, y: 3)
        }
        .buttonStyle(PosterCardButtonStyle())
        .focusEffectDisabledIfAvailable()
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.easeOut(duration: 0.14), value: isFocused)
        .accessibilityLabel("\(actor.name), \(actor.character ?? "")")
    }
    
    private var placeholderAvatar: some View {
        Image(systemName: "person.fill")
            .resizable()
            .scaledToFit()
            .frame(width: 38, height: 38)
            .foregroundColor(.white.opacity(0.4))
    }
}
