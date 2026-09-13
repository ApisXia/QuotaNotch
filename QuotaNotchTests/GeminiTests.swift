import XCTest
@testable import QuotaNotchCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class GeminiTests: XCTestCase {
    func testBucketsKeepLowestReadingPerModelAndStableIDs() throws {
        let data = Data(#"{"buckets":[{"modelId":"gemini-pro","remainingFraction":0.8},{"modelId":"gemini-flash","remainingFraction":1},{"modelId":"gemini-pro","remainingFraction":0.3,"resetTime":"2031-01-01T00:00:00Z"}]}"#.utf8)
        let result = try QuotaParser.parse(data, provider: .gemini, now: Date())
        XCTAssertEqual(result.windows.map(\.id), ["gemini-flash", "gemini-pro"])
        XCTAssertEqual(result.windows.map(\.remainingPercent), [100, 30])
        XCTAssertNotNil(result.windows.last?.resetsAt)
    }

    func testInvalidBucketsAreNotFullQuota() {
        for value in ["true", "-0.1", "1.01", "\"0.3\"", "null"] {
            let data = Data("{\"buckets\":[{\"modelId\":\"gemini-pro\",\"remainingFraction\":\(value)}]}".utf8)
            XCTAssertThrowsError(try QuotaParser.parse(data, provider: .gemini, now: Date()))
        }
    }

    func testGeminiCredentialAndExpiry() throws {
        let data = Data(#"{"access_token":"fixture-only","expiry_date":1924992000000}"#.utf8)
        let credential = try LocalQuotaCredentials.decode(data, provider: .gemini)
        XCTAssertEqual(credential.expiresAt, Date(timeIntervalSince1970: 1924992000))
        XCTAssertFalse(String(describing: credential).contains("fixture-only"))
        XCTAssertThrowsError(try LocalQuotaCredentials.decode(Data(#"{"api_key":"fixture-only"}"#.utf8), provider: .gemini))
    }

    func testProjectDiscoveryBeforeQuotaAndCooldown() async throws {
        let transport = GeminiFixtureTransport()
        let client = QuotaClient(credentials: GeminiFixtureCredentials(), transport: transport)
        let result = await client.refresh(.gemini)
        XCTAssertNil(result.failure)
        XCTAssertEqual(result.snapshot?.windows.first?.remainingPercent, 50)
        _ = await client.refresh(.gemini)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.map { $0.url?.lastPathComponent }, ["v1internal:loadCodeAssist", "v1internal:retrieveUserQuota"])
        XCTAssertTrue(requests.allSatisfy { $0.httpMethod == "POST" && $0.url?.host == "cloudcode-pa.googleapis.com" })
        let body = try XCTUnwrap(requests.last?.httpBody)
        XCTAssertEqual((try JSONSerialization.jsonObject(with: body) as? [String: String])?["project"], "fixture-project")
    }
}

private struct GeminiFixtureCredentials: QuotaCredentialSource {
    func load(_ provider: QuotaProvider) async throws -> QuotaCredential {
        QuotaCredential(accessToken: "fixture-only", accountID: nil, expiresAt: nil)
    }
}
private actor GeminiFixtureTransport: QuotaTransport {
    var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> QuotaHTTPResponse {
        requests.append(request)
        let body = requests.count == 1 ? #"{"cloudaicompanionProject":"fixture-project"}"# : #"{"buckets":[{"modelId":"gemini-pro","remainingFraction":0.5}]}"#
        return QuotaHTTPResponse(data: Data(body.utf8), status: 200, retryAfter: nil)
    }
}
