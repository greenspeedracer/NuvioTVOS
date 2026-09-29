import Foundation

struct SceneSubtitleMusicRecognizer: Sendable {
    
    /// Detects song cues in subtitle text and returns a recognized song model with interval timing if found.
    static func detectSong(
        in text: String,
        startTime: Double,
        endTime: Double,
        canonicalId: String
    ) -> SceneRecognizedSong? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        let stripped = stripFormatting(trimmed)
        guard isLikelyMusicCue(stripped) else { return nil }
        
        guard let (title, artist) = parseSongAndArtist(from: stripped) else {
            return nil
        }
        
        let cleanedTitle = formatTitleOrArtist(title)
        let cleanedArtist = formatTitleOrArtist(artist ?? "Original Soundtrack")
        
        guard !cleanedTitle.isEmpty, cleanedTitle.count >= 2 else { return nil }
        
        let songId = "\(canonicalId)-\(cleanedTitle.lowercased())-\(cleanedArtist.lowercased())"
            .replacingOccurrences(of: " ", with: "-")
        
        return SceneRecognizedSong(
            id: songId,
            title: cleanedTitle,
            artist: cleanedArtist,
            observedSourceTime: startTime,
            startTime: startTime,
            endTime: max(endTime, startTime + 15.0),
            sceneDescription: "Identified from scene subtitle cue"
        )
    }
    
    private static func formatTitleOrArtist(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: CharacterSet(charactersIn: " \"'“”’[]():-–—♪♫#\n\t"))
        if trimmed == trimmed.uppercased() && trimmed.count >= 3 && trimmed.rangeOfCharacter(from: .letters) != nil {
            return trimmed.capitalized
        }
        return trimmed
    }
    
    private static func isLikelyMusicCue(_ text: String) -> Bool {
        let musicSymbols = ["♪", "♫", "&#9834;", "&#9835;", "♬", "♩"]
        if musicSymbols.contains(where: { text.contains($0) }) {
            return true
        }
        
        let lower = text.lowercased()
        let keywords = [
            "[playing", "(playing", "[music:", "(music:", "[song:", "(song:",
            "plays]", "plays)", "playing]", "playing)", "theme song",
            "soundtrack", "- music", "singing]"
        ]
        return keywords.contains(where: { lower.contains($0) })
    }
    
    private static func parseSongAndArtist(from text: String) -> (title: String, artist: String?)? {
        let cleaned = cleanMusicDecorations(text)
        guard !cleaned.isEmpty else { return nil }
        
        // Pattern 1: Quoted title followed by "by" artist: e.g. "God Save the Queen" by Sex Pistols
        let quotedByPattern = "[\"“](.+?)[\"”](?:\\s+by\\s+|\\s*-\\s*)([A-Za-z0-9\\s\\.\\'\\-&]{2,50})"
        if let match = regexMatch(pattern: quotedByPattern, text: cleaned, options: .caseInsensitive) {
            return (title: match[1], artist: match[2])
        }
        
        // Pattern 2: Title by Artist: e.g. God Save the Queen by Sex Pistols
        let byPattern = "^([A-Za-z0-9\\s\\.\\'\\-]{2,50})\\s+by\\s+([A-Za-z0-9\\s\\.\\'\\-&]{2,50})"
        if let match = regexMatch(pattern: byPattern, text: cleaned, options: .caseInsensitive) {
            return (title: match[1], artist: match[2])
        }
        
        // Pattern 3: Artist - Title: e.g. Sex Pistols - God Save the Queen
        let dashPattern = "^([A-Za-z0-9\\s\\.\\'\\-&]{2,40})\\s*[-–—:]\\s*[\"“]?([A-Za-z0-9\\s\\.\\'\\-&]{2,50})[\"”]?"
        if let match = regexMatch(pattern: dashPattern, text: cleaned, options: .caseInsensitive) {
            let part1 = match[1].trimmingCharacters(in: .whitespaces)
            let part2 = match[2].trimmingCharacters(in: .whitespaces)
            let lower1 = part1.lowercased()
            if lower1 == "playing" || lower1 == "music" || lower1 == "song" {
                return (title: part2, artist: nil)
            }
            return (title: part2, artist: part1)
        }
        
        // Pattern 4: [Playing "God Save the Queen"] or [Song: "God Save the Queen"]
        let playingQuotedPattern = "(?:playing|song|music)[:\\s]+[\"“]([A-Za-z0-9\\s\\.\\'\\-&]{2,50})[\"”]"
        if let match = regexMatch(pattern: playingQuotedPattern, text: cleaned, options: .caseInsensitive) {
            return (title: match[1], artist: nil)
        }
        
        // Pattern 5: Inside quotes alone: e.g. ♪ "God Save the Queen" ♪
        let quotesOnlyPattern = "[\"“]([A-Za-z0-9\\s\\.\\'\\-&]{2,50})[\"”]"
        if let match = regexMatch(pattern: quotesOnlyPattern, text: cleaned, options: .caseInsensitive) {
            let candidate = match[1].trimmingCharacters(in: .whitespaces)
            if candidate.count >= 3 && !candidate.lowercased().contains("groan") && !candidate.lowercased().contains("laugh") {
                return (title: candidate, artist: nil)
            }
        }
        
        // Pattern 6: Descriptive music cues: e.g. "punk rock music", "upbeat music", "theme song"
        let lowerCleaned = cleaned.lowercased()
        if lowerCleaned.contains("music") || lowerCleaned.contains("song") || lowerCleaned.contains("theme") {
            let desc = cleaned.replacingOccurrences(of: "playing", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "plays", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if desc.count >= 3 && desc.count <= 40 {
                return (title: formatTitleOrArtist(desc), artist: "Original Soundtrack")
            }
        }
        
        return nil
    }
    
    private static func cleanMusicDecorations(_ raw: String) -> String {
        var str = raw
        let symbols = ["♪", "♫", "&#9834;", "&#9835;", "♬", "♩"]
        for s in symbols {
            str = str.replacingOccurrences(of: s, with: " ")
        }
        str = str.trimmingCharacters(in: CharacterSet(charactersIn: "[]() \t\n\r"))
        
        // Remove trailing "plays" or "playing"
        if let range = str.range(of: " plays", options: [.caseInsensitive, .backwards]), range.upperBound == str.endIndex {
            str = String(str[..<range.lowerBound])
        }
        if let range = str.range(of: " playing", options: [.caseInsensitive, .backwards]), range.upperBound == str.endIndex {
            str = String(str[..<range.lowerBound])
        }
        
        return str.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private static func regexMatch(
        pattern: String,
        text: String,
        options: NSRegularExpression.Options = []
    ) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let nsStr = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsStr.length)) else { return nil }
        
        var results: [String] = []
        for i in 0..<match.numberOfRanges {
            let range = match.range(at: i)
            if range.location != NSNotFound {
                results.append(nsStr.substring(with: range))
            } else {
                results.append("")
            }
        }
        return results
    }
    
    private static func stripFormatting(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\{[^\\}]+\\}", with: "", options: .regularExpression)
        return result
    }
}
