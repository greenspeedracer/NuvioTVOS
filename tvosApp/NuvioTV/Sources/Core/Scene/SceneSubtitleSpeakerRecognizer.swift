import Foundation

struct SceneSubtitleSpeakerRecognizer: Sendable {
    
    /// Extracts speaker names from subtitle text and matches them against candidate cast members.
    static func detectSpeakers(
        in subtitleText: String,
        candidates: [SceneCastCandidate]
    ) -> [SceneCastCandidate] {
        let trimmed = subtitleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !candidates.isEmpty else { return [] }
        
        let speakerTags = extractSpeakerTags(from: trimmed)
        guard !speakerTags.isEmpty else { return [] }
        
        var matchedCandidates: [SceneCastCandidate] = []
        var seenIDs = Set<String>()
        
        for tag in speakerTags {
            if let candidate = matchSpeakerTag(tag, against: candidates) {
                if seenIDs.insert(candidate.id).inserted {
                    matchedCandidates.append(candidate)
                }
            }
        }
        
        return matchedCandidates
    }
    
    static func extractSpeakerTags(from text: String) -> [String] {
        let stripped = stripFormatting(text)
        var tags: [String] = []
        
        // 1. Bracketed tags: e.g. [President Curtis], [Curtis]:, [Curtis chuckles], >> [Curtis]
        let bracketPattern = "\\[([A-Za-z0-9\\s\\.\\'\\-]{2,50})\\]"
        if let regex = try? NSRegularExpression(pattern: bracketPattern) {
            let nsStr = stripped as NSString
            let matches = regex.matches(in: stripped, range: NSRange(location: 0, length: nsStr.length))
            for match in matches where match.numberOfRanges > 1 {
                let tag = nsStr.substring(with: match.range(at: 1))
                tags.append(tag)
            }
        }
        
        // 2. Parentheses tags: e.g. (President Curtis), (Curtis):
        let parenPattern = "\\(([A-Za-z0-9\\s\\.\\'\\-]{2,50})\\):?"
        if let regex = try? NSRegularExpression(pattern: parenPattern) {
            let nsStr = stripped as NSString
            let matches = regex.matches(in: stripped, range: NSRange(location: 0, length: nsStr.length))
            for match in matches where match.numberOfRanges > 1 {
                let tag = nsStr.substring(with: match.range(at: 1))
                tags.append(tag)
            }
        }
        
        // 3. Colon prefix: e.g. "President Curtis: As for your mother", "- Summer: Dad!", ">> CURTIS: Yes"
        let lines = stripped.components(separatedBy: .newlines)
        let colonPattern = "^(?:>{1,3}\\s*)?(?:-\\s*)?([A-Za-z0-9\\s\\.\\'\\-]{2,40}):\\s+"
        if let regex = try? NSRegularExpression(pattern: colonPattern) {
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let nsLine = trimmed as NSString
                if let match = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: nsLine.length)),
                   match.numberOfRanges > 1 {
                    let tag = nsLine.substring(with: match.range(at: 1))
                    // Avoid matching time codes like "00:01" or URLs
                    if !tag.allSatisfy({ $0.isNumber || $0 == ":" }) {
                        tags.append(tag)
                    }
                }
            }
        }
        
        return tags
    }
    
    static func matchSpeakerTag(
        _ tag: String,
        against candidates: [SceneCastCandidate]
    ) -> SceneCastCandidate? {
        let normalizedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedTag.isEmpty else { return nil }
        
        // 1. Direct actor name match (e.g. subtitle says "Keith David:" or "[Keith David]")
        if let match = candidates.first(where: {
            $0.name.lowercased() == normalizedTag ||
            normalizedTag.contains($0.name.lowercased())
        }) {
            return match
        }
        
        // 2. Character name match
        for candidate in candidates {
            guard let rawCharacter = candidate.character, !rawCharacter.isEmpty else { continue }
            let characterAliases = generateCharacterAliases(rawCharacter)
            
            for alias in characterAliases {
                let aliasLower = alias.lowercased()
                // Exact match: "president curtis" == "president curtis"
                if aliasLower == normalizedTag {
                    return candidate
                }
                // Tag contains full alias: "[president curtis sighs]" or "president curtis speaks"
                if normalizedTag.contains(aliasLower) && aliasLower.count >= 4 {
                    return candidate
                }
                // Alias contains tag if tag is a distinctive single name (e.g. "curtis" in "president curtis", "summer" in "summer smith")
                let tokens = aliasLower.components(separatedBy: .whitespaces)
                if tokens.contains(normalizedTag) && normalizedTag.count >= 3 {
                    return candidate
                }
            }
        }
        
        return nil
    }
    
    static func generateCharacterAliases(_ raw: String) -> [String] {
        let cleaned = raw
            .replacingOccurrences(of: "(voice)", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "(uncredited)", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let parts = cleaned.components(separatedBy: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        var aliases: [String] = []
        for part in parts {
            aliases.append(part)
            let strippedHonorifics = part
                .replacingOccurrences(of: "Special Agent ", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "Agent ", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "President ", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "Officer ", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "Dr. ", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "Doctor ", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !strippedHonorifics.isEmpty && strippedHonorifics != part {
                aliases.append(strippedHonorifics)
            }
        }
        return aliases
    }
    
    static func stripFormatting(_ text: String) -> String {
        var result = text
        // HTML / WebVTT formatting tags: <i>, </b>, <c.color>, etc.
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // ASS override tags: {\an8}, {\pos(100,200)}, etc.
        result = result.replacingOccurrences(of: "\\{[^\\}]+\\}", with: "", options: .regularExpression)
        return result
    }
}
