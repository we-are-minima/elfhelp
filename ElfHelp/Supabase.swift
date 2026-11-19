import Foundation
import Security
import UIKit

// MARK: - Configuración

enum SupabaseConfig {
    static let url = URL(string: "https://vledhoswxfxktdnylzaw.supabase.co")!
    /// Clave pública (publishable). Es segura dentro de la app porque las tablas tienen RLS.
    static let publishableKey = "sb_publishable_dFNyV3GbW7QLAR2PrcvchA_VqerDikW"
    static let imageBucket = "travesuras"

    static func endpoint(_ path: String, query: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: url.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        return components.url!
    }
}

enum SupabaseError: Error {
    case badResponse(Int)
}

private func checkedData(for request: URLRequest) async throws -> Data {
    let (data, response) = try await URLSession.shared.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200..<300).contains(status) else { throw SupabaseError.badResponse(status) }
    return data
}

// MARK: - Catálogo

/// Fila de la tabla `travesuras` tal y como la devuelve Supabase.
struct RemoteTravesura: Decodable {
    let id: String
    let title: String
    let description: String?
    let image_path: String?
    let materials: [String]
    let steps: [String]
    let elf_counts: [Int]
    let difficulty: String?
}

extension Trastada {
    init(remote: RemoteTravesura) {
        let difficulty: String
        switch remote.difficulty {
        case "medium": difficulty = "Media"
        case "hard": difficulty = "Elaborada"
        default: difficulty = "Fácil"
        }
        let elves = remote.elf_counts.sorted().map { $0 == 1 ? "1 elfo" : "2 elfos" }
        self.init(
            id: remote.id,
            title: remote.title,
            symbol: "sparkles",
            elves: elves.isEmpty ? ["1 elfo"] : elves,
            difficulty: difficulty,
            time: "",
            materialsType: "",
            cleanup: "",
            materials: remote.materials.joined(separator: ", "),
            preparation: remote.steps.joined(separator: " "),
            tags: remote.materials,
            imagePath: remote.image_path,
            details: remote.description
        )
    }
}

/// Catálogo de travesuras: arranca con la última copia guardada (o el JSON de la app)
/// y se actualiza desde Supabase cada vez que la app se abre.
@MainActor
final class CatalogStore: ObservableObject {
    static let shared = CatalogStore()

    @Published private(set) var items: [Trastada]
    private var refreshing = false

    private init() {
        items = Self.cachedCatalog() ?? Self.bundledCatalog()
    }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            var request = URLRequest(url: SupabaseConfig.endpoint("rest/v1/travesuras", query: [
                URLQueryItem(name: "select", value: "id,title,description,image_path,materials,steps,elf_counts,difficulty"),
                URLQueryItem(name: "order", value: "id"),
            ]))
            request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
            request.timeoutInterval = 15
            let data = try await checkedData(for: request)
            let remote = try JSONDecoder().decode([RemoteTravesura].self, from: data)
            // Si la tabla viniera vacía por error, mantenemos lo que ya teníamos.
            guard !remote.isEmpty else { return }
            let catalog = remote.map(Trastada.init(remote:))
            await RemoteArtwork.prefetch(catalog)
            items = catalog
            Self.saveCache(catalog)
        } catch {
            // Sin conexión o error: seguimos con la copia local.
        }
    }

    private static var cacheURL: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("catalog-cache.json")
    }

    private static func cachedCatalog() -> [Trastada]? {
        guard let data = try? Data(contentsOf: cacheURL),
              let catalog = try? JSONDecoder().decode([Trastada].self, from: data),
              !catalog.isEmpty else { return nil }
        return catalog
    }

    private static func saveCache(_ catalog: [Trastada]) {
        guard let data = try? JSONEncoder().encode(catalog) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    private static func bundledCatalog() -> [Trastada] {
        guard let url = Bundle.main.url(forResource: "Catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Trastada].self, from: data)) ?? []
    }
}

// MARK: - Imágenes remotas

/// Imágenes que no están en Assets: se descargan del bucket `travesuras` y se guardan en caché.
enum RemoteArtwork {
    private static var folder: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let folder = caches.appendingPathComponent("travesuras-images", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func fileURL(for path: String) -> URL {
        let safeName = path.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        return folder.appendingPathComponent(safeName)
    }

    private static func remoteURL(for path: String) -> URL? {
        if path.hasPrefix("http") { return URL(string: path) }
        return SupabaseConfig.endpoint("storage/v1/object/public/\(SupabaseConfig.imageBucket)/\(path)")
    }

    private static func needsDownload(_ path: String) -> Bool {
        UIImage(named: path) == nil && !FileManager.default.fileExists(atPath: fileURL(for: path).path)
    }

    static func image(for idea: Trastada) -> UIImage? {
        guard let path = idea.imagePath else { return nil }
        return UIImage(contentsOfFile: fileURL(for: path).path)
    }

    static func prefetch(_ catalog: [Trastada]) async {
        let paths = Set(catalog.compactMap(\.imagePath)).filter(needsDownload)
        await withTaskGroup(of: Void.self) { group in
            for path in paths {
                group.addTask {
                    guard let url = remoteURL(for: path),
                          let data = try? await checkedData(for: URLRequest(url: url)),
                          UIImage(data: data) != nil else { return }
                    try? data.write(to: fileURL(for: path), options: .atomic)
                }
            }
        }
    }
}

// MARK: - Usuario anónimo

private struct StoredSession: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let userID: String
}

private struct AuthResponse: Decodable {
    struct User: Decodable { let id: String }
    let access_token: String
    let refresh_token: String
    let expires_in: Double
    let user: User
}

/// Crea un usuario anónimo la primera vez y renueva su sesión cuando caduca.
actor SupabaseAuth {
    static let shared = SupabaseAuth()

    private let keychainAccount = "supabase-session"

    fileprivate func session() async throws -> StoredSession {
        if let stored = load() {
            if stored.expiresAt > Date().addingTimeInterval(60) { return stored }
            if let refreshed = try? await authenticate(
                path: "auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
                body: ["refresh_token": stored.refreshToken]
            ) { return refreshed }
        }
        return try await authenticate(path: "auth/v1/signup", body: [:])
    }

    private func authenticate(path: String, query: [URLQueryItem] = [], body: [String: String]) async throws -> StoredSession {
        var request = URLRequest(url: SupabaseConfig.endpoint(path, query: query))
        request.httpMethod = "POST"
        request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let response = try JSONDecoder().decode(AuthResponse.self, from: try await checkedData(for: request))
        let session = StoredSession(
            accessToken: response.access_token,
            refreshToken: response.refresh_token,
            expiresAt: Date().addingTimeInterval(response.expires_in),
            userID: response.user.id
        )
        save(session)
        return session
    }

    // Keychain

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Bundle.main.bundleIdentifier ?? "ElfHelp",
         kSecAttrAccount as String: keychainAccount]
    }

    private func load() -> StoredSession? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(StoredSession.self, from: data)
    }

    private func save(_ session: StoredSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }
}

