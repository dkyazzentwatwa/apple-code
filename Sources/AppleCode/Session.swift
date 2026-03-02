import Foundation

enum UIMode: String, Codable {
    case classic
    case framed
}

struct Session: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    var updatedAt: Date
    var messages: [Message]
    var workingDir: String
    var modelConfig: ModelConfig?
    var uiMode: UIMode
    var activeThemeName: String

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
        case messages
        case workingDir
        case modelConfig
        case uiMode
        case activeThemeName
    }

    init(
        workingDir: String = FileManager.default.currentDirectoryPath,
        modelConfig: ModelConfig? = nil,
        uiMode: UIMode = .classic,
        activeThemeName: String = TUITheme.wow.name
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.updatedAt = Date()
        self.messages = []
        self.workingDir = workingDir
        self.modelConfig = modelConfig
        self.uiMode = uiMode
        self.activeThemeName = activeThemeName
    }

    mutating func addMessage(role: String, content: String) {
        messages.append(Message(role: role, content: content))
        updatedAt = Date()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        messages = try container.decode([Message].self, forKey: .messages)
        workingDir = try container.decode(String.self, forKey: .workingDir)
        modelConfig = try container.decodeIfPresent(ModelConfig.self, forKey: .modelConfig)
        uiMode = try container.decodeIfPresent(UIMode.self, forKey: .uiMode) ?? .classic
        activeThemeName = try container.decodeIfPresent(String.self, forKey: .activeThemeName) ?? TUITheme.wow.name
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

    func createSession(
        workingDir: String? = nil,
        modelConfig: ModelConfig? = nil,
        uiMode: UIMode = .classic,
        activeThemeName: String = TUITheme.wow.name
    ) -> Session {
        let dir = workingDir ?? FileManager.default.currentDirectoryPath
        let session = Session(
            workingDir: dir,
            modelConfig: modelConfig,
            uiMode: uiMode,
            activeThemeName: activeThemeName
        )
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
                preview: session.messages.first?.content.prefix(50).description ?? "(empty)",
                uiMode: session.uiMode
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
    let uiMode: UIMode

    var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: updatedAt, relativeTo: Date())
    }
}
