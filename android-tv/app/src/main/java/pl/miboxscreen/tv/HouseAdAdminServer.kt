package pl.miboxscreen.tv

import fi.iki.elonen.NanoHTTPD
import org.json.JSONObject
import java.net.NetworkInterface
import android.util.Base64

class HouseAdAdminServer(
    private val repository: HouseAdRepository,
    port: Int = HouseAdConfig.ADMIN_PORT,
) : NanoHTTPD(port) {

    override fun serve(session: IHTTPSession): Response {
        if (session.method == Method.GET && session.uri == "/api/ads/next") {
            val ad = repository.next()
            val body = if (ad == null) {
                JSONObject().put("available", false)
            } else {
                JSONObject()
                    .put("available", true)
                    .put("id", ad.id)
                    .put("brand", ad.brand)
                    .put("message", ad.message)
            }
            return newFixedLengthResponse(
                Response.Status.OK,
                "application/json; charset=utf-8",
                body.toString()
            )
        }
        if (!authorized(session)) return unauthorized()
        if (session.method == Method.POST) {
            runCatching { session.parseBody(HashMap()) }
            when (session.uri) {
                "/ads/add" -> repository.add(session.parms["brand"].orEmpty(), session.parms["message"].orEmpty())
                "/ads/toggle" -> repository.toggle(session.parms["id"].orEmpty())
                "/ads/delete" -> repository.delete(session.parms["id"].orEmpty())
            }
            return redirectHome()
        }
        return if (session.uri == "/" || session.uri == "/index.html") {
            newFixedLengthResponse(Response.Status.OK, "text/html; charset=utf-8", page())
        } else {
            newFixedLengthResponse(Response.Status.NOT_FOUND, MIME_PLAINTEXT, "Nie znaleziono")
        }
    }

    private fun authorized(session: IHTTPSession): Boolean {
        val header = session.headers["authorization"] ?: return false
        if (!header.startsWith("Basic ", ignoreCase = true)) return false
        val decoded = runCatching { String(Base64.decode(header.substringAfter(' '), Base64.DEFAULT)) }.getOrNull()
        return decoded == "admin:${repository.adminPin}"
    }

    private fun unauthorized() = newFixedLengthResponse(
        Response.Status.UNAUTHORIZED,
        MIME_PLAINTEXT,
        "Podaj uzytkownika admin i kod wyswietlony na Mi Boxie.",
    ).apply { addHeader("WWW-Authenticate", "Basic realm=\"MiBox reklamy\"") }

    private fun redirectHome() = newFixedLengthResponse(Response.Status.REDIRECT, MIME_PLAINTEXT, "Zapisano")
        .apply { addHeader("Location", "/") }

    private fun page(): String {
        val cards = repository.all().joinToString("\n") { ad ->
            val status = if (ad.enabled) "Aktywna" else "Wylaczona"
            val toggle = if (ad.enabled) "Wylacz" else "Wlacz"
            """
            <article class="card ${if (ad.enabled) "" else "off"}">
              <div><strong>${html(ad.brand)}</strong><p>${html(ad.message)}</p><small>$status</small></div>
              <div class="actions">
                <form method="post" action="/ads/toggle"><input type="hidden" name="id" value="${html(ad.id)}"><button>$toggle</button></form>
                <form method="post" action="/ads/delete" onsubmit="return confirm('Usunac reklame?')"><input type="hidden" name="id" value="${html(ad.id)}"><button class="danger">Usun</button></form>
              </div>
            </article>
            """.trimIndent()
        }.ifEmpty { "<p>Brak reklam. Dodaj pierwsza ponizej.</p>" }

        return """
        <!doctype html><html lang="pl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>MiBox - reklamy</title><style>
        :root{color-scheme:dark;font-family:system-ui,sans-serif;background:#07111f;color:#f2f7ff}body{max-width:760px;margin:auto;padding:24px}h1{color:#70e1c8}.hint{color:#aebdce}.card{display:flex;justify-content:space-between;gap:16px;align-items:center;background:#102238;border:1px solid #31506b;border-radius:16px;padding:18px;margin:14px 0}.card.off{opacity:.55}.card p{margin:.35rem 0}.actions{display:flex;gap:8px}form{margin:0}label{display:block;margin:14px 0 6px}input[type=text]{box-sizing:border-box;width:100%;padding:13px;border-radius:10px;border:1px solid #49647c;background:#0c1b2d;color:white}button{border:0;border-radius:9px;padding:10px 14px;background:#70e1c8;color:#07111f;font-weight:700;cursor:pointer}.danger{background:#e98888}.new{margin-top:30px;padding:20px;border:1px solid #31506b;border-radius:16px}small{color:#70e1c8}@media(max-width:550px){.card{align-items:flex-start;flex-direction:column}}
        </style></head><body><h1>MiBox - wlasne reklamy</h1>
        <p class="hint">Aktywne reklamy sa tasowane. Kazda pojawia sie raz w kolejce, bez powtorzenia tej samej reklamy pod rzad.</p>
        $cards
        <form class="new" method="post" action="/ads/add"><h2>Dodaj reklame</h2>
          <label for="brand">Marka / naglowek</label><input id="brand" name="brand" type="text" maxlength="40" required placeholder="RW DESIGN">
          <label for="message">Tresc</label><input id="message" name="message" type="text" maxlength="100" required placeholder="Projektowanie stron i aplikacji">
          <p><button type="submit">Dodaj do rotacji</button></p>
        </form></body></html>
        """.trimIndent()
    }

    private fun html(value: String): String = value
        .replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
        .replace("\"", "&quot;").replace("'", "&#39;")

    companion object {
        fun panelUrl(): String {
            val addresses = NetworkInterface.getNetworkInterfaces().toList()
                .flatMap { it.inetAddresses.toList() }
                .filter { !it.isLoopbackAddress && it.hostAddress?.contains(':') == false }
            val address = (addresses.firstOrNull { it.isSiteLocalAddress } ?: addresses.firstOrNull())
                ?.hostAddress ?: "adres-IP-Mi-Boxa"
            return "http://$address:${HouseAdConfig.ADMIN_PORT}"
        }
    }
}
