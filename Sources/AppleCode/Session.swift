import Foundation

struct Session: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    var updatedAt: Date
    var messages: [Message]
    var workingDir: String

    init(workingDir: String = FileManager.default.currentDirectoryPath) {
        self.id = UUID()
        self.createdAt = Date()
        self.updatedAt = Date()
        self.messages = []
        self.workingDir = workingDir
    }

    mutating func addMessage(role: String, content: String) {
        messages.append(Message(role: role, content: content))
        updatedAt = Date()
    }
}

struct Message: Codable {
    let role: String
    let content: String
}

@MainActor
final class SessionManager {
    static let shared = SessionManager()

    private let sessionsDir: URL
    private var currentSession: Session?

    private init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        sessionsDir = homeDir.appendingPathComponent(".apple-code/sessions")
        try? FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
    }

    func createSession(workingDir: String? = nil) -> Session {
        let dir = workingDir ?? FileManager.default.currentDirectoryPath
        let session = Session(workingDir: dir)
        currentSession = session
        return session
    }

    func currentSession_() -> Session? {
        return currentSession
    }

    func setCurrentSession(_ session: Session) {
        currentSession = session
    }

    func saveSession(_ session: Session) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(session)
        let url = sessionsDir.appendingPathComponent("\(session.id.uuidString).json")
        try data.write(to: url)
        currentSession = session
    }

    func loadSession(id: UUID) throws -> Session {
        let url = sessionsDir.appendingPathComponent("\(id.uuidString).json")
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let session = try decoder.decode(Session.self, from: data)
        currentSession = session
        return session
    }

    func listSessions() -> [SessionSummary] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: sessionsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        return contents.compactMap { url -> SessionSummary? in
            guard url.pathExtension == "json" else { return nil }
            guard let data = try? Data(contentsOf: url),
                  let session = try? JSONDecoder().decode(Session.self, from: data) else {
                return nil
            }
            return SessionSummary(
                id: session.id,
                createdAt: session.createdAt,
                updatedAt: session.updatedAt,
                messageCount: session.messages.count,
                workingDir: session.workingDir,
                preview: session.messages.first?.content.prefix(50).description ?? "(empty)"
            )
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    func deleteSession(id: UUID) throws {
        let url = sessionsDir.appendingPathComponent("\(id.uuidString).json")
        try FileManager.default.removeItem(at: url)
    }

    func sessionDirectory() -> URL {
        return sessionsDir
    }
}

struct SessionSummary: Identifiable {
    let id: UUID
    let createdAt: Date
    let updatedAt: Date
    let messageCount: Int
    let workingDir: String
    let preview: String

    var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: updatedAt, relativeTo: Date())
    }
}
