import Foundation

struct Trastada: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    let elves: [String]
    let difficulty: String
    let time: String
    let materialsType: String
    let cleanup: String
    let materials: String
    let preparation: String
    /// Campos que llegan desde Supabase (el JSON de la app no los tiene).
    var tags: [String]?
    var imagePath: String?
    /// Día (1–24) en que sale por defecto en el calendario inicial, según el modo de elfos.
    var defaultDayOneElf: Int?
    var defaultDayTwoElves: Int?

    func defaultDay(twoElves: Bool) -> Int? { twoElves ? defaultDayTwoElves : defaultDayOneElf }

    var materialTags: [String] {
        if let tags { return tags }
        return materials
            .replacingOccurrences(of: #"\s+(?:y|e)\s+"#, with: ",", options: [.regularExpression, .caseInsensitive])
            .components(separatedBy: CharacterSet(charactersIn: ",;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func similarity(to other: Trastada) -> Int {
        let sharedMaterials = Set(materialTags.map { $0.lowercased() })
            .intersection(other.materialTags.map { $0.lowercased() })
        return sharedMaterials.count * 5
            + (Set(elves).isDisjoint(with: other.elves) ? 0 : 3)
            + (materialsType == other.materialsType ? 2 : 0)
            + (difficulty == other.difficulty ? 2 : 0)
            + (time == other.time ? 1 : 0)
    }

    func options(for filter: CatalogFilter) -> [String] {
        switch filter {
        case .elves: elves
        case .difficulty: [difficulty]
        case .time: [time]
        case .materials: [materialsType]
        case .cleanup: [cleanup]
        }
    }
}

enum CatalogFilter: String, CaseIterable, Identifiable, Codable {
    case elves = "Elfos"
    case difficulty = "Dificultad"
    case time = "Tiempo"
    case materials = "Materiales"
    case cleanup = "Limpieza"
    var id: Self { self }

    var options: [String] {
        switch self {
        case .elves: ["1 elfo", "2 elfos"]
        case .difficulty: ["Fácil", "Media", "Elaborada"]
        case .time: ["Hasta 5 min", "6–15 min", "Más de 15 min"]
        case .materials: ["Habituales de casa", "Específicos"]
        case .cleanup: ["Mínima", "Requiere recoger"]
        }
    }
}

struct CatalogFilters: Equatable {
    var selections: [CatalogFilter: Set<String>]

    init(_ values: [CatalogFilter: Set<String>] = [:]) {
        let elves = values[.elves] == ["2 elfos"] ? "2 elfos" : "1 elfo"
        selections = [.elves: [elves]]

    }

    func matches(_ idea: Trastada) -> Bool {
        selections.allSatisfy { group, choices in
            !choices.isDisjoint(with: idea.options(for: group))
        }
    }

    mutating func toggle(_ option: String, in group: CatalogFilter) {
        var choices = selections[group] ?? []
        if !choices.insert(option).inserted { choices.remove(option) }
        selections[group] = choices.isEmpty || choices.count == group.options.count ? nil : choices
    }
}

enum TravesuraOutcome: String, Codable, CaseIterable {
    case incredible, disaster, skipped, completed
    var title: String {
        switch self {
        case .incredible: "Increíble"
        case .disaster: "Un desastre"
        case .skipped: "No la hice"
        case .completed: "Travesura completada"
        }
    }
}

struct TravesuraReview: Codable {
    let ideaID: String
    let outcome: TravesuraOutcome
}

struct DecemberPlan: Codable {
    var assignments: [Int: String] = [:]
    var deckOrder: [String] = []
    var reviews: [Int: TravesuraReview]?

    mutating func review(day: Int, outcome: TravesuraOutcome) {
        guard reviews?[day] == nil, let id = assignments[day] else { return }
        if reviews == nil { reviews = [:] }
        reviews?[day] = TravesuraReview(ideaID: id, outcome: outcome)
        if outcome == .skipped { assignments.removeValue(forKey: day) }
    }

    mutating func markCompleted(day: Int) {
        guard let id = assignments[day] ?? reviews?[day]?.ideaID else { return }
        if reviews == nil { reviews = [:] }
        reviews?[day] = TravesuraReview(ideaID: id, outcome: .completed)
        if assignments[day] == nil, !assignments.values.contains(id) {
            assignments[day] = id
        }
    }

    mutating func unmarkCompleted(day: Int) {
        guard let review = reviews?[day], review.outcome != .skipped else { return }
        // Keep the historical card if its idea has since been assigned elsewhere.
        if assignments[day] == nil {
            reviews?[day] = TravesuraReview(ideaID: review.ideaID, outcome: .skipped)
        } else {
            reviews?[day] = nil
        }
    }

    mutating func fillStarterDays(from catalog: [Trastada], matching filters: CatalogFilters, days: ClosedRange<Int> = 1...24) {
        let illustratedIDs = Set(catalog.map(\.id))
        for day in days {
            if let id = assignments[day], !illustratedIDs.contains(id) {
                assignments.removeValue(forKey: day)
            }
        }
        // Primero, las travesuras que tienen día asignado por defecto en Supabase para este modo de elfos.
        let twoElves = filters.selections[.elves] == ["2 elfos"]
        let scheduled = catalog
            .compactMap { idea in idea.defaultDay(twoElves: twoElves).map { ($0, idea.id) } }
            .sorted { $0.0 < $1.0 }
        for (day, id) in scheduled where days.contains(day)
            && assignments[day] == nil && reviews?[day] == nil && !assignments.values.contains(id) {
            assignments[day] = id
        }
        let assigned = Set(assignments.values)
        let available = catalog.filter { !assigned.contains($0.id) }
        let ordered = available.filter(filters.matches) + available.filter { !filters.matches($0) }
        let emptyDays = days.filter { assignments[$0] == nil && reviews?[$0] == nil }
        for (day, idea) in zip(emptyDays, ordered) { assignments[day] = idea.id }
    }

    func deck(from catalog: [Trastada]) -> [Trastada] {
        let lookup = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        let ordered = Set(deckOrder)
        let assigned = Set(assignments.values)
        return (deckOrder.compactMap { lookup[$0] } + catalog.filter { !ordered.contains($0.id) })
            .filter { !assigned.contains($0.id) }
    }

    mutating func pass(_ id: String, catalog: [Trastada]) {
        deckOrder = deck(from: catalog).map(\.id).filter { $0 != id } + [id]
    }

    mutating func assign(_ id: String, to day: Int, catalog: [Trastada]) {
        let displaced = assignments[day]
        assignments = assignments.filter { $0.value != id }
        assignments[day] = id
        if let displaced, displaced != id { pass(displaced, catalog: catalog) }
    }

    mutating func remove(from day: Int, catalog: [Trastada]) {
        if let id = assignments.removeValue(forKey: day) { pass(id, catalog: catalog) }
    }
}

struct DecemberEdition {
    static let pages = 1...24

    let year: Int
    var calendar = Calendar(identifier: .gregorian)

    func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: 12, day: day))!
    }

    func today(_ now: Date) -> Int? {
        (1...24).first { calendar.isDate(date($0), inSameDayAs: now) }
    }

    func canEdit(_ day: Int, now: Date) -> Bool {
        (1...24).contains(day) && date(day) >= calendar.startOfDay(for: now)
    }

    func reminderDate(for day: Int, hour: Int, minute: Int) -> Date? {
        guard let eve = calendar.date(byAdding: .day, value: -1, to: date(day)) else { return nil }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: eve)
    }

    func nextDiscovery(_ now: Date) -> Int? {
        if let today = today(now), today < 24 { return today + 1 }
        if let eve = reminderDate(for: 1, hour: 0, minute: 0),
           calendar.isDate(eve, inSameDayAs: now) { return 1 }
        return nil
    }

    func calendarDate(for page: Int) -> Date {
        calendar.date(byAdding: .day, value: page - 1, to: date(1))!
    }

    func stripFocus(_ now: Date) -> Int {
        if let day = Self.pages.first(where: { calendar.isDate(calendarDate(for: $0), inSameDayAs: now) }) {
            return day
        }
        return now < date(1) ? Self.pages.lowerBound : Self.pages.upperBound
    }
}
