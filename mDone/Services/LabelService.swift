import Foundation

/// Label operations: listing, creating, and associating labels with tasks.
///
/// Backs the "Current" feature, which marks long-running tasks with a
/// dedicated Vikunja label so they surface in their own section at the top
/// of the task list. Like the other services this is an `actor` for thread
/// safety, and takes an injectable `APIClient` so tests can drive it through
/// `MockURLProtocol`.
actor LabelService {
    private let apiClient: APIClient

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    func createLabel(_ request: LabelCreateRequest) async throws -> VLabel {
        try await apiClient.send(Endpoint.createLabel(), body: request)
    }

    /// Associates `labelId` with `taskId`. Vikunja echoes the new relation,
    /// which we don't need, so the response body is discarded.
    func addLabel(taskId: Int64, labelId: Int64) async throws {
        try await apiClient.sendExpectingEmpty(
            Endpoint.addLabelToTask(taskId: taskId),
            body: LabelTaskRequest(labelId: labelId)
        )
    }

    func removeLabel(taskId: Int64, labelId: Int64) async throws {
        try await apiClient.delete(Endpoint.removeLabelFromTask(taskId: taskId, labelId: labelId))
    }
}
