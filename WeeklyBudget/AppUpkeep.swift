import SwiftUI
import UserNotifications

/// Keeps a sideloaded copy alive: warns before its signature runs out (free Apple IDs sign for 7 days)
/// and when GitHub has a newer version. Each phone warns its own owner, whichever tool installed it.
@MainActor @Observable
final class AppUpkeep {
    static let shared = AppUpkeep()

    /// When this copy stops opening. Nil for builds with no signing profile (simulator, App Store).
    private(set) var expiry: Date?
    /// A newer version on GitHub, like "1.4".
    private(set) var newerVersion: String?

    static let repo = "https://github.com/Rahul-Das-456/weekly-budget"
    private let versionURL = URL(string: "https://raw.githubusercontent.com/Rahul-Das-456/weekly-budget/main/project.yml")!
    private let lastCheckKey = "upkeep.lastGitHubCheck"
    private let notifiedVersionKey = "upkeep.notifiedVersion"
    private let remoteVersionKey = "upkeep.remoteVersion"

    var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }

    /// AltStore and SideStore add ALT keys to the Info.plist they install; phoneapps doesn't.
    var installedWithAltStore: Bool { Bundle.main.object(forInfoDictionaryKey: "ALTDeviceID") != nil }

    var hoursLeft: Double? { expiry.map { $0.timeIntervalSinceNow / 3600 } }
    var expiresSoon: Bool { (hoursLeft ?? .infinity) <= 48 }

    /// What to do to re-sign this copy, in the words of the tool that installed it.
    var refreshHowTo: String {
        installedWithAltStore
            ? "Open AltStore (or SideStore) and tap Refresh All."
            : "Leave your iPhone unlocked on the same Wi-Fi as your Mac (it refreshes on its own), or run phoneapps refresh on the Mac."
    }

    var updateHowTo: String {
        installedWithAltStore
            ? "Download WeeklyBudget.ipa from GitHub and open it in AltStore (My Apps → +). Your budget stays."
            : "Run phoneapps update budget on your Mac, or just wait: auto refresh picks it up. Your budget stays."
    }

    private init() {}

    /// Call on launch and whenever the app comes to the front.
    func refresh() async {
        expiry = Self.readExpiry()
        // GitHub first: the expiry alerts may wait on the notification permission prompt.
        await checkGitHub()
        await scheduleExpiryAlerts()
    }

    // MARK: Signing

    private static func readExpiry() -> Date? {
        // Debug / screenshots: `-signingExpiresInHours 30`.
        let fake = UserDefaults.standard.double(forKey: "signingExpiresInHours")
        if fake != 0 { return Date().addingTimeInterval(fake * 3600) }
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(from: data[start.lowerBound..<end.upperBound], format: nil) as? [String: Any]
        else { return nil }
        return plist["ExpirationDate"] as? Date
    }

    /// Notifications at 2 days, 1 day and 3 hours before expiry. Scheduled ahead of time, so they arrive
    /// even once the app can no longer open. Redone on every launch, so a refreshed copy moves them out.
    private func scheduleExpiryAlerts() async {
        let center = UNUserNotificationCenter.current()
        let ids = ["upkeep.expiry.48", "upkeep.expiry.24", "upkeep.expiry.3"]
        center.removePendingNotificationRequests(withIdentifiers: ids)
        guard let expiry, await allowed() else { return }
        for (id, hours) in zip(ids, [48.0, 24.0, 3.0]) {
            let when = expiry.addingTimeInterval(-hours * 3600)
            guard when > Date() else { continue }
            let c = UNMutableNotificationContent()
            c.title = hours >= 24 ? "Budget stops opening in \(Int(hours / 24)) day\(hours >= 48 ? "s" : "")" : "Budget stops opening in 3 hours"
            c.body = refreshHowTo + " Already refreshed? Open Budget once and this goes away."
            c.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: when.timeIntervalSinceNow, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: id, content: c, trigger: trigger))
        }
    }

    // MARK: Updates

    /// Reads MARKETING_VERSION from the repo's project.yml, at most every 6 hours unless forced.
    func checkGitHub(force: Bool = false) async {
        let d = UserDefaults.standard
        if !force, d.string(forKey: "upkeepFakeRemoteVersion") == nil, Date().timeIntervalSince1970 - d.double(forKey: lastCheckKey) < 6 * 3600 {
            // Checked recently: reuse what GitHub said last time.
            if let last = d.string(forKey: remoteVersionKey) { newerVersion = Self.isNewer(last, than: current) ? last : nil }
            return
        }
        guard let (data, resp) = try? await URLSession.shared.data(from: versionURL),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let text = String(data: data, encoding: .utf8),
              let line = text.split(separator: "\n").first(where: { $0.contains("MARKETING_VERSION") })
        else { return }
        d.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
        var remote = line.split(separator: ":", maxSplits: 1).last.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"'")) } ?? ""
        if let fake = d.string(forKey: "upkeepFakeRemoteVersion") { remote = fake }   // debug: -upkeepFakeRemoteVersion 9.9
        d.set(remote, forKey: remoteVersionKey)
        newerVersion = Self.isNewer(remote, than: current) ? remote : nil
        guard let v = newerVersion, d.string(forKey: notifiedVersionKey) != v, await allowed() else { return }
        d.set(v, forKey: notifiedVersionKey)
        let c = UNMutableNotificationContent()
        c.title = "Budget \(v) is out"
        c.body = updateHowTo
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "upkeep.update.\(v)", content: c, trigger: nil))
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    private func allowed() async -> Bool {
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .notDetermined: return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default: return false
        }
    }
}

