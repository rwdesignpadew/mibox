import ReplayKit

final class SampleHandler: RPBroadcastSampleHandler {
    private let streamServer = HLSStreamServer()

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        do {
            try streamServer.start()
        } catch {
            finishBroadcastWithError(NSError(
                domain: "pl.miboxscreen.broadcast",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Nie udało się uruchomić transmisji: \(error.localizedDescription)"]
            ))
        }
    }

    override func broadcastFinished() {
        streamServer.stop()
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        switch sampleBufferType {
        case .video:
            streamServer.appendVideo(sampleBuffer)
        case .audioApp:
            streamServer.appendAudio(sampleBuffer)
        default:
            break
        }
    }
}
