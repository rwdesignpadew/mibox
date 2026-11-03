import AVFoundation
import Darwin
import Foundation
import Network
import UniformTypeIdentifiers

final class HLSStreamServer: NSObject, AVAssetWriterDelegate {
    private struct Segment {
        let sequence: Int
        let data: Data
    }

    private let queue = DispatchQueue(label: "pl.miboxscreen.hls")
    private let port: NWEndpoint.Port = 8090
    private let segmentDuration = 1.0
    private let maximumSegmentCount = 45
    private var listener: NWListener?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var initializationSegment: Data?
    private var segments: [Segment] = []
    private var nextSequence = 0
    private var sessionID = UUID().uuidString

    func start() throws {
        SharedSettings.defaults.removeObject(forKey: SharedSettings.streamURLKey)
        initializationSegment = nil
        segments.removeAll(keepingCapacity: true)
        nextSequence = 0
        sessionID = UUID().uuidString
        let listener = try NWListener(using: .tcp, on: port)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connection.start(queue: self.queue)
            self.receiveRequest(on: connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.stop() }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.videoInput?.markAsFinished()
            self.writer?.finishWriting {}
            self.writer = nil
            self.videoInput = nil
            self.listener?.cancel()
            self.listener = nil
            SharedSettings.defaults.removeObject(forKey: SharedSettings.streamURLKey)
        }
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        queue.async { [weak self] in self?.appendOnQueue(sampleBuffer) }
    }

    private func appendOnQueue(_ sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        if writer == nil, !configureWriter(from: sampleBuffer) { return }
        guard let writer, let videoInput else { return }

        if writer.status == .unknown {
            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        }
        if writer.status == .writing, videoInput.isReadyForMoreMediaData {
            videoInput.append(sampleBuffer)
        }
    }

    private func configureWriter(from sampleBuffer: CMSampleBuffer) -> Bool {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return false }
        do {
            let writer = try AVAssetWriter(contentType: .mpeg4Movie)
            writer.delegate = self
            writer.outputFileTypeProfile = .mpeg4AppleHLS
            writer.preferredOutputSegmentInterval = CMTime(seconds: segmentDuration, preferredTimescale: 600)
            writer.initialSegmentStartTime = .zero

            let sourceWidth = CVPixelBufferGetWidth(imageBuffer)
            let sourceHeight = CVPixelBufferGetHeight(imageBuffer)
            let scale = min(1, min(1920.0 / Double(sourceWidth), 1080.0 / Double(sourceHeight)))
            let width = max(2, Int(Double(sourceWidth) * scale) / 2 * 2)
            let height = max(2, Int(Double(sourceHeight) * scale) / 2 * 2)
            let settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 3_000_000,
                    AVVideoExpectedSourceFrameRateKey: 30,
                    AVVideoMaxKeyFrameIntervalKey: 30,
                    AVVideoMaxKeyFrameIntervalDurationKey: segmentDuration,
                    AVVideoAllowFrameReorderingKey: false,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264MainAutoLevel
                ]
            ]
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else { return false }
            writer.add(input)
            self.writer = writer
            videoInput = input
            return true
        } catch {
            return false
        }
    }

    func assetWriter(
        _ writer: AVAssetWriter,
        didOutputSegmentData segmentData: Data,
        segmentType: AVAssetSegmentType,
        segmentReport: AVAssetSegmentReport?
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            if segmentType == .initialization {
                self.initializationSegment = segmentData
            } else {
                self.segments.append(Segment(sequence: self.nextSequence, data: segmentData))
                self.nextSequence += 1
                if self.segments.count > self.maximumSegmentCount { self.segments.removeFirst() }
            }
            self.publishURLIfReady()
        }
    }

    private func publishURLIfReady() {
        guard initializationSegment != nil, !segments.isEmpty,
              let address = Self.wifiIPv4Address() else { return }
        SharedSettings.defaults.set(
            "http://\(address):\(port.rawValue)/live.m3u8?session=\(sessionID)",
            forKey: SharedSettings.streamURLKey
        )
    }

    private func receiveRequest(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, error in
            guard let self, error == nil, let data,
                  let request = String(data: data, encoding: .utf8),
                  let firstLine = request.split(separator: "\r\n").first else {
                connection.cancel()
                return
            }
            let requestTarget = firstLine.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
            let path = requestTarget.split(separator: "?", maxSplits: 1).first.map(String.init) ?? "/"
            self.sendResponse(for: path, on: connection)
        }
    }

    private func sendResponse(for path: String, on connection: NWConnection) {
        let body: Data?
        let contentType: String
        if path == "/live.m3u8" {
            body = playlist().data(using: .utf8)
            contentType = "application/vnd.apple.mpegurl"
        } else if path == "/init.mp4" {
            body = initializationSegment
            contentType = "video/mp4"
        } else if let name = path.split(separator: "/").last,
                  name.hasPrefix("segment"), name.hasSuffix(".m4s"),
                  let sequence = Int(name.dropFirst(7).dropLast(4)) {
            body = segments.first(where: { $0.sequence == sequence })?.data
            contentType = "video/iso.segment"
        } else {
            body = nil
            contentType = "text/plain"
        }

        let status = body == nil ? "404 Not Found" : "200 OK"
        let responseBody = body ?? Data("Not found".utf8)
        let headers = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(responseBody.count)\r\nCache-Control: no-cache, no-store\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n"
        var response = Data(headers.utf8)
        response.append(responseBody)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func playlist() -> String {
        let first = segments.first?.sequence ?? 0
        var text = "#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-TARGETDURATION:1\n#EXT-X-MEDIA-SEQUENCE:\(first)\n#EXT-X-INDEPENDENT-SEGMENTS\n#EXT-X-MAP:URI=\"init.mp4\"\n"
        for segment in segments {
            text += "#EXTINF:1.000,\nsegment\(segment.sequence).m4s\n"
        }
        return text
    }

    private static func wifiIPv4Address() -> String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return nil }
        defer { freeifaddrs(interfaces) }
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let interface = pointer?.pointee {
            defer { pointer = interface.ifa_next }
            guard String(cString: interface.ifa_name) == "en0",
                  interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            var address = interface.ifa_addr.pointee
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(&address, socklen_t(interface.ifa_addr.pointee.sa_len), &buffer,
                                     socklen_t(buffer.count), nil, 0, NI_NUMERICHOST)
            if result == 0 { return String(cString: buffer) }
        }
        return nil
    }
}
