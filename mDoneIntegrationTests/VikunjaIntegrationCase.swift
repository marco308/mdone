import Foundation
import XCTest
@testable import mDone

/// Base class for tests that run against a **real** Vikunja server rather than
/// `MockURLProtocol`.
///
/// The unit suite pins our decoding against hand-written JSON, which is exactly
/// the wrong shape of test for "did upstream change the wire format?": it stays
/// green forever whatever the server does. These tests answer the other half by
/// driving the real services against a live instance.
///
/// They are not part of the PR run. `.github/workflows/vikunja-integration.yml`
/// brings a server up nightly and runs them against `vikunja/vikunja:latest`,
/// so a release that breaks the v1 contract shows up as a red nightly instead
/// of a user's bug report. With nothing reachable every test skips, which keeps
/// a whole-scheme `xcodebuild test` green on a laptop with Docker switched off.
///
/// Point them somewhere else with `MDONE_INTEGRATION_SERVER_URL`,
/// `MDONE_INTEGRATION_USER` and `MDONE_INTEGRATION_PASSWORD`. The defaults match
/// the local dev server from `docker-compose.dev.yml` plus
/// `scripts/seed-dev-vikunja.sh`.
class VikunjaIntegrationCase: XCTestCase {
    struct Config: Sendable {
        var serverURL: String
        var username: String
        var password: String

        static func fromEnvironment() -> Config {
            let env = ProcessInfo.processInfo.environment
            return Config(
                serverURL: env["MDONE_INTEGRATION_SERVER_URL"] ?? "http://localhost:3456",
                username: env["MDONE_INTEGRATION_USER"] ?? "devuser",
                password: env["MDONE_INTEGRATION_PASSWORD"] ?? "devpassword"
            )
        }
    }

    private(set) var config = Config.fromEnvironment()

    /// A client of our own rather than `APIClient.shared`: these tests run
    /// inside the app's process, and configuring the singleton would point the
    /// live app at the test server for the rest of the run.
    private(set) var client: APIClient!
    private(set) var tasks: TaskService!
    private(set) var projects: ProjectService!
    private(set) var labels: LabelService!

    /// A project created per test and deleted in `tearDown`, so a run leaves the
    /// server as it found it and no two tests fight over the same tasks.
    private(set) var scratchProject: Project!

    /// Server version string, e.g. `v2.6.0`, or nil if the server didn't report
    /// one. Logged once per run so a red nightly names the release that broke us.
    private(set) var serverVersion: String?

    override func setUp() async throws {
        try await super.setUp()
        config = Config.fromEnvironment()

        // Throws XCTSkip when nothing answers. Probed once per process: the
        // client retries a refused connection three times with backoff, so
        // probing per test would cost ~7s each with no server running.
        serverVersion = try await IntegrationSession.shared.serverVersion(for: config)

        let token = try await IntegrationSession.shared.token(for: config)
        client = APIClient()
        await client.configure(serverURL: config.serverURL, token: token)

        tasks = TaskService(apiClient: client)
        projects = ProjectService(apiClient: client)
        labels = LabelService(apiClient: client)

        scratchProject = try await projects.createProject(
            ProjectCreateRequest(title: "mDone integration \(UUID().uuidString.prefix(8))")
        )
    }

