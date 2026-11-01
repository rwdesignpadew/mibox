import CoreMedia
import Foundation
import ImageIO
import ReplayKit
import WebRTC

final class WebRTCSender: NSObject {
    var onSignal: (([String: Any]) -> Void)?
    var onError: ((String) -> Void)?

    private let factory: RTCPeerConnectionFactory
    private let videoSource: RTCVideoSource
    private let capturer: RTCVideoCapturer
    private var peer: RTCPeerConnection!
    private var offerCreated = false
    private var remoteDescriptionReady = false
    private var pendingCandidates: [RTCIceCandidate] = []

    override init() {
        RTCInitializeSSL()
        let encoder = RTCDefaultVideoEncoderFactory()
        let decoder = RTCDefaultVideoDecoderFactory()
        factory = RTCPeerConnectionFactory(encoderFactory: encoder, decoderFactory: decoder)
        videoSource = factory.videoSource()
        capturer = RTCVideoCapturer(delegate: videoSource)
        super.init()
        createPeer()
    }

    private func createPeer() {
        let config = RTCConfiguration()
        config.sdpSemantics = .unifiedPlan
        config.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        peer = factory.peerConnection(with: config, constraints: constraints, delegate: self)
        let track = factory.videoTrack(with: videoSource, trackId: "screen-video")
        peer.add(track, streamIds: ["screen"])
    }

    func makeOfferIfNeeded() {
        guard !offerCreated else { return }
        offerCreated = true
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: ["OfferToReceiveAudio": "false", "OfferToReceiveVideo": "false"],
            optionalConstraints: nil
        )
        peer.offer(for: constraints) { [weak self] sdp, error in
            guard let self, let sdp else {
                self?.onError?(error?.localizedDescription ?? "Nie udało się utworzyć oferty")
                return
            }
            self.peer.setLocalDescription(sdp) { error in
                if let error { self.onError?(error.localizedDescription); return }
                self.onSignal?(["type": "offer", "sdp": sdp.sdp])
            }
        }
    }

    func handle(_ message: [String: Any]) {
        switch message["type"] as? String {
        case "answer":
            guard let sdp = message["sdp"] as? String else { return }
            peer.setRemoteDescription(RTCSessionDescription(type: .answer, sdp: sdp)) { [weak self] error in
                guard let self else { return }
                if let error { self.onError?(error.localizedDescription); return }
                self.remoteDescriptionReady = true
                self.pendingCandidates.forEach { self.peer.add($0) }
                self.pendingCandidates.removeAll()
            }
        case "ice-candidate":
            guard let candidate = message["candidate"] as? String,
                  let lineNumber = message["sdpMLineIndex"] as? NSNumber else { return }
            let iceCandidate = RTCIceCandidate(
                sdp: candidate,
                sdpMLineIndex: lineNumber.int32Value,
                sdpMid: message["sdpMid"] as? String
            )
            if remoteDescriptionReady { peer.add(iceCandidate) }
            else { pendingCandidates.append(iceCandidate) }
        default: break
        }
    }

    func capture(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = Int64(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * 1_000_000_000)
        let rotation = Self.rotation(for: sampleBuffer)
        let buffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
        videoSource.capturer(capturer, didCapture: RTCVideoFrame(buffer: buffer, rotation: rotation, timeStampNs: timestamp))
    }

    private static func rotation(for sample: CMSampleBuffer) -> RTCVideoRotation {
        guard let value = CMGetAttachment(sample, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil) as? NSNumber,
              let orientation = CGImagePropertyOrientation(rawValue: value.uint32Value) else { return ._0 }
        switch orientation {
        case .right: return ._90
        case .down: return ._180
        case .left: return ._270
        default: return ._0
        }
    }

    func stop() {
        peer.close()
        RTCCleanupSSL()
    }
}

extension WebRTCSender: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        onSignal?([
            "type": "ice-candidate", "candidate": candidate.sdp,
            "sdpMid": candidate.sdpMid ?? "0", "sdpMLineIndex": candidate.sdpMLineIndex
        ])
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didStartReceivingOn transceiver: RTCRtpTransceiver) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams: [RTCMediaStream]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {}
}
