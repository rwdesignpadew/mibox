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

class MainActivity : AppCompatActivity(), SignalClient.Listener {
    private lateinit var renderer: SurfaceViewRenderer
    private lateinit var overlay: LinearLayout
    private lateinit var codeView: TextView
    private lateinit var statusView: TextView
    private lateinit var signalClient: SignalClient
    private lateinit var receiver: WebRtcReceiver

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_FULLSCREEN or
            View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY

        renderer = SurfaceViewRenderer(this)
        codeView = textView(72f, "------")
        statusView = textView(22f, "Łączenie z serwerem…")
        overlay = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(48, 48, 48, 48)
            setBackgroundColor(0xDD07111F.toInt())
            addView(textView(28f, "MiBox Screen"))
            addView(textView(20f, "Wpisz ten kod na iPhonie"))
            addView(codeView)
            addView(statusView)
        }
        setContentView(FrameLayout(this).apply {
            addView(renderer, FrameLayout.LayoutParams(-1, -1))
            addView(this@MainActivity.overlay, FrameLayout.LayoutParams(-1, -1))
        })

        signalClient = SignalClient(BuildConfig.SIGNALING_URL, this)
        receiver = WebRtcReceiver(this, renderer, signalClient::send) {
            status -> runOnUiThread { updateStatus(status) }
        }
        signalClient.connect()
    }

    private fun textView(size: Float, value: String) = TextView(this).apply {
        text = value
        textSize = size
        setTextColor(0xFFF2F7FF.toInt())
        gravity = Gravity.CENTER
        setPadding(8, 12, 8, 12)
    }

    override fun onConnected() = runOnUiThread {
        updateStatus("Pobieranie kodu…")
        signalClient.send(JSONObject().put("type", "join").put("role", "receiver"))
    }

    override fun onMessage(message: JSONObject) = runOnUiThread {
        when (message.optString("type")) {
            "joined" -> {
                codeView.text = message.getString("roomCode")
                updateStatus("Oczekiwanie na iPhone'a")
            }
            "peer-joined" -> updateStatus("iPhone połączony — uruchom transmisję")
            "error" -> updateStatus(message.optString("message", "Błąd serwera"))
            else -> receiver.handle(message)
        }
    }

    override fun onDisconnected(reason: String) = runOnUiThread { updateStatus("Rozłączono: $reason") }

    private fun updateStatus(value: String) {
        statusView.text = value
        overlay.visibility = if (value.equals("Connected", ignoreCase = true)) View.GONE else View.VISIBLE
    }

    override fun onDestroy() {
        signalClient.close()
        receiver.release()
        super.onDestroy()
    }
}
