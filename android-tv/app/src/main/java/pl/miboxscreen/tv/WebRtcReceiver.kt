package pl.miboxscreen.tv

import android.content.Context
import org.json.JSONObject
import org.webrtc.*

class WebRtcReceiver(
    context: Context,
    private val renderer: SurfaceViewRenderer,
    private val signal: (JSONObject) -> Unit,
    private val state: (String) -> Unit
) {
    private val egl = EglBase.create()
    private val factory: PeerConnectionFactory
    private var peer: PeerConnection? = null
    private val pendingCandidates = mutableListOf<IceCandidate>()
    private var remoteDescriptionReady = false

    init {
        PeerConnectionFactory.initialize(
            PeerConnectionFactory.InitializationOptions.builder(context).createInitializationOptions()
        )
        factory = PeerConnectionFactory.builder()
            .setVideoDecoderFactory(DefaultVideoDecoderFactory(egl.eglBaseContext))
            .setOptions(PeerConnectionFactory.Options())
            .createPeerConnectionFactory()
        renderer.init(egl.eglBaseContext, null)
        renderer.setEnableHardwareScaler(true)
        renderer.setMirror(false)
        createPeer()
    }

    private fun createPeer() {
        peer?.close()
        pendingCandidates.clear()
        remoteDescriptionReady = false
        val config = PeerConnection.RTCConfiguration(
            listOf(PeerConnection.IceServer.builder("stun:stun.l.google.com:19302").createIceServer())
        ).apply { sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN }

        peer = factory.createPeerConnection(config, object : PeerConnection.Observer {
            override fun onIceCandidate(candidate: IceCandidate) {
                signal(JSONObject().apply {
                    put("type", "ice-candidate")
                    put("candidate", candidate.sdp)
                    put("sdpMid", candidate.sdpMid)
                    put("sdpMLineIndex", candidate.sdpMLineIndex)
                })
            }
            override fun onTrack(transceiver: RtpTransceiver) {
                (transceiver.receiver.track() as? VideoTrack)?.addSink(renderer)
            }
            override fun onConnectionChange(newState: PeerConnection.PeerConnectionState) {
                state(newState.name.lowercase().replaceFirstChar(Char::uppercase))
            }
            override fun onSignalingChange(value: PeerConnection.SignalingState) = Unit
            override fun onIceConnectionChange(value: PeerConnection.IceConnectionState) = Unit
            override fun onIceConnectionReceivingChange(value: Boolean) = Unit
            override fun onIceGatheringChange(value: PeerConnection.IceGatheringState) = Unit
            override fun onIceCandidatesRemoved(value: Array<out IceCandidate>) = Unit
            override fun onAddStream(value: MediaStream) = Unit
            override fun onRemoveStream(value: MediaStream) = Unit
            override fun onDataChannel(value: DataChannel) = Unit
            override fun onRenegotiationNeeded() = Unit
            override fun onAddTrack(receiver: RtpReceiver, streams: Array<out MediaStream>) = Unit
        })
    }

    fun handle(message: JSONObject) {
        when (message.optString("type")) {
            "offer" -> acceptOffer(message.getString("sdp"))
            "ice-candidate" -> {
                val candidate = IceCandidate(
                    message.optString("sdpMid"),
                    message.optInt("sdpMLineIndex"),
                    message.getString("candidate")
                )
                if (remoteDescriptionReady) peer?.addIceCandidate(candidate) else pendingCandidates.add(candidate)
            }
            "peer-left", "stop" -> {
                renderer.clearImage()
                createPeer()
                state("Oczekiwanie na iPhone'a")
            }
        }
    }

    private fun acceptOffer(sdp: String) {
        val observer = object : SdpObserver {
            override fun onSetSuccess() {
                remoteDescriptionReady = true
                pendingCandidates.forEach { peer?.addIceCandidate(it) }
                pendingCandidates.clear()
                peer?.createAnswer(object : SdpObserver {
                    override fun onCreateSuccess(answer: SessionDescription) {
                        peer?.setLocalDescription(object : NoopSdpObserver() {
                            override fun onSetSuccess() {
                                signal(JSONObject().put("type", "answer").put("sdp", answer.description))
                            }
                        }, answer)
                    }
                    override fun onCreateFailure(error: String) = state("Błąd odpowiedzi: $error")
                    override fun onSetSuccess() = Unit
                    override fun onSetFailure(error: String) = Unit
                }, MediaConstraints())
            }
            override fun onSetFailure(error: String) = state("Błąd połączenia: $error")
            override fun onCreateSuccess(value: SessionDescription) = Unit
            override fun onCreateFailure(error: String) = Unit
        }
        peer?.setRemoteDescription(observer, SessionDescription(SessionDescription.Type.OFFER, sdp))
    }

    fun release() {
        peer?.close()
        factory.dispose()
        renderer.release()
        egl.release()
    }

    private open class NoopSdpObserver : SdpObserver {
        override fun onCreateSuccess(value: SessionDescription) = Unit
        override fun onSetSuccess() = Unit
        override fun onCreateFailure(error: String) = Unit
        override fun onSetFailure(error: String) = Unit
    }
}
