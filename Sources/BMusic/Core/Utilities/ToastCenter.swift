import Foundation
import SwiftUI

struct ToastMessage: Identifiable {
    enum Style {
        case info, success, error
    }

    let id = UUID()
    var text: String
    var symbol: String
    var style: Style
}

@MainActor
final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()

    @Published private(set) var current: ToastMessage?
    private var dismissTask: Task<Void, Never>?

    func show(_ text: String, symbol: String = "checkmark.circle.fill", style: ToastMessage.Style = .info) {
        dismissTask?.cancel()
        let message = ToastMessage(text: text, symbol: symbol, style: style)
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            current = message
        }
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self?.current?.id == message.id else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    self?.current = nil
                }
            }
        }
    }

    func error(_ text: String) {
        show(text, symbol: "exclamationmark.triangle.fill", style: .error)
    }

    func success(_ text: String) {
        show(text, symbol: "checkmark.circle.fill", style: .success)
    }
}
