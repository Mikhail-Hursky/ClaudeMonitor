import Foundation
import Security

// MARK: - Paths

private let cacheDir      = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache")
private let apiCacheFile  = cacheDir.appendingPathComponent("claude-api-response.json")
private let backoffFile   = cacheDir.appendingPathComponent("claude-usage-backoff")
private let lockFile      = cacheDir.appendingPathComponent("claude-usage.lock")

private let apiURL    = URL(string: "https://api.anthropic.com/api/oauth/usage")!
private let cacheTTL: TimeInterval = 120

// MARK: - Model

struct UsageData {
    let fiveHourPct:      Double?
    let fiveHourResetsAt: String?
    let sevenDayPct:      Double?
    let sevenDayResetsAt: String?
}

// MARK: - Helpers

private func fileAge(_ url: URL) -> TimeInterval {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
          let mod = attrs[.modificationDate] as? Date else { return .infinity }
    return Date().timeIntervalSince(mod)
}

private func loadCache() -> [String: Any]? {
    guard let data = try? Data(contentsOf: apiCacheFile) else { return nil }
    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
}

private func getToken() -> String? {
    var item: CFTypeRef?
    let query: [CFString: Any] = [
        kSecClass:       kSecClassGenericPassword,
        kSecAttrService: "Claude Code-credentials",
        kSecReturnData:  true,
        kSecMatchLimit:  kSecMatchLimitOne,
    ]
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
          let data  = item as? Data,
          let json  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let oauth = json["claudeAiOauth"] as? [String: Any],
          let token = oauth["accessToken"] as? String
    else { return nil }
    return token
}

private func claudeVersion() -> String {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    task.arguments     = ["claude", "-v"]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError  = Pipe()
    try? task.run()
    task.waitUntilExit()
    let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return out?.isEmpty == false ? out! : "2.1.81"
}

// MARK: - Public

func fetchUsage(completion: @escaping ([String: Any]?) -> Void) {
    DispatchQueue.global(qos: .utility).async {
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        // Fresh cache
        if fileAge(apiCacheFile) < cacheTTL {
            completion(loadCache()); return
        }

        // Exponential backoff
        if FileManager.default.fileExists(atPath: backoffFile.path),
           let s    = try? String(contentsOf: backoffFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           let wait = TimeInterval(s),
           fileAge(backoffFile) < wait {
            completion(loadCache()); return
        }

        // Lock
        if fileAge(lockFile) < 30 {
            completion(loadCache()); return
        }
        FileManager.default.createFile(atPath: lockFile.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: lockFile) }

        guard let token = getToken() else { completion(loadCache()); return }

        var req = URLRequest(url: apiURL, timeoutInterval: 5)
        req.setValue("Bearer \(token)",          forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20",          forHTTPHeaderField: "anthropic-beta")
        req.setValue("claude-code/\(claudeVersion())", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: req) { data, _, error in
            guard error == nil, let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { completion(loadCache()); return }

            if let errType = (json["error"] as? [String: Any])?["type"] as? String {
                if errType == "rate_limit_error" {
                    let prev = (try? String(contentsOf: backoffFile, encoding: .utf8)
                        .trimmingCharacters(in: .whitespacesAndNewlines))
                        .flatMap { TimeInterval($0) } ?? 60
                    try? "\(Int(min(prev * 2, 600)))".write(to: backoffFile, atomically: true, encoding: .utf8)
                }
                completion(loadCache()); return
            }

            try? FileManager.default.removeItem(at: backoffFile)
            try? data.write(to: apiCacheFile)
            completion(json)
        }.resume()
    }
}

func parseUsage(_ json: [String: Any]) -> UsageData {
    let fh = json["five_hour"] as? [String: Any]
    let sd = json["seven_day"]  as? [String: Any]
    return UsageData(
        fiveHourPct:      fh?["utilization"] as? Double,
        fiveHourResetsAt: fh?["resets_at"]   as? String,
        sevenDayPct:      sd?["utilization"] as? Double,
        sevenDayResetsAt: sd?["resets_at"]   as? String
    )
}

func timeLeft(_ iso: String) -> String {
    let fmt = ISO8601DateFormatter()
    fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var date = fmt.date(from: iso)
    if date == nil {
        fmt.formatOptions = [.withInternetDateTime]
        date = fmt.date(from: iso)
    }
    guard let date else { return "?" }
    let secs = Int(date.timeIntervalSinceNow)
    guard secs > 0 else { return "~0м" }
    let d = secs / 86400
    let h = (secs % 86400) / 3600
    let m = (secs % 3600) / 60
    if d > 0 { return "\(d)д\(h)ч" }
    if h > 0 { return "\(h)ч\(m)м" }
    return "\(m)м"
}
