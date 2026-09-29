import Foundation

public enum HTTPProbe {
    /// True if something answers HTTP on this port (any status code counts).
    /// Used to decide whether "open in browser" makes sense; databases and debuggers say no.
    public static func speaksHTTP(host: String, port: Int, timeout: TimeInterval = 0.6) async -> Bool {
        let urlHost = host == "::1" ? "[::1]" : "127.0.0.1"
        guard let url = URL(string: "http://\(urlHost):\(port)/") else { return false }

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
            return response is HTTPURLResponse
        } catch {
            return false
        }
    }
}
