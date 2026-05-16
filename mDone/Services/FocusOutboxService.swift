import Foundation
import OSLog
import SwiftData

/// Delivers undelivered `FocusRecord` rows to the focus-service capture
/// endpoint (mdone#62). Source of truth is the FocusRecord itself —
/// `deliveredAt == nil` is "pending". No separate queue table.
///
/// `@MainActor` so SwiftData reads/writes stay on the main context,
/// matching the existing `FocusManager` / `SyncService` patterns; the
/// HTTP call is awaited and naturally yields the actor.
@MainActor
@Observable
final class FocusOutboxService {
    private let modelContainer: ModelContainer
    private let session: URLSession
    private let logger = Logger(subsystem: "com.mdone", category: "FocusOutboxService")

    private static let batchSize = 50

    /// 429 backoff: drains short-circuit if we hit a rate limit until this
    /// passes. Cleared on next successful drain or app restart.
    private var rateLimitedUntil: Date?

    /// Coalesce drain calls — only one in flight at a time.
    private var drainInFlight = false

    init(modelContainer: ModelContainer, session: URLSession = .shared) {
        self.modelContainer = modelContainer
        self.session = session
    }

    // MARK: - Public API

    /// Called after `FocusManager.persistCompletedSession` inserts a record.
    /// Fire-and-forget: does not block focus completion on network.
    func enqueue(_ record: FocusRecord) {
        ensureClientId(for: record)
        Task { await drain() }
    }

    /// Drain all undelivered records. Safe to call repeatedly — calls are
    /// coalesced. Returns silently when nothing to do or when the feature
    /// is unconfigured.
    func drain() async {
        guard !drainInFlight else { return }
        drainInFlight = true
        defer { drainInFlight = false }

        guard FocusSyncConfig.isConfigured(),
              let url = FocusSyncConfig.focusEventsURL(),
              let token = FocusSyncConfig.getToken()
        else {
            return
        }

        if let until = rateLimitedUntil, until > Date() {
            logger.info("Skipping drain — rate-limited until \(until)")
            return
        }

        let records = fetchPending()
        guard !records.isEmpty else { return }

        logger.info("Draining \(records.count) pending focus record(s) → \(url.absoluteString, privacy: .public)")

        for record in records {
            let outcome = await deliver(record, to: url, token: token)
            switch outcome {
            case .accepted:
                record.deliveredAt = Date()
                try? modelContainer.mainContext.save()
            case .rateLimited(let retryAfter):
                rateLimitedUntil = Date().addingTimeInterval(retryAfter)
                logger.notice("Rate-limited, backing off \(retryAfter)s")
                return
            case .authFailed:
                logger.error("focus-service rejected token (401/403). Pausing drain — user must fix settings.")
                return
            case .schemaRejected(let body):
                logger.error("focus-service rejected payload (422): \(body, privacy: .public). Skipping record clientId=\(record.clientId ?? "<nil>", privacy: .public).")
                // Don't mark delivered, don't loop forever — move on to the
                // next record. Same record will be retried on next drain.
                continue
            case .transient:
                logger.info("Transient failure delivering focus record — will retry on next drain")
                return
            }
        }
    }

    // MARK: - Delivery

    private enum Outcome {
        case accepted
        case rateLimited(TimeInterval)
        case authFailed
        case schemaRejected(String)
        case transient
    }

    private func deliver(_ record: FocusRecord, to url: URL, token: String) async -> Outcome {
        ensureClientId(for: record)
        guard let payload = encodePayload(for: record) else {
            return .schemaRejected("client-side encoding failed")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = payload
        request.timeoutInterval = 15

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .transient
            }
            switch http.statusCode {
            case 200, 201:
                return .accepted
            case 401, 403:
                return .authFailed
            case 422:
                let body = String(data: data, encoding: .utf8) ?? "<no body>"
                return .schemaRejected(body)
            case 429:
                let retryAfter = parseRetryAfter(http) ?? 60
                return .rateLimited(retryAfter)
            case 500 ..< 600:
                return .transient
            default:
                logger.notice("Unexpected status \(http.statusCode) from focus-service")
                return .transient
            }
        } catch {
            logger.info("Network error delivering focus record: \(error.localizedDescription, privacy: .public)")
            return .transient
        }
    }

    // MARK: - Helpers

    private func fetchPending() -> [FocusRecord] {
        var descriptor = FetchDescriptor<FocusRecord>(
            predicate: #Predicate<FocusRecord> { $0.deliveredAt == nil },
            sortBy: [SortDescriptor(\FocusRecord.endedAt, order: .forward)]
        )
        descriptor.fetchLimit = Self.batchSize
        return (try? modelContainer.mainContext.fetch(descriptor)) ?? []
    }

    private func ensureClientId(for record: FocusRecord) {
        if record.clientId == nil {
            record.clientId = UUID().uuidString
            try? modelContainer.mainContext.save()
        }
    }

    private func encodePayload(for record: FocusRecord) -> Data? {
        struct Payload: Encodable {
            let taskId: Int64
            let taskTitle: String
            let projectName: String
            let priorityLevel: Int
            let startedAt: String
            let endedAt: String
            let focusedSeconds: Double
            let device: String
            let clientId: String?
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        let payload = Payload(
            taskId: record.taskId,
            taskTitle: record.taskTitle,
            projectName: record.projectName,
            priorityLevel: record.priorityLevel,
            startedAt: iso.string(from: record.startedAt),
            endedAt: iso.string(from: record.endedAt),
            focusedSeconds: record.focusedSeconds,
            device: record.device,
            clientId: record.clientId
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try? encoder.encode(payload)
    }

    private func parseRetryAfter(_ response: HTTPURLResponse) -> TimeInterval? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        if let seconds = TimeInterval(raw) { return seconds }
        // HTTP-date form — rare from slowapi, but support for robustness.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = formatter.date(from: raw) {
            return max(0, date.timeIntervalSinceNow)
        }
        return nil
    }
}
