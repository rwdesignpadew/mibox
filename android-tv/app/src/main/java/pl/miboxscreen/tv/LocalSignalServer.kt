package pl.miboxscreen.tv

import org.java_websocket.WebSocket
import org.java_websocket.handshake.ClientHandshake
import org.java_websocket.server.WebSocketServer
import org.json.JSONObject
import java.net.InetSocketAddress

class LocalSignalServer(
    port: Int,
    private val roomCode: String,
    private val listener: Listener
) : WebSocketServer(InetSocketAddress(port)) {
    interface Listener {
        fun onSenderJoined(isPro: Boolean)
        fun onSenderLeft()
        fun onSignal(message: JSONObject)
        fun onPlaybackCommand(message: JSONObject)
        fun onServerError(message: String)
    }

    @Volatile
    private var sender: WebSocket? = null

    override fun onOpen(connection: WebSocket, handshake: ClientHandshake) {
        if (handshake.resourceDescriptor != "/signal") {
            connection.close(1008, "Use /signal")
        }
    }

    override fun onMessage(connection: WebSocket, text: String) {
        val message = runCatching { JSONObject(text) }.getOrElse {
            send(connection, JSONObject().put("type", "error").put("message", "Invalid JSON"))
            return
        }

        if (message.optString("type") == "join") {
            join(connection, message)
            return
        }

        if (connection != sender) {
            send(connection, JSONObject().put("type", "error").put("message", "Join first"))
            return
        }

        if (message.optString("type") in setOf("offer", "ice-candidate")) {
            listener.onSignal(message)
        } else if (message.optString("type") in setOf("play", "pause", "resume", "stop", "seek")) {
            listener.onPlaybackCommand(message)
        } else {
            send(connection, JSONObject().put("type", "error").put("message", "Unsupported message"))
        }
    }

    private fun join(connection: WebSocket, message: JSONObject) {
        val suppliedRoom = message.optString("roomCode")
        if (message.optString("role") != "sender" || (suppliedRoom.isNotEmpty() && suppliedRoom != roomCode)) {
            send(connection, JSONObject().put("type", "error").put("message", "Nieprawidłowy kod telewizora"))
            connection.close(1008, "Invalid room code")
            return
        }

        synchronized(this) {
            sender?.takeIf { it != connection }?.close(1008, "Another iPhone connected")
            sender = connection
        }
        send(connection, JSONObject().apply {
            put("type", "joined")
            put("role", "sender")
            put("roomCode", roomCode)
            put("peerPresent", true)
        })
        send(connection, JSONObject().put("type", "peer-joined").put("role", "receiver"))
        listener.onSenderJoined(message.optBoolean("isPro", false))
    }

    fun sendSignal(message: JSONObject) {
        sender?.takeIf { it.isOpen }?.let { send(it, message) }
    }

    fun sendPlaybackStatus(state: String, error: String? = null) {
        val message = JSONObject().put("type", "playback-status").put("state", state)
        if (error != null) message.put("error", error)
        sender?.takeIf { it.isOpen }?.let { send(it, message) }
    }

    private fun send(connection: WebSocket, message: JSONObject) {
        if (connection.isOpen) connection.send(message.toString())
    }

    override fun onClose(connection: WebSocket, code: Int, reason: String, remote: Boolean) {
        synchronized(this) {
            if (sender == connection) {
                sender = null
                listener.onSenderLeft()
            }
        }
    }

    override fun onError(connection: WebSocket?, error: Exception) {
        listener.onServerError(error.message ?: "Błąd lokalnego serwera")
    }

    override fun onStart() {
        connectionLostTimeout = 20
    }
}
