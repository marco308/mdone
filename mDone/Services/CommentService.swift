import Foundation

/// Reads and writes task comments (#2).
actor CommentService {
    private let apiClient: APIClient

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    /// Every comment on the task, oldest first.
    func fetchComments(taskId: Int64) async throws -> [TaskComment] {
        let comments: [TaskComment] = try await apiClient.fetchAllPages({ page, perPage in
            Endpoint.taskComments(taskId: taskId, page: page, perPage: perPage)
        }, perPage: 50)
        return comments.sorted { ($0.created ?? .distantPast, $0.id) < ($1.created ?? .distantPast, $1.id) }
    }

    func createComment(taskId: Int64, html: String) async throws -> TaskComment {
        try await apiClient.send(
            Endpoint.createTaskComment(taskId: taskId),
            body: TaskCommentRequest(comment: html)
        )
    }

    func updateComment(taskId: Int64, commentId: Int64, html: String) async throws -> TaskComment {
        try await apiClient.send(
            Endpoint.updateTaskComment(taskId: taskId, commentId: commentId),
            body: TaskCommentRequest(comment: html)
        )
    }

    func deleteComment(taskId: Int64, commentId: Int64) async throws {
        try await apiClient.delete(Endpoint.deleteTaskComment(taskId: taskId, commentId: commentId))
    }
}
