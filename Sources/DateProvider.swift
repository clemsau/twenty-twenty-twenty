import Foundation

@MainActor
protocol DateProvider {
    var now: Date { get }
}

@MainActor
struct SystemDateProvider: DateProvider {
    var now: Date { Date() }
}
