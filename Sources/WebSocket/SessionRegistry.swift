import Foundation

/// Tracks WebSocket-connected sessions and their role assignments.
@MainActor
final class SessionRegistry: ObservableObject {

    struct ConnectedSession {
        let sessionId: String
        var teamId: String?
        var roleId: String?
        var lastStatus: WSStatusMessage?
        let connectedAt: Date
    }

    @Published var sessions: [String: ConnectedSession] = [:]

    func register(sessionId: String) {
        if sessions[sessionId] == nil {
            sessions[sessionId] = ConnectedSession(
                sessionId: sessionId,
                connectedAt: Date()
            )
            AppState.log("SessionRegistry: registered \(sessionId)")
        }
    }

    func unregister(sessionId: String) {
        sessions.removeValue(forKey: sessionId)
        AppState.log("SessionRegistry: unregistered \(sessionId)")
    }

    func updateStatus(_ status: WSStatusMessage) {
        if sessions[status.sessionId] == nil {
            register(sessionId: status.sessionId)
        }
        sessions[status.sessionId]?.lastStatus = status
    }

    func assignRole(sessionId: String, teamId: String, roleId: String) {
        sessions[sessionId]?.teamId = teamId
        sessions[sessionId]?.roleId = roleId
    }

    var connectedCount: Int { sessions.count }

    func isConnected(_ sessionId: String) -> Bool {
        sessions[sessionId] != nil
    }
}