/// Shown at the top of the main screen when this copy expires within 2 days or GitHub has a newer version.
struct UpkeepBanner: View {
    private var upkeep: AppUpkeep { .shared }

    var body: some View {
        if upkeep.expiresSoon, let h = upkeep.hoursLeft {
            banner(icon: "exclamationmark.triangle.fill", color: .orange,
                   title: h <= 0 ? "This copy has expired" : "Stops opening in \(Self.left(h))",
                   text: upkeep.refreshHowTo)
                .accessibilityIdentifier("upkeep-expiry")
        }
        if let v = upkeep.newerVersion {
            banner(icon: "arrow.down.circle.fill", color: .blue, title: "Version \(v) is on GitHub", text: upkeep.updateHowTo)
                .accessibilityIdentifier("upkeep-update")
        }
    }

    static func left(_ hours: Double) -> String {
        hours >= 24 ? "\(Int((hours / 24).rounded(.up))) days" : "\(max(1, Int(hours.rounded(.up)))) hours"
    }

    private func banner(icon: String, color: Color, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(color).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Settings section: when this copy expires, how to refresh, and a manual update check.
struct UpkeepSettingsSection: View {
    private var upkeep: AppUpkeep { .shared }
    @State private var checking = false

    var body: some View {
        Section {
            if let e = upkeep.expiry {
                LabeledContent("Opens until", value: e.formatted(date: .abbreviated, time: .shortened))
            } else {
                Text("Not a sideloaded copy, so it doesn't expire.").foregroundStyle(.secondary)
            }
            LabeledContent("Version", value: upkeep.current)
            if let v = upkeep.newerVersion {
                Text("Version \(v) is on GitHub. \(upkeep.updateHowTo)").font(.subheadline)
            }
            Button(checking ? "Checking…" : "Check GitHub for a new version") {
                checking = true
                Task { await upkeep.checkGitHub(force: true); checking = false }
            }
            .disabled(checking)
            .accessibilityIdentifier("upkeep-check")
        } header: {
            Text("App updates")
        } footer: {
            Text("You'll get a notification 2 days, 1 day and 3 hours before this copy stops opening, and when a new version is on GitHub. To refresh: \(upkeep.refreshHowTo)")
        }
    }
}
