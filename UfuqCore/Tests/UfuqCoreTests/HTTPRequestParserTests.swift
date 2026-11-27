import XCTest
@testable import UfuqCore

final class HTTPRequestParserTests: XCTestCase {
    private func parse(_ s: String) -> HTTPParseResult { HTTPRequestParser.parse(Data(s.utf8)) }

    func testParsesGetWithQueryAndHeaders() {
        let result = parse("GET /v1/events?since=12&x=a%20b HTTP/1.1\r\nHost: mac.local\r\nX-Ufuq-Auth: abc\r\n\r\n")
        guard case .request(let r) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(r.method, "GET")
        XCTAssertEqual(r.path, "/v1/events")
        XCTAssertEqual(r.query, ["since": "12", "x": "a b"])
        XCTAssertEqual(r.headers["x-ufuq-auth"], "abc")
    }

    func testIncompleteUntilBlankLine() {
        XCTAssertEqual(parse("GET /v1/snapshot HTTP/1.1\r\nHost: a\r\n"), .incomplete)
        XCTAssertEqual(parse(""), .incomplete)
    }

    func testRejectsOtherMethods() {
        XCTAssertEqual(parse("POST /v1/snapshot HTTP/1.1\r\n\r\n"), .invalid(status: 405))
        XCTAssertEqual(parse("DELETE / HTTP/1.1\r\n\r\n"), .invalid(status: 405))
    }

    func testRejectsMalformed() {
        XCTAssertEqual(parse("GET\r\n\r\n"), .invalid(status: 400))
        XCTAssertEqual(parse("GET /x FTP/1.0\r\n\r\n"), .invalid(status: 400))
        XCTAssertEqual(parse("GET x HTTP/1.1\r\n\r\n"), .invalid(status: 400))
        XCTAssertEqual(parse("GET /x HTTP/1.1\r\nbroken header\r\n\r\n"), .invalid(status: 400))
        XCTAssertEqual(HTTPRequestParser.parse(Data([0xff, 0xfe, 0x0d, 0x0a, 0x0d, 0x0a])), .invalid(status: 400))
    }

    func testRejectsBodiesAndHugeHeads() {
        XCTAssertEqual(parse("GET /x HTTP/1.1\r\nContent-Length: 5\r\n\r\nhello"), .invalid(status: 413))
        XCTAssertEqual(parse("GET /x HTTP/1.1\r\nContent-Length: 0\r\n\r\n").isRequest, true)
        let huge = "GET /x HTTP/1.1\r\nX: " + String(repeating: "a", count: 9000)
        XCTAssertEqual(parse(huge), .invalid(status: 431))
    }

    func testResponseSerialization() {
        let empty = String(decoding: HTTPResponse(status: 401).serialized(), as: UTF8.self)
        XCTAssertTrue(empty.hasPrefix("HTTP/1.1 401 Unauthorized\r\n"))
        XCTAssertTrue(empty.contains("Content-Length: 0\r\n"))
        XCTAssertTrue(empty.hasSuffix("\r\n\r\n"))
        let full = HTTPResponse(status: 200, body: Data([1, 2, 3])).serialized()
        XCTAssertTrue(String(decoding: full, as: UTF8.self).contains("Content-Length: 3\r\n"))
        XCTAssertEqual(full.suffix(3), Data([1, 2, 3]))
    }
}

private extension HTTPParseResult {
    var isRequest: Bool { if case .request = self { return true } else { return false } }
}
