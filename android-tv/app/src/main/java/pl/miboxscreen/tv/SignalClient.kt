package pl.miboxscreen.tv

import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject
import java.util.concurrent.TimeUnit

class SignalClient(
    private val serverUrl: String,
    private val listener: Listener
) : WebSocketListener() {
    interface Listener {
        fun onConnected()
        fun onMessage(message: JSONObject)
        fun onDisconnected(reason: String)
    }

    private val client = OkHttpClient.Builder()
        .pingInterval(15, TimeUnit.SECONDS)
        .build()
    private var socket: WebSocket? = null

    fun connect() {
        socket = client.newWebSocket(Request.Builder().url(serverUrl).build(), this)
    }

    fun send(message: JSONObject) {
        socket?.send(message.toString())
    }

    fun close() {
        socket?.close(1000, "TV app closed")
        client.dispatcher.executorService.shutdown()
    }

    override fun onOpen(webSocket: WebSocket, response: Response) = listener.onConnected()
    override fun onMessage(webSocket: WebSocket, text: String) {
        runCatching { JSONObject(text) }.onSuccess(listener::onMessage)
    }
    override fun onClosed(webSocket: WebSocket, code: Int, reason: String) = listener.onDisconnected(reason)
    override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) =
        listener.onDisconnected(t.message ?: "Connection failed")
}

