import Foundation
import XCTest
@testable import NuvioTV

private final class JellyfinMockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class JellyfinClientTests: XCTestCase {
    private var session: URLSession!
    private let baseURL = URL(string: "http://192.168.1.100:8096")!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [JellyfinMockURLProtocol.self]
        session = URLSession(configuration: config)
    }

    override func tearDown() {
        JellyfinMockURLProtocol.requestHandler = nil
        session = nil
        super.tearDown()
    }

    // MARK: - Authentication & Headers

    func testAuthenticateUsesStandardAuthorizationHeader() async throws {
        var capturedRequest: URLRequest?

        JellyfinMockURLProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let json = """
            {
                "User": { "Id": "user-abc-123" },
                "AccessToken": "token-xyz-789"
            }
            """
            return (response, Data(json.utf8))
        }

        let result = try await JellyfinClient.authenticate(
            baseURL: baseURL,
            username: "admin",
            password: "password123",
            session: session
        )

        XCTAssertEqual(result.userId, "user-abc-123")
        XCTAssertEqual(result.accessToken, "token-xyz-789")

        let req = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(req.url?.path, "/Users/AuthenticateByName")
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let authHeader = try XCTUnwrap(req.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(authHeader.starts(with: "MediaBrowser "))
        XCTAssertTrue(authHeader.contains("Client=\"Nuvio\""))
        XCTAssertTrue(authHeader.contains("Device=\"Apple TV\""))
        XCTAssertTrue(authHeader.contains("DeviceId=\"NuvioTV-AppleTV\""))
        XCTAssertNil(req.value(forHTTPHeaderField: "X-Emby-Authorization"))
    }

    func testCurrentUserIdUsesUsersMeWhenSupported() async throws {
        var capturedRequest: URLRequest?

        JellyfinMockURLProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let json = """
            {
                "Id": "emby-user-456"
            }
            """
            return (response, Data(json.utf8))
        }

        let userId = try await JellyfinClient.currentUserId(
            baseURL: baseURL,
            apiKey: "my-api-key",
            session: session
        )

        XCTAssertEqual(userId, "emby-user-456")

        let req = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(req.url?.path, "/Users/Me")
        let authHeader = try XCTUnwrap(req.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(authHeader.contains("Token=\"my-api-key\""))
        XCTAssertNil(req.value(forHTTPHeaderField: "X-Emby-Token"))
    }

    func testCurrentUserIdFallsBackToUsersWhenMeReturns400() async throws {
        var requestedPaths: [String] = []

        JellyfinMockURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            requestedPaths.append(path)

            if path == "/Users/Me" {
                // Jellyfin 10.9/12 returns 400 for API keys on /Users/Me
                let response = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
                return (response, Data("Cannot authenticate user with an API key".utf8))
            } else if path == "/Users" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let json = """
                [
                    {
                        "Id": "regular-user-id",
                        "Name": "RegularUser",
                        "Policy": { "IsAdministrator": false }
                    },
                    {
                        "Id": "admin-user-id",
                        "Name": "AdminUser",
                        "Policy": { "IsAdministrator": true }
                    }
                ]
                """
                return (response, Data(json.utf8))
            } else {
                let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }
        }

        let userId = try await JellyfinClient.currentUserId(
            baseURL: baseURL,
            apiKey: "jellyfin-admin-key",
            session: session
        )

        // Should prefer admin user
        XCTAssertEqual(userId, "admin-user-id")
        XCTAssertEqual(requestedPaths, ["/Users/Me", "/Users"])
    }

    func testCurrentUserIdMatchesSpecifiedUsernameOnFallback() async throws {
        JellyfinMockURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            if path == "/Users/Me" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
                return (response, Data("Bad Request".utf8))
            } else if path == "/Users" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let json = """
                [
                    {
                        "Id": "admin-id",
                        "Name": "Admin",
                        "Policy": { "IsAdministrator": true }
                    },
                    {
                        "Id": "target-user-id",
                        "Name": "TargetUser",
                        "Policy": { "IsAdministrator": false }
                    }
                ]
                """
                return (response, Data(json.utf8))
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }

        let userId = try await JellyfinClient.currentUserId(
            baseURL: baseURL,
            apiKey: "some-key",
            username: "targetuser",
            session: session
        )

        XCTAssertEqual(userId, "target-user-id")
    }

    func testCurrentUserIdThrowsUnauthorizedOn401() async {
        JellyfinMockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        do {
            _ = try await JellyfinClient.currentUserId(baseURL: self.baseURL, apiKey: "invalid-key", session: self.session)
            XCTFail("Expected unauthorized error to be thrown")
        } catch let error as JellyfinClient.ClientError {
            XCTAssertEqual(error.message, L10n.string("jellyfin_error_unauthorized", fallback: "Invalid API key or credentials"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testPingSendsStandardAuthorizationHeader() async throws {
        var capturedRequest: URLRequest?

        JellyfinMockURLProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"ServerName":"Jellyfin"}"#.utf8))
        }

        let client = JellyfinClient(baseURL: baseURL, accessToken: "test-token-123", session: session)
        try await client.ping()

        let req = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(req.url?.path, "/System/Info")
        let authHeader = try XCTUnwrap(req.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(authHeader.contains("Token=\"test-token-123\""))
        XCTAssertNil(req.value(forHTTPHeaderField: "X-Emby-Token"))
    }

    func testLibrariesAndItemsParsing() async throws {
        JellyfinMockURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!

            if path == "/Users/user-1/Views" {
                let json = """
                {
                    "Items": [
                        { "Id": "lib-1", "Name": "Movies", "CollectionType": "movies" },
                        { "Id": "lib-2", "Name": "TV Shows", "CollectionType": "tvshows" }
                    ]
                }
                """
                return (response, Data(json.utf8))
            } else if path == "/Users/user-1/Items" {
                let json = """
                {
                    "Items": [
                        {
                            "Id": "movie-1",
                            "Name": "Sample Movie",
                            "Type": "Movie",
                            "Overview": "Movie overview",
                            "ProductionYear": 2024,
                            "CommunityRating": 8.5
                        }
                    ]
                }
                """
                return (response, Data(json.utf8))
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }

        let client = JellyfinClient(baseURL: baseURL, accessToken: "test-token", session: session)
        let libraries = try await client.libraries(userId: "user-1")
        XCTAssertEqual(libraries.count, 2)
        XCTAssertEqual(libraries[0].name, "Movies")
        XCTAssertEqual(libraries[1].name, "TV Shows")

        let items = try await client.items(userId: "user-1", libraryId: "lib-1")
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].name, "Sample Movie")
        XCTAssertEqual(items[0].type, "Movie")
        XCTAssertEqual(items[0].productionYear, 2024)
        XCTAssertEqual(items[0].communityRating, 8.5)
    }
}
