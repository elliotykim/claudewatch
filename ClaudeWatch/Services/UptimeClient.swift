import Foundation

/// Fetches incident history from the Claude status page and computes
/// per-component daily uptime for the last 90 days.
struct UptimeClient {

    let session: URLSession
    let componentsEndpoint: URL
    let incidentsEndpoint: URL
    let statusPageURL: URL

    init(
        session: URLSession = .shared,
        componentsEndpoint: URL = URL(string: "https://status.claude.com/api/v2/components.json")!,
        incidentsEndpoint: URL = URL(string: "https://status.claude.com/api/v2/incidents.json")!,
        statusPageURL: URL = URL(string: "https://status.claude.com")!
    ) {
        self.session = session
        self.componentsEndpoint = componentsEndpoint
        self.incidentsEndpoint = incidentsEndpoint
        self.statusPageURL = statusPageURL
    }

    enum FetchError: Error, LocalizedError {
        case http(Int)
        case transport(Error)
        case malformed
        var errorDescription: String? {
            switch self {
            case .http(let c): return "HTTP \(c)"
            case .transport(let e): return e.localizedDescription
            case .malformed: return "Unexpected response format"
            }
        }
    }

    /// Fetch 90-day uptime history for all known components.
    func fetch() async -> Result<[ComponentUptime], FetchError> {
        let componentStatuses: [String: Severity]
        switch await fetchComponentStatuses() {
        case .success(let s): componentStatuses = s
        case .failure(let e): return .failure(e)
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let startDate = calendar.date(byAdding: .day, value: -89, to: today) else {
            return .failure(.malformed)
        }

        let incidents: [[String: Any]]
        switch await fetchAllIncidents(since: startDate) {
        case .success(let i): incidents = i
        case .failure(let e): return .failure(e)
        }

        // Scrape official 90-day uptime percentages from the status page HTML
        let officialUptime = await scrapeUptimePercentages()

        var results: [ComponentUptime] = []
        for component in StatusComponent.all {
            let currentSeverity = componentStatuses[component.id] ?? .operational
            let (days, merged) = computeUptime(
                componentID: component.id,
                incidents: incidents,
                startDate: startDate,
                endDate: today,
                calendar: calendar
            )
            var uptimeByDuration: [Int: Double] = [:]
            // Use official 90-day value from the status page
            if let official = officialUptime[component.id] {
                uptimeByDuration[90] = official
            }
            // Compute 30/60 day values from incident data
            for duration in [30, 60] {
                let windowStart = calendar.date(byAdding: .day, value: -(duration - 1), to: today)!
                let windowEnd = calendar.date(byAdding: .day, value: 1, to: today)!
                let totalSec = windowEnd.timeIntervalSince(windowStart)
                let downSec = merged.reduce(0.0) { sum, r in
                    let s = max(r.start, windowStart)
                    let e = min(r.end, windowEnd)
                    return s < e ? sum + e.timeIntervalSince(s) : sum
                }
                uptimeByDuration[duration] = max(0, min(100, (1 - downSec / totalSec) * 100))
            }
            results.append(ComponentUptime(
                id: component.id,
                name: component.name,
                currentSeverity: currentSeverity,
                days: days,
                uptimeByDuration: uptimeByDuration
            ))
        }
        return .success(results)
    }

    // MARK: - API

    /// Scrape official 90-day uptime percentages from the status page HTML.
    /// Returns [componentID: percentage].
    private func scrapeUptimePercentages() async -> [String: Double] {
        var req = URLRequest(url: statusPageURL)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("ClaudeWatch/1.0", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await session.data(for: req),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let html = String(data: data, encoding: .utf8)
        else { return [:] }

        // Parse: <var data-var="uptime-percent">99.26</var> preceded by
        //        <span id="uptime-percent-{componentID}">
        var results: [String: Double] = [:]
        let pattern = #"id=\"uptime-percent-([a-z0-9]+)\">\s*<var[^>]*>([0-9.]+)</var>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [:] }
        let range = NSRange(html.startIndex..., in: html)
        for match in regex.matches(in: html, range: range) {
            guard let idRange = Range(match.range(at: 1), in: html),
                  let valRange = Range(match.range(at: 2), in: html),
                  let value = Double(html[valRange]),
                  value >= 0, value <= 100
            else { continue }
            results[String(html[idRange])] = value
        }
        return results
    }

    private func fetchComponentStatuses() async -> Result<[String: Severity], FetchError> {
        var req = URLRequest(url: componentsEndpoint)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("ClaudeWatch/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { return .failure(.http(0)) }
            guard http.statusCode == 200 else { return .failure(.http(http.statusCode)) }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let components = json["components"] as? [[String: Any]]
            else { return .failure(.malformed) }

            var statuses: [String: Severity] = [:]
            for comp in components {
                if let id = comp["id"] as? String, let status = comp["status"] as? String {
                    statuses[id] = Severity(componentStatus: status)
                }
            }
            return .success(statuses)
        } catch {
            return .failure(.transport(error))
        }
    }

    private func fetchAllIncidents(since cutoff: Date) async -> Result<[[String: Any]], FetchError> {
        var allIncidents: [[String: Any]] = []
        var page = 1
        let perPage = 100

        let maxPages = 10
        while page <= maxPages {
            var comps = URLComponents(url: incidentsEndpoint, resolvingAgainstBaseURL: false)!
            comps.queryItems = [
                URLQueryItem(name: "page", value: "\(page)"),
                URLQueryItem(name: "per_page", value: "\(perPage)")
            ]
            guard let url = comps.url else { break }

            var req = URLRequest(url: url)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            req.setValue("ClaudeWatch/1.0", forHTTPHeaderField: "User-Agent")

            do {
                let (data, response) = try await session.data(for: req)
                guard let http = response as? HTTPURLResponse else { return .failure(.http(0)) }
                guard http.statusCode == 200 else { return .failure(.http(http.statusCode)) }

                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let incidents = json["incidents"] as? [[String: Any]]
                else { return .failure(.malformed) }

                if incidents.isEmpty { break }

                var reachedCutoff = false
                for incident in incidents {
                    guard let createdStr = incident["created_at"] as? String,
                          let created = Self.parseISO8601(createdStr)
                    else { continue }

                    if created < cutoff {
                        // Include if the incident was still active during our window
                        if let resolvedStr = incident["resolved_at"] as? String,
                           let resolved = Self.parseISO8601(resolvedStr),
                           resolved > cutoff {
                            allIncidents.append(incident)
                        }
                        reachedCutoff = true
                        continue
                    }
                    allIncidents.append(incident)
                }

                if reachedCutoff || incidents.count < perPage { break }
                page += 1
            } catch {
                return .failure(.transport(error))
            }
        }
        return .success(allIncidents)
    }

    // MARK: - Computation

    private struct IncidentRange {
        let start: Date
        let end: Date
        let severity: Severity
    }

    private func computeUptime(
        componentID: String,
        incidents: [[String: Any]],
        startDate: Date,
        endDate: Date,
        calendar: Calendar
    ) -> ([DayStatus], [(start: Date, end: Date)]) {
        let periodEnd = calendar.date(byAdding: .day, value: 1, to: endDate)!

        // Collect incident time ranges that affect this component
        var ranges: [IncidentRange] = []
        for incident in incidents {
            guard let impactStr = incident["impact"] as? String else { continue }
            let severity = Severity(incidentImpact: impactStr)
            if severity == .operational { continue }

            guard let components = incident["components"] as? [[String: Any]],
                  components.contains(where: { ($0["id"] as? String) == componentID })
            else { continue }

            guard let startedStr = incident["started_at"] as? String ?? incident["created_at"] as? String,
                  let incidentStart = Self.parseISO8601(startedStr)
            else { continue }

            let incidentEnd: Date
            if let resolvedStr = incident["resolved_at"] as? String,
               let resolved = Self.parseISO8601(resolvedStr) {
                incidentEnd = resolved
            } else {
                incidentEnd = Date()
            }

            let clippedStart = max(incidentStart, startDate)
            let clippedEnd = min(incidentEnd, periodEnd)
            if clippedStart < clippedEnd {
                ranges.append(IncidentRange(start: clippedStart, end: clippedEnd, severity: severity))
            }
        }

        // Day-level severity map (worst per day)
        let totalDays = (calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 0) + 1
        var daySeverities = [Int: Severity]()

        for range in ranges {
            var dayStart = calendar.startOfDay(for: range.start)
            let lastDay = calendar.startOfDay(for: range.end.addingTimeInterval(-1))
            while dayStart <= lastDay && dayStart <= endDate {
                let offset = calendar.dateComponents([.day], from: startDate, to: dayStart).day ?? 0
                if offset >= 0 && offset < totalDays {
                    if let existing = daySeverities[offset] {
                        if range.severity > existing { daySeverities[offset] = range.severity }
                    } else {
                        daySeverities[offset] = range.severity
                    }
                }
                dayStart = calendar.date(byAdding: .day, value: 1, to: dayStart)!
            }
        }

        var days: [DayStatus] = []
        for i in 0..<totalDays {
            let date = calendar.date(byAdding: .day, value: i, to: startDate)!
            days.append(DayStatus(date: date, severity: daySeverities[i] ?? .operational))
        }

        // Merge overlapping incident ranges for duration-based uptime calculation
        let sorted = ranges.sorted { $0.start < $1.start }
        var merged: [(start: Date, end: Date)] = []
        for r in sorted {
            if let last = merged.last, r.start <= last.end {
                merged[merged.count - 1].end = max(last.end, r.end)
            } else {
                merged.append((r.start, r.end))
            }
        }

        return (days, merged)
    }

    // MARK: - Date Parsing

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoStandard: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseISO8601(_ string: String) -> Date? {
        isoFractional.date(from: string) ?? isoStandard.date(from: string)
    }
}
