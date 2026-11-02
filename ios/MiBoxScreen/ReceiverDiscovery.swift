import Combine
import Darwin
import Foundation

final class ReceiverDiscovery: NSObject, ObservableObject {
    @Published private(set) var receiverName: String?
    @Published private(set) var serverURL: String?
    @Published private(set) var status = "Szukanie odbiornika w sieci Wi‑Fi…"

    private let browser = NetServiceBrowser()
    private var services: [NetService] = []
    private var isRunning = false
    private let udpQueue = DispatchQueue(label: "pl.miboxscreen.discovery.udp", qos: .userInitiated)
    private var udpSocket: Int32 = -1

    override init() {
        super.init()
        browser.delegate = self
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        status = "Szukanie odbiornika w sieci Wi‑Fi…"
        browser.searchForServices(ofType: "_miboxscreen._tcp.", inDomain: "local.")
        startUDPDiscovery()
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
        closeUDPSocket()
        isRunning = false
    }

    private func startUDPDiscovery() {
        udpQueue.async { [weak self] in
            guard let self, self.isRunning else { return }
            let descriptor = Darwin.socket(AF_INET, SOCK_DGRAM.rawValue, IPPROTO_UDP)
            guard descriptor >= 0 else { return }
            self.udpSocket = descriptor

            var enabled: Int32 = 1
            setsockopt(descriptor, SOL_SOCKET, SO_BROADCAST, &enabled, socklen_t(MemoryLayout.size(ofValue: enabled)))

            var timeout = timeval(tv_sec: 1, tv_usec: 0)
            setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))

            var localAddress = sockaddr_in()
            localAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            localAddress.sin_family = sa_family_t(AF_INET)
            localAddress.sin_port = 0
            localAddress.sin_addr = in_addr(s_addr: INADDR_ANY)
            withUnsafePointer(to: &localAddress) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    _ = Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }

            let request = Array("MIBOXSCREEN_DISCOVER_V1".utf8)
            var broadcastAddress = sockaddr_in()
            broadcastAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            broadcastAddress.sin_family = sa_family_t(AF_INET)
            broadcastAddress.sin_port = in_port_t(45_321).bigEndian
            broadcastAddress.sin_addr = in_addr(s_addr: INADDR_BROADCAST)

            request.withUnsafeBytes { bytes in
                withUnsafePointer(to: &broadcastAddress) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        _ = Darwin.sendto(
                            descriptor,
                            bytes.baseAddress,
                            bytes.count,
                            0,
                            $0,
                            socklen_t(MemoryLayout<sockaddr_in>.size)
                        )
                    }
                }
            }

            let deadline = Date().addingTimeInterval(6)
            var buffer = [UInt8](repeating: 0, count: 512)
            while self.isRunning && Date() < deadline {
                var senderAddress = sockaddr_in()
                var senderLength = socklen_t(MemoryLayout<sockaddr_in>.size)
                let count = withUnsafeMutablePointer(to: &senderAddress) { addressPointer in
                    addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                        Darwin.recvfrom(descriptor, &buffer, buffer.count, 0, socketAddress, &senderLength)
                    }
                }
                guard count > 0 else { continue }
                let message = String(decoding: buffer.prefix(Int(count)), as: UTF8.self)
                let parts = message.split(separator: "|", omittingEmptySubsequences: false)
                guard parts.count >= 4,
                      parts[0] == "MIBOXSCREEN_RECEIVER_V1",
                      let port = UInt16(parts[1]) else { continue }

                var address = senderAddress.sin_addr
                var addressBuffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                guard inet_ntop(AF_INET, &address, &addressBuffer, socklen_t(INET_ADDRSTRLEN)) != nil else { continue }
                let host = String(cString: addressBuffer)
                let name = String(parts[3])
                DispatchQueue.main.async {
                    self.receiverName = name
                    self.serverURL = "ws://\(host):\(port)/signal"
                    self.status = "Odbiornik gotowy"
                }
                break
            }
            self.closeUDPSocket(descriptor)
        }
    }

    private func closeUDPSocket(_ expectedDescriptor: Int32? = nil) {
        let descriptor = udpSocket
        guard descriptor >= 0, expectedDescriptor == nil || expectedDescriptor == descriptor else { return }
        udpSocket = -1
        Darwin.close(descriptor)
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
