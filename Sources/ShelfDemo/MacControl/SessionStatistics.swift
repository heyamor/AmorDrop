import Combine
import Foundation

struct SessionRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let source: String
    let startedAt: Date
    let endedAt: Date
    var duration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }
}

/// Local-only completed-session history. Concurrent owners are counted
/// separately; totals are session-hours, not unique wall-clock hours.
@MainActor
final class SessionStatistics: ObservableObject {
    private struct Snapshot: Codable {
        var records: [SessionRecord] = []
        var count = 0
        var seconds: TimeInterval = 0
    }
    private static let key = "macControl.sessionStatistics.v1"
    private let defaults: UserDefaults
    @Published private var snapshot = Snapshot()
    @Published var enabled: Bool {
        didSet { defaults.set(enabled, forKey: "macControl.recordSessionStatistics") }
    }
    var records: [SessionRecord] { snapshot.records }
    var count: Int { snapshot.count }
    var seconds: TimeInterval { snapshot.seconds }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.object(forKey: "macControl.recordSessionStatistics") as? Bool ?? true
        if let data = defaults.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(Snapshot.self, from: data) { snapshot = saved }
    }

    func record(source: String, startedAt: Date, endedAt: Date) {
        guard enabled, endedAt >= startedAt else { return }
        let record = SessionRecord(id: UUID(), source: source, startedAt: startedAt, endedAt: endedAt)
        snapshot.records.insert(record, at: 0)
        snapshot.records = Array(snapshot.records.prefix(200))
        snapshot.count += 1
        snapshot.seconds += record.duration
        persist()
    }

    func clear() {
        snapshot = Snapshot()
        defaults.removeObject(forKey: Self.key)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: Self.key) }
    }
}

enum SessionDurationOptions {
    static let minutes = [30, 60, 120, 180, 240, 360, 480, 720]
    static func label(minutes: Int) -> String {
        minutes < 60 ? "\(minutes) \(L("minutes"))" : "\(minutes / 60) \(L("hours"))"
    }
    static func clock(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(ceil(seconds)))
        return String(format: "%02d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
    }
}
