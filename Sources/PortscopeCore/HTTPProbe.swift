import Foundation

/// What a port said when asked for HTTP.
public enum HTTPProbeResult: Equatable, Sendable {
    /// Answered with this status code.
    case status(Int)
    /// Connected but never answered within the timeout: a hung dev server or something that is not HTTP but keeps the socket open.
    case unresponsive
    /// Refused, reset, or replied with something that is not HTTP.
    case notHTTP

    public var speaksHTTP: Bool {
        if case .status = self { return true }
        return false
    }
}

public enum HTTPProbe {
    /// Asks the port for `/` with HEAD. Any status code counts as HTTP; databases and debuggers say no.
    public static func probe(host: String, port: Int, timeout: TimeInterval = 0.6) async -> HTTPProbeResult {
        let urlHost = host == "::1" ? "[::1]" : "127.0.0.1"
        guard let url = URL(string: "http://\(urlHost):\(port)/") else { return .notHTTP }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.connectionProxyDictionary = [:]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = timeout
        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse { return .status(http.statusCode) }
            return .notHTTP
        } catch let error as URLError where error.code == .timedOut {
            return .unresponsive
        } catch {
            return .notHTTP
        }
    }

    /// True if something answers HTTP on this port (any status code counts).
    public static func speaksHTTP(host: String, port: Int, timeout: TimeInterval = 0.6) async -> Bool {
        await probe(host: host, port: port, timeout: timeout).speaksHTTP
    }
}
