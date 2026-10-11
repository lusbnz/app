import Foundation
import Testing
@testable import Xu

struct AIProtocolTests {
    private let quotaJSON = #"{"used":42,"limit":300,"credits":10,"remaining":268,"resetsAt":"2026-11-01T00:00:00.000Z"}"#

    @Test func aSuccessfulRunCarriesTextAndQuota() throws {
        let data = Data(#"{"text":" 232k cho 8 lần. ","quota":\#(quotaJSON)}"#.utf8)
        let response = try AIProtocol.runResponse(status: 200, data: data)
        #expect(response.text == "232k cho 8 lần.")
        #expect(response.quota.remaining == 268 && response.quota.limit == 300 && response.quota.credits == 10)
        #expect(response.quota.resetsAt == TestClock.calendar.date(from: DateComponents(timeZone: TimeZone(identifier: "UTC"), year: 2026, month: 11, day: 1)))
    }

    @Test func statusCodesMapToErrors() {
        let empty = Data("{}".utf8)
        #expect(throws: AIError.notSubscribed) { try AIProtocol.runResponse(status: 403, data: empty) }
        #expect(throws: AIError.notSubscribed) { try AIProtocol.runResponse(status: 401, data: empty) }
        #expect(throws: AIError.unavailable) { try AIProtocol.runResponse(status: 502, data: empty) }
        #expect(throws: AIError.network) { try AIProtocol.runResponse(status: 400, data: empty) }
        #expect(throws: AIError.network) { try AIProtocol.runResponse(status: 200, data: empty) }
        #expect(throws: AIError.network) { try AIProtocol.quotaResponse(status: 200, data: Data("oops".utf8)) }
    }

    @Test func runningOutOfUsesKeepsTheLatestQuota() throws {
        let data = Data(#"{"error":"quota_exceeded","quota":\#(quotaJSON)}"#.utf8)
        do {
            _ = try AIProtocol.runResponse(status: 429, data: data)
            Issue.record("phải báo hết lượt")
        } catch AIError.quotaExceeded(let quota) {
            #expect(quota?.used == 42)
        }
    }

    @Test func requestsAreTrimmedToTheServerLimits() throws {
        let request = AIRunRequest(task: .ask, sheet: String(repeating: "a", count: 20_000), text: String(repeating: "b", count: 900), language: "vi")
        let sent = try JSONDecoder().decode(AIRunRequest.self, from: AIProtocol.encode(request))
        #expect(sent.sheet?.count == AIProtocol.maxSheetLength)
        #expect(sent.text?.count == AIProtocol.maxTextLength)
        #expect(sent.task == .ask && sent.language == "vi")
    }

    @Test func onlyAShortSingleLineIsAUsableRewrite() {
        #expect(AIProtocol.cleanedLine("  ăn với Minh 450k chia 3 hôm qua \n") == "ăn với Minh 450k chia 3 hôm qua")
        #expect(AIProtocol.cleanedLine("") == nil)
        #expect(AIProtocol.cleanedLine("dòng một\ndòng hai") == nil)
        #expect(AIProtocol.cleanedLine(String(repeating: "x", count: 201)) == nil)
    }
}

/// Chặn mọi yêu cầu mạng của một `URLSession` riêng để xem `AIClient` gửi gì.
final class AIStubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, Data))?
    nonisolated(unsafe) static var seen: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.seen.append(request)
        let (status, data) = Self.handler?(request) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url ?? URL(fileURLWithPath: "/"), statusCode: status, httpVersion: nil, headerFields: nil)
        if let response { client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed) }
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct AIClientTests {
    private let quotaJSON = #"{"used":1,"limit":300,"credits":0,"remaining":299,"resetsAt":"2026-11-01T00:00:00Z"}"#

    private func makeClient() -> AIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AIStubProtocol.self]
        AIStubProtocol.seen = []
        return AIClient(baseURL: URL(string: "https://ai.example")!, transactionID: "2000000123", session: URLSession(configuration: configuration))
    }

    @Test func runPostsTheTaskWithTheTransactionHeader() async throws {
        let client = makeClient()
        let quota = quotaJSON
        AIStubProtocol.handler = { _ in (200, Data(#"{"text":"ok","quota":\#(quota)}"#.utf8)) }
        let response = try await client.run(AIRunRequest(task: .insight, sheet: "Đã tiêu tháng này: 1tr", language: "vi"))
        #expect(response.text == "ok" && response.quota.remaining == 299)
        let request = try #require(AIStubProtocol.seen.first)
        #expect(request.url?.absoluteString == "https://ai.example/v1/run")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: AIProtocol.transactionHeader) == "2000000123")
    }

    @Test func quotaAndTopUpUseTheirOwnPaths() async throws {
        let client = makeClient()
        let quota = quotaJSON
        AIStubProtocol.handler = { _ in (200, Data(#"{"quota":\#(quota)}"#.utf8)) }
        #expect(try await client.quota().limit == 300)
        #expect(try await client.topUp(transactionID: "777").remaining == 299)
        #expect(AIStubProtocol.seen.map { $0.url?.path } == ["/v1/quota", "/v1/topup"])
        #expect(AIStubProtocol.seen.map(\.httpMethod) == ["GET", "POST"])
    }

    @Test func serverRefusalsBecomeTypedErrors() async {
        let client = makeClient()
        AIStubProtocol.handler = { _ in (403, Data(#"{"error":"not_subscribed"}"#.utf8)) }
        await #expect(throws: AIError.notSubscribed) { try await client.quota() }
    }
}

struct CloudAnswererTests {
    private let calendar = TestClock.calendar

    private var snapshot: SpendingSnapshot {
        SpendingSnapshot.make(records: [
            SpendingRecord(name: "cf", amount: 29_000, categoryKey: "food", date: TestClock.date(2026, 10, 2)),
            SpendingRecord(name: "cf", amount: 29_000, categoryKey: "food", date: TestClock.date(2026, 10, 3)),
        ], monthlyBudget: 9_000_000, now: TestClock.now, calendar: calendar)
    }

    @Test func sendsOnlyTheAggregatedSheetAndTheQuestion() async throws {
        let answerer = CloudAnswerer(calendar: calendar) { request in
            #expect(request.task == .ask)
            #expect(request.text == "cf hết bao nhiêu?")
            #expect(request.sheet?.contains("- cf: 58k cho 2 lần") == true)
            return "58k cho 2 lần."
        }
        #expect(try await answerer.answer("cf hết bao nhiêu?", context: snapshot) == "58k cho 2 lần.")
    }

    @Test func anAnswerWithAnInventedNumberIsRejected() async {
        let answerer = CloudAnswerer(calendar: calendar) { _ in "Khoảng 75k." }
        await #expect(throws: AskError.self) { try await answerer.answer("cf hết bao nhiêu?", context: snapshot) }
        let empty = CloudAnswerer(calendar: calendar) { _ in "" }
        await #expect(throws: AskError.self) { try await empty.answer("cf?", context: snapshot) }
    }
}

struct AINormalizeTests {
    private let parser = ExpenseParser(rates: .standard)

    @Test func aRewrittenLineIsAcceptedOnlyWhenTheParserReadsEveryAmount() {
        func readable(_ line: String) -> Bool {
            EntryRows.isReadable(line, parser: parser, now: TestClock.now, calendar: TestClock.calendar)
        }
        #expect(readable("ăn với Minh 450k chia 3 hôm qua"))
        #expect(readable("phở 45k, grab 32k"))
        #expect(!readable("ăn với Minh hết nhiều tiền"))
        #expect(!readable("phở 45k, grab"))
        #expect(!readable("tháng này cf hết bao nhiêu?"))
    }
}