// MARK: - Sincronización del calendario

/// Copia el calendario del móvil a `user_mischiefs` para poder ver las travesuras más elegidas.
/// El calendario sigue viviendo en el móvil; esto es solo una copia.
@MainActor
final class PlanSync {
    static let shared = PlanSync()
    private var pending: Task<Void, Never>?

    func schedule(_ planData: Data, year: Int) {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled,
                  let plan = try? JSONDecoder().decode(DecemberPlan.self, from: planData) else { return }
            try? await Self.upload(plan, year: year)
        }
    }

    private struct Row: Encodable {
        let user_id: String
        let travesura_id: String
        let status: String
        let assigned_date: String?
        let outcome: String?
        let updated_at: String
    }

    private static func upload(_ plan: DecemberPlan, year: Int) async throws {
        let session = try await SupabaseAuth.shared.session()
        let now = ISO8601DateFormatter().string(from: Date())
        func date(_ day: Int) -> String { String(format: "%04d-12-%02d", year, day) }

        // Prioridad si una travesura aparece varias veces: hecha > asignada > saltada.
        var rows: [String: Row] = [:]
        func rank(_ row: Row) -> Int { row.status == "done" ? 3 : row.status == "assigned" ? 2 : 1 }
        func add(_ row: Row) {
            if let existing = rows[row.travesura_id], rank(existing) >= rank(row) { return }
            rows[row.travesura_id] = row
        }
        for (day, review) in plan.reviews ?? [:] {
            let skipped = review.outcome == .skipped
            add(Row(user_id: session.userID, travesura_id: review.ideaID,
                    status: skipped ? "available" : "done",
                    assigned_date: skipped ? nil : date(day),
                    outcome: review.outcome.rawValue, updated_at: now))
        }
        for (day, id) in plan.assignments where plan.reviews?[day] == nil {
            add(Row(user_id: session.userID, travesura_id: id, status: "assigned",
                    assigned_date: date(day), outcome: nil, updated_at: now))
        }

        func request(_ url: URL, method: String) -> URLRequest {
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
            return request
        }

        // 1. Guardar o actualizar las filas actuales.
        if !rows.isEmpty {
            var upsert = request(SupabaseConfig.endpoint("rest/v1/user_mischiefs", query: [
                URLQueryItem(name: "on_conflict", value: "user_id,travesura_id"),
            ]), method: "POST")
            upsert.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
            upsert.httpBody = try JSONEncoder().encode(Array(rows.values))
            _ = try await checkedData(for: upsert)
        }

        // 2. Borrar las que ya no están en el calendario.
        var filters = [URLQueryItem(name: "user_id", value: "eq.\(session.userID)")]
        if !rows.isEmpty {
            let ids = rows.keys.sorted().map { "\"\($0)\"" }.joined(separator: ",")
            filters.append(URLQueryItem(name: "travesura_id", value: "not.in.(\(ids))"))
        }
        _ = try await checkedData(for: request(SupabaseConfig.endpoint("rest/v1/user_mischiefs", query: filters), method: "DELETE"))
    }
}
