import AppKit
import Foundation

/// Loads site icons for Day Tracker (Google favicon endpoint; no API key).
actor FaviconLoader {
    static let shared = FaviconLoader()

    private var cache: [String: NSImage] = [:]

    func image(forDomain domain: String) async -> NSImage? {
        let key = domain.lowercased()
        if let cached = cache[key] { return cached }
        var components = URLComponents(string: "https://www.google.com/s2/favicons")!
        components.queryItems = [
            URLQueryItem(name: "domain", value: key),
            URLQueryItem(name: "sz", value: "64")
        ]
        guard let url = components.url else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else { return nil }
            guard let img = NSImage(data: data), img.size.width > 1 else { return nil }
            cache[key] = img
            return img
        } catch {
            return nil
        }
    }
}
