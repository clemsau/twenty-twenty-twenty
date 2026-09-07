import Foundation

@MainActor
protocol Notifier: AnyObject {
    func notify(withSound: Bool)
}
