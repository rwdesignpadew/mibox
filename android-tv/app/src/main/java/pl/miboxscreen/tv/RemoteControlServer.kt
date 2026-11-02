package pl.miboxscreen.tv

import fi.iki.elonen.NanoHTTPD

class RemoteControlServer(
    private val roomCode: String,
    port: Int = REMOTE_PORT
) : NanoHTTPD(port) {
    override fun serve(session: IHTTPSession): Response {
        if (session.method != Method.POST || session.uri != "/remote") {
            return newFixedLengthResponse(Response.Status.NOT_FOUND, MIME_PLAINTEXT, "Not found")
        }
        if (session.parms["room"] != roomCode) {
            return newFixedLengthResponse(Response.Status.UNAUTHORIZED, MIME_PLAINTEXT, "Invalid room code")
        }
        if (!RemoteAccessibilityService.isEnabled()) {
            return newFixedLengthResponse(
                Response.Status.SERVICE_UNAVAILABLE,
                MIME_PLAINTEXT,
                "Enable MiBox Screen Remote in Android TV accessibility settings"
            )
        }
        val executed = RemoteAccessibilityService.execute(session.parms["command"].orEmpty())
        return if (executed) {
            newFixedLengthResponse(Response.Status.OK, MIME_PLAINTEXT, "OK")
        } else {
            newFixedLengthResponse(Response.Status.BAD_REQUEST, MIME_PLAINTEXT, "Command unavailable")
        }
    }

    companion object {
        const val REMOTE_PORT = 8082
    }
}