    override func tearDown() async throws {
        if let scratchProject, let projects {
            // Best effort: a failed assertion mid-test still gets its project
            // cleaned up, and a cleanup failure must not mask the real failure.
            try? await projects.deleteProject(id: scratchProject.id)
        }
        scratchProject = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// The scratch project's view of the given kind, failing the test when the
    /// server didn't create one.
    func viewId(kind: String, file: StaticString = #filePath, line: UInt = #line) async throws -> Int64 {
        let views = try await projects.fetchProjectViews(projectId: scratchProject.id)
        guard let view = views.first(where: { $0.viewKind == kind }) else {
            XCTFail(
                "Project \(scratchProject.id) has no \(kind) view, got \(views.map { $0.viewKind ?? "nil" })",
                file: file,
                line: line
            )
            throw VikunjaIntegrationError.missingView(kind)
        }
        return view.id
    }

    /// Creates a task in the scratch project.
    @discardableResult
    func makeTask(_ request: TaskCreateRequest) async throws -> VTask {
        try await tasks.createTask(projectId: scratchProject.id, request: request)
    }
}

/// Per-process state shared by every integration test: one reachability probe
/// and one login for the whole run.
///
/// Both are cached for the same reason, that repeating them per test method is
/// expensive in a way that looks like a bug. The probe costs the client's full
/// retry ladder when nothing is listening, and Vikunja rate-limits
/// `POST /login` per user hard enough that a login per test starts returning
/// 429 around the tenth test (observed on v2.4.0), which reads exactly like a
/// broken login and isn't.
actor IntegrationSession {
    static let shared = IntegrationSession()

    private struct Probe {
        var version: String?
        var skipReason: String?
    }

    private var probes: [String: Probe] = [:]
    private var tokens: [String: String] = [:]
    /// Why login failed, if it did. Cached alongside the tokens so a bad
    /// password fails all 14 tests with the same clear message instead of
    /// making 14 more login attempts and tripping the rate limiter, which
    /// buries the real error under a pile of 429s.
    private var loginFailures: [String: VikunjaIntegrationError] = [:]

    /// The server's reported version, or `XCTSkip` if it can't be reached.
    ///
    /// Probes through the app's own `ServerInfoService`, so the nightly also
    /// covers the code the setup screen runs before anyone can log in.
    func serverVersion(for config: VikunjaIntegrationCase.Config) async throws -> String? {
        if let probe = probes[config.serverURL] {
            if let reason = probe.skipReason {
                throw XCTSkip(reason)
            }
            return probe.version
        }

        guard let url = URL(string: config.serverURL) else {
            let reason = "MDONE_INTEGRATION_SERVER_URL is not a URL: \(config.serverURL)"
            probes[config.serverURL] = Probe(skipReason: reason)
            throw XCTSkip(reason)
        }

        do {
            let info = try await ServerInfoService().fetch(from: url)
            probes[config.serverURL] = Probe(version: info.version)
            print("[integration] \(config.serverURL) is Vikunja \(info.version ?? "unknown")")
            return info.version
        } catch {
            let reason = """
            No Vikunja reachable at \(config.serverURL) (\(error.localizedDescription)).
            Start one with: docker compose -f docker-compose.dev.yml up -d && ./scripts/seed-dev-vikunja.sh
            """
            probes[config.serverURL] = Probe(skipReason: reason)
            throw XCTSkip(reason)
        }
    }

    /// The shared session token, logging in on first use.
    func token(for config: VikunjaIntegrationCase.Config) async throws -> String {
        let key = "\(config.serverURL)|\(config.username)"
        if let cached = tokens[key] {
            return cached
        }
        if let failure = loginFailures[key] {
            throw failure
        }
        do {
            let token = try await Self.login(config)
            tokens[key] = token
            return token
        } catch let error as VikunjaIntegrationError {
            loginFailures[key] = error
            throw error
        }
    }

    /// Performs a real password login and hands back the token.
    static func login(_ config: VikunjaIntegrationCase.Config) async throws -> String {
        let client = APIClient()
        await client.configure(serverURL: config.serverURL, token: "")
        do {
            let response: LoginResponse = try await client.send(
                Endpoint.login,
                body: LoginRequest(username: config.username, password: config.password)
            )
            return response.token
        } catch {
            throw VikunjaIntegrationError.loginFailed(
                user: config.username,
                server: config.serverURL,
                underlying: error
            )
        }
    }
}

enum VikunjaIntegrationError: LocalizedError {
    case missingView(String)
    case loginFailed(user: String, server: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case let .missingView(kind):
            "The scratch project has no \(kind) view"
        case let .loginFailed(user, server, underlying):
            """
            Could not log in as \(user) on \(server): \(underlying). \
            If the server is up but has no seeded user, run ./scripts/seed-dev-vikunja.sh.
            """
        }
    }
}
