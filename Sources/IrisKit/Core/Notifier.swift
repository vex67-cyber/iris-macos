import Foundation
import UserNotifications

/// 通知（可选功能）。只有作为完整 App Bundle 运行时才可用。
public final class Notifier {

    public static let shared = Notifier()

    /// `swift run` 调试时没有 bundle，UNUserNotificationCenter 会崩溃，必须先判断。
    public var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    private init() {}

    public func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard isAvailable else {
            DispatchQueue.main.async { completion(false) }
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    public func post(title: String, body: String, after: TimeInterval = 1) {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, after), repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    public func cancelAll() {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
