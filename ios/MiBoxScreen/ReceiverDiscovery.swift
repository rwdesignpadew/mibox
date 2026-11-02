import Combine
import Foundation

final class ReceiverDiscovery: NSObject, ObservableObject {
    @Published private(set) var receiverName: String?
    @Published private(set) var serverURL: String?
    @Published private(set) var status = "Szukanie odbiornika w sieci Wi‑Fi…"

    private let browser = NetServiceBrowser()
    private var services: [NetService] = []
    private var isRunning = false

    override init() {
        super.init()
        browser.delegate = self
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        status = "Szukanie odbiornika w sieci Wi‑Fi…"
        browser.searchForServices(ofType: "_miboxscreen._tcp.", inDomain: "local.")
    }

    func restart() {
        stop()
        services.removeAll()
        receiverName = nil
        serverURL = nil
        start()
    }

    func stop() {
        guard isRunning else { return }
        browser.stop()
        services.forEach { $0.stop() }
        isRunning = false
    }
}

extension ReceiverDiscovery: NetServiceBrowserDelegate {
    func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) {
        DispatchQueue.main.async { self.status = "Szukanie odbiornika w sieci Wi‑Fi…" }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        guard !services.contains(where: { $0.name == service.name }) else { return }
        services.append(service)
        service.delegate = self
        service.resolve(withTimeout: 5)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        services.removeAll { $0.name == service.name }
        if receiverName == service.name {
            DispatchQueue.main.async {
                self.receiverName = nil
                self.serverURL = nil
                self.status = "Odbiornik zniknął z sieci"
            }
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        DispatchQueue.main.async {
            self.status = "Nie udało się przeszukać sieci lokalnej"
        }
    }
}

extension ReceiverDiscovery: NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let rawHost = sender.hostName, sender.port > 0 else { return }
        let host = rawHost.hasSuffix(".") ? String(rawHost.dropLast()) : rawHost
        DispatchQueue.main.async {
            self.receiverName = sender.name
            self.serverURL = "ws://\(host):\(sender.port)/signal"
            self.status = "Odbiornik gotowy"
        }
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        DispatchQueue.main.async { self.status = "Znaleziono odbiornik, ale nie można ustalić jego adresu" }
    }
}
