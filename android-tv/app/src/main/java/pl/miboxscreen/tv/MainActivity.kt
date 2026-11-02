package pl.miboxscreen.tv

import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import org.json.JSONObject
import org.webrtc.SurfaceViewRenderer
import java.security.SecureRandom

class MainActivity : AppCompatActivity(), LocalSignalServer.Listener {
    private lateinit var renderer: SurfaceViewRenderer
    private lateinit var overlay: LinearLayout
    private lateinit var codeView: TextView
    private lateinit var statusView: TextView
    private lateinit var houseAdBanner: HouseAdBanner
    private lateinit var adAdminServer: HouseAdAdminServer
    private lateinit var signalServer: LocalSignalServer
    private lateinit var serviceAdvertiser: ReceiverServiceAdvertiser
    private lateinit var receiver: WebRtcReceiver
    private var proSession = false
    private val roomCode = SecureRandom().nextInt(1_000_000).toString().padStart(6, '0')

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_FULLSCREEN or
            View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY

        renderer = SurfaceViewRenderer(this)
        codeView = textView(72f, roomCode)
        statusView = textView(22f, "Oczekiwanie na iPhone'a")
        val adRepository = HouseAdRepository(this)
        houseAdBanner = HouseAdBanner(this, adRepository)
        overlay = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(48, 48, 48, 48)
            setBackgroundColor(0xDD07111F.toInt())
            addView(textView(28f, "MiBox Screen"))
            addView(textView(20f, "Wpisz ten kod na iPhonie"))
            addView(codeView)
            addView(statusView)
            addView(textView(16f, "Panel reklam: ${HouseAdAdminServer.panelUrl()}\nLogin: admin   Kod: ${adRepository.adminPin}"))
        }
        setContentView(FrameLayout(this).apply {
            addView(renderer, FrameLayout.LayoutParams(-1, -1))
            addView(this@MainActivity.overlay, FrameLayout.LayoutParams(-1, -1))
            addView(houseAdBanner, FrameLayout.LayoutParams(-2, -2, Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL).apply {
                setMargins(48, 48, 48, 48)
            })
        })

        signalServer = LocalSignalServer(SIGNAL_PORT, roomCode, this)
        receiver = WebRtcReceiver(this, renderer, signalServer::sendSignal) {
            status -> runOnUiThread { updateStatus(status) }
        }
        signalServer.start()
        adAdminServer = HouseAdAdminServer(adRepository)
        runCatching { adAdminServer.start() }
        serviceAdvertiser = ReceiverServiceAdvertiser(this, SIGNAL_PORT, roomCode)
        serviceAdvertiser.start()
    }

    private fun textView(size: Float, value: String) = TextView(this).apply {
        text = value
        textSize = size
        setTextColor(0xFFF2F7FF.toInt())
        gravity = Gravity.CENTER
        setPadding(8, 12, 8, 12)
    }

    override fun onSenderJoined(isPro: Boolean) = runOnUiThread {
        proSession = isPro
        updateStatus("iPhone połączony — uruchamianie transmisji")
    }

    override fun onSenderLeft() = runOnUiThread {
        proSession = false
        receiver.handle(JSONObject().put("type", "peer-left"))
    }

    override fun onSignal(message: JSONObject) = runOnUiThread { receiver.handle(message) }
    override fun onServerError(message: String) = runOnUiThread { updateStatus("Błąd: $message") }

    private fun updateStatus(value: String) {
        statusView.text = value
        val connected = value.equals("Connected", ignoreCase = true)
        overlay.visibility = if (connected) View.GONE else View.VISIBLE
        if (connected && !proSession) houseAdBanner.start() else houseAdBanner.stop()
    }

    override fun onDestroy() {
        houseAdBanner.stop()
        adAdminServer.stop()
        serviceAdvertiser.stop()
        runCatching { signalServer.stop(1_000) }
        receiver.release()
        super.onDestroy()
    }

    companion object {
        private const val SIGNAL_PORT = 8080
    }
}
