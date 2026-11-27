import Foundation

public struct HTTPRequest: Equatable, Sendable {
    public var method: String
    public var path: String
    public var query: [String: String]
    /// Header names are lower-cased.
    public var headers: [String: String]

    public init(method: String, path: String, query: [String: String] = [:], headers: [String: String] = [:]) {
        self.method = method
        self.path = path
        self.query = query
        self.headers = headers
    }
}

public enum HTTPParseResult: Equatable, Sendable {
    /// The head is not complete yet; read more bytes.
    case incomplete
    case request(HTTPRequest)
    /// Reject with this status (400, 405, 413 or 431).
    case invalid(status: Int)
}

/// A minimal HTTP/1.1 request-head parser: GET only, no body. Anything else is rejected.
public enum HTTPRequestParser {
    public static let maxHeadBytes = 8 * 1024

    public static func parse(_ data: Data) -> HTTPParseResult {
        let terminator = Data("\r\n\r\n".utf8)
        guard let end = data.range(of: terminator) else {
            return data.count > maxHeadBytes ? .invalid(status: 431) : .incomplete
        }
        guard end.lowerBound <= maxHeadBytes else { return .invalid(status: 431) }
        guard let head = String(data: data[data.startIndex..<end.lowerBound], encoding: .utf8) else {
            return .invalid(status: 400)
        }
        let lines = head.components(separatedBy: "\r\n")
        let parts = lines[0].split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts[2].hasPrefix("HTTP/1.") else { return .invalid(status: 400) }
        guard parts[0] == "GET" else {
            return .invalid(status: parts[0].allSatisfy({ $0.isUppercase }) && !parts[0].isEmpty ? 405 : 400)
        }
        let target = parts[1]
        guard target.hasPrefix("/") else { return .invalid(status: 400) }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":"), colon != line.startIndex else { return .invalid(status: 400) }
            let name = line[line.startIndex..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
        // GET with a body is not part of this protocol.
        if let length = headers["content-length"], length != "0" { return .invalid(status: 413) }
        if headers["transfer-encoding"] != nil { return .invalid(status: 413) }

        var path = target
        var query: [String: String] = [:]
        if let q = target.firstIndex(of: "?") {
            path = String(target[target.startIndex..<q])
            for pair in target[target.index(after: q)...].split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let key = String(kv[0]).removingPercentEncoding ?? String(kv[0])
                let value = kv.count > 1 ? (String(kv[1]).removingPercentEncoding ?? String(kv[1])) : ""
                query[key] = value
            }
        }
        return .request(HTTPRequest(method: "GET", path: path, query: query, headers: headers))
    }
}

public struct HTTPResponse: Equatable, Sendable {
    public var status: Int
    public var body: Data

    public init(status: Int, body: Data = Data()) {
        self.status = status
        self.body = body
    }

    static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 413: return "Content Too Large"
        case 431: return "Request Header Fields Too Large"
        case 500: return "Internal Server Error"
        default: return "Error"
        }
    }

    /// Wire bytes. Always closes the connection. An empty body (401 and friends) sends no content.
    public func serialized() -> Data {
        var head = "HTTP/1.1 \(status) \(Self.reason(status))\r\n"
        if !body.isEmpty { head += "Content-Type: application/octet-stream\r\n" }
        head += "Content-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}
