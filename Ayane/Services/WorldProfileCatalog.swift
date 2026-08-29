import Foundation

/// Pure value helpers for the reusable world-profile catalog.
///
/// The catalog deliberately has no ModelContext, UserDefaults, or networking
/// dependency. Callers can therefore use the exact same deterministic match
/// rule in previews, import validation, and production selection.
enum WorldProfileCatalog {
    /// Returns one deterministic winner per world ID. Different IDs remain
    /// independent and are sorted by their UUID string.
    static func canonicalWorldProfiles(
        _ values: [AyaneWorldProfileExport]
    ) -> [AyaneWorldProfileExport] {
        SchemaV11DataSupport.canonicalWorldProfiles(values)
    }

    /// Selects the world most related to a role's name and persona prompt.
    /// A positive score is required for a match. With no clear hit, the stable
    /// legacy reality world wins when present; otherwise the first canonical
    /// world (UUID order) is returned.
    static func bestMatchID(
        roleName: String,
        prompt: String,
        worlds: [AyaneWorldProfileExport]
    ) -> UUID {
        let canonical = canonicalWorldProfiles(worlds)
        guard !canonical.isEmpty else { return WorldProfileRecord.realityID }

        let query = normalize([roleName, prompt].joined(separator: " "))
        let queryTerms = terms(in: query)
        let scored = canonical.map { world in
            (world, score(query: query, queryTerms: queryTerms, world: world))
        }

        if let winner = scored
            .filter({ $0.1 > 0 })
            .sorted(by: { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return stableWorldLess(lhs.0, rhs.0)
            })
            .first {
            return winner.0.id
        }

        return canonical.first(where: { $0.id == WorldProfileRecord.realityID })?.id
            ?? canonical[0].id
    }

    private static func score(
        query: String,
        queryTerms: Set<String>,
        world: AyaneWorldProfileExport
    ) -> Int {
        let fields: [(String, Int)] = [
            (world.displayName, 8),
            (world.worldKind, 4),
            (world.locationContext, 3)
        ] + world.commonFacts.map { ($0, 2) }

        return fields.reduce(0) { total, field in
            total + fieldScore(
                query: query,
                queryTerms: queryTerms,
                field: normalize(field.0),
                weight: field.1
            )
        }
    }

    private static func fieldScore(
        query: String,
        queryTerms: Set<String>,
        field: String,
        weight: Int
    ) -> Int {
        guard !field.isEmpty else { return 0 }

        // Exact phrase hits are intentionally dominant. This makes a role
        // explicitly named after a world choose that world over incidental
        // overlap in a long facts list.
        if !field.isEmpty, !stopWords.contains(field), query.contains(field) {
            return weight * 100 + min(field.count, 50)
        }
        if !query.isEmpty, !stopWords.contains(query), field.contains(query) {
            return weight * 80 + min(query.count, 50)
        }

        let fieldTerms = terms(in: field)
        let overlap = queryTerms.intersection(fieldTerms)
        guard !overlap.isEmpty else { return 0 }
        let meaningful = overlap.filter { $0.count >= 2 && !stopWords.contains($0) }
        guard !meaningful.isEmpty else { return 0 }
        let lengthBonus = meaningful.map(\.count).max() ?? 0
        return weight * meaningful.count * 10 + min(lengthBonus, 20)
    }

    private static func stableWorldLess(
        _ lhs: AyaneWorldProfileExport,
        _ rhs: AyaneWorldProfileExport
    ) -> Bool {
        let leftID = lhs.id.uuidString.lowercased()
        let rightID = rhs.id.uuidString.lowercased()
        if leftID != rightID { return leftID < rightID }
        return lhs.displayName < rhs.displayName
    }

    private static let stopWords: Set<String> = [
        "的", "是", "在", "与", "和", "或", "我", "你", "他", "她", "它",
        "这", "那", "一个", "这个", "世界", "现实", "角色", "主人", "world",
        "the", "and", "or", "is", "a", "an", "of", "to", "in"
    ]

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Tokenizes Latin/number runs and CJK n-grams. CJK n-grams retain useful
    /// phrase overlap without relying on a language model or locale-specific
    /// dictionary, while short stop words are ignored at scoring time.
    private static func terms(in value: String) -> Set<String> {
        let scalars = Array(value.unicodeScalars)
        var result = Set<String>()
        var latin = ""

        func flushLatin() {
            guard !latin.isEmpty else { return }
            result.insert(latin)
            latin = ""
        }

        for scalar in scalars {
            if isCJK(scalar) {
                // CJK scalars are alphabetic too, so this check must happen
                // before `isAlphabetic`; otherwise the n-gram pass below
                // never receives any Chinese characters.
                flushLatin()
                result.insert(String(scalar))
                continue
            }
            if scalar.properties.isAlphabetic || scalar.properties.numericType != nil {
                latin.unicodeScalars.append(scalar)
                continue
            }
            flushLatin()
        }
        flushLatin()

        let cjk = scalars.filter(isCJK).map(String.init)
        guard cjk.count >= 2 else { return result }
        for length in 2...min(4, cjk.count) {
            for index in 0...(cjk.count - length) {
                result.insert(cjk[index..<(index + length)].joined())
            }
        }
        return result
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
            return true
        default:
            return false
        }
    }
}
