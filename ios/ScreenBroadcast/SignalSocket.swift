import Foundation

final class SignalSocket {
    var onMessage: (([String: Any]) -> Void)?
    var onOpen: (() -> Void)?
    var onError: ((Error) -> Void)?

    private let session = URLSession(configuration: .default)
    private var task: URLSessionWebSocketTask?

    func connect(url: URL) {
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        task.sendPing { [weak self] error in
            if let error { self?.onError?(error) } else {
                self?.onOpen?()
                self?.receive()
            }
        }
    }

    func send(_ object: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(text)) { [weak self] error in
            if let error { self?.onError?(error) }
        }
    }

    private func receive() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                let data: Data?
                switch message {
                case .string(let text): data = text.data(using: .utf8)
                case .data(let value): data = value
                @unknown default: data = nil
                }
                if let data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    self.onMessage?(json)
                }
                self.receive()
            case .failure(let error): self.onError?(error)
            }
        }
    }

    func close() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }
}

