import Foundation

/// Reads the people the team features show: the signed-in user, for
/// "Assigned to me", and who a project's tasks can be assigned to. Only
/// called while Team features is on (#272), so a personal-use setup makes
/// none of these requests.
actor UserService {
    private let apiClient: APIClient

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    func fetchCurrentUser() async throws -> User {
        try await apiClient.fetch(Endpoint.currentUser)
    }

    /// Everyone who can see the project, the signed-in user included.
    func fetchProjectUsers(projectId: Int64) async throws -> [User] {
        try await apiClient.fetch(Endpoint.projectUsers(projectId: projectId))
    }
}
