import Combine
import Foundation

struct NativeReceiverDevice: Identifiable, Equatable {
    let name: String
    let host: String
    let port: Int
    let roomCode: String
    var id: String { "\(host):\(port)" }
}

@MainActor
final class NativeReceiverManager: NSObject, ObservableObject {
    @Published private(set) var devices: [NativeReceiverDevice] = []
    @Published private(set) var connectedDevice: NativeReceiverDevice?
    @Published private(set) var isConnected = false
    @Published private(set) var status = "Szukam aplikacji MiBox Screen na telewizorze…"
    @Published private(set) var errorMessage: String?

    private let browser = NetServiceBrowser()
    private var services: [NetService] = []
    private var socket: URLSessionWebSocketTask?

    override init() {
        super.init()
        browser.delegate = self
    }

    func start() {
        guard socket == nil else { return }
        browser.searchForServices(ofType: "_miboxscreen._tcp.", inDomain: "local.")
    }

    func stop() {
        browser.stop()
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        isConnected = false
    }

    func connect(_ device: NativeReceiverDevice) {
        socket?.cancel(with: .goingAway, reason: nil)
        guard let url = URL(string: "ws://\(device.host):\(device.port)/signal") else { return }
        connectedDevice = device
        status = "Łączenie z \(device.name)…"
        errorMessage = nil
        let task = URLSession.shared.webSocketTask(with: url)
        socket = task
        task.resume()
        receive(on: task)
        send([
            "type": "join",
            "role": "sender",
            "roomCode": device.roomCode,
            "isPro": false
        ])
    }

    func play(_ url: URL, title: String? = nil, headers: [String: String] = [:]) {
        guard isConnected else {
            errorMessage = "Uruchom MiBox Screen na telewizorze i połącz odbiornik."
            return
        }
        status = "Wysyłam film do Mi Boxa…"
        errorMessage = nil
        send([
            "type": "play",
            "url": url.absoluteString,
            "title": title ?? "Wideo z iPhone'a",
            "headers": headers
        ])
    }

    func reconnect() {
        if let connectedDevice { connect(connectedDevice) } else { start() }
    }

    private func send(_ object: [String: Any]) {
        guard let socket,
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return }
        socket.send(.string(text)) { [weak self] error in
            guard let error else { return }
            Task { @MainActor in
                self?.isConnected = false
                self?.errorMessage = "Nie udało się wysłać polecenia: \(error.localizedDescription)"
            }
        }
    }

    private func receive(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.socket === task else { return }
                switch result {
                case .success(let message):
                    let text: String
                    switch message {
                    case .string(let value): text = value
                    case .data(let data): text = String(data: data, encoding: .utf8) ?? ""
                    @unknown default: text = ""
                    }
                    self.handle(text)
                    self.receive(on: task)
                case .failure(let error):
                    self.isConnected = false
                    self.status = "Odbiornik rozłączony"
                    self.errorMessage = error.localizedDescription
                    self.socket = nil
                }
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }
        switch type {
        case "joined", "peer-joined":
            isConnected = true
            status = "Połączono z aplikacją na Mi Boxie"
            errorMessage = nil
        case "playback-status":
            let state = json["state"] as? String ?? ""
            if state == "error" {
                errorMessage = json["error"] as? String ?? "Mi Box nie może odtworzyć filmu."
                status = "Błąd odtwarzania"
            } else {
                status = [
                    "loading": "Ładowanie filmu…",
                    "buffering": "Buforowanie…",
                    "playing": "Film jest odtwarzany na Mi Boxie",
                    "paused": "Pauza",
                    "ended": "Film zakończony"
                ][state] ?? state
            }
        case "error":
            errorMessage = json["message"] as? String ?? "Błąd odbiornika"
        default: break
        }
    }

    private func addResolved(_ service: NetService) {
        guard let host = service.hostName?.trimmingCharacters(in: CharacterSet(charactersIn: ".")),
              service.port > 0 else { return }
        let txt = NetService.dictionary(fromTXTRecord: service.txtRecordData() ?? Data())
        let room = txt["room"].flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let device = NativeReceiverDevice(name: service.name, host: host, port: service.port, roomCode: room)
        if !devices.contains(device) { devices.append(device) }
        status = "Znaleziono \(device.name)"
        if connectedDevice == nil { connect(device) }
    }
}

extension NativeReceiverManager: NetServiceBrowserDelegate, NetServiceDelegate {
    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        Task { @MainActor in
            services.append(service)
            service.delegate = self
            service.resolve(withTimeout: 5)
        }
    }

    nonisolated func netServiceDidResolveAddress(_ sender: NetService) {
        Task { @MainActor in addResolved(sender) }
    }

    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        Task { @MainActor in
            status = "Nie udało się przeszukać sieci lokalnej"
            errorMessage = "Sprawdź dostęp aplikacji do sieci lokalnej w Ustawieniach iPhone'a."
        }
    }
}
