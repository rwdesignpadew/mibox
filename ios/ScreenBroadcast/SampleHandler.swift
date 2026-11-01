import ReplayKit

final class SampleHandler: RPBroadcastSampleHandler {
    private let socket = SignalSocket()
    private var sender: WebRTCSender?

    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        let defaults = SharedSettings.defaults
        guard let urlText = defaults.string(forKey: SharedSettings.serverURLKey),
              let url = URL(string: urlText),
              let roomCode = defaults.string(forKey: SharedSettings.roomCodeKey),
              roomCode.range(of: #"^\d{6}$"#, options: .regularExpression) != nil else {
            finishBroadcastWithError(message: "Otwórz aplikację MiBox Screen i wpisz adres serwera oraz kod z telewizora.")
            return
        }

        let sender = WebRTCSender()
        self.sender = sender
        sender.onSignal = { [weak socket] message in socket?.send(message) }
        sender.onError = { [weak self] message in self?.finishBroadcastWithError(message: message) }
        socket.onOpen = { [weak socket] in
            socket?.send(["type": "join", "role": "sender", "roomCode": roomCode])
        }
        socket.onMessage = { [weak sender] message in
            let type = message["type"] as? String
            if type == "joined" || type == "peer-joined" { sender?.makeOfferIfNeeded() }
            else { sender?.handle(message) }
        }
        socket.onError = { [weak self] error in self?.finishBroadcastWithError(message: error.localizedDescription) }
        socket.connect(url: url)
    }

    override func broadcastFinished() {
        socket.send(["type": "stop"])
        socket.close()
        sender?.stop()
        sender = nil
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        if sampleBufferType == .video { sender?.capture(sampleBuffer) }
    }

    private func finishBroadcastWithError(message: String) {
        finishBroadcastWithError(NSError(
            domain: "pl.miboxscreen.broadcast", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        ))
    }
}
