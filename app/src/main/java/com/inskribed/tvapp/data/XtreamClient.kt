package com.inskribed.tvapp.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException

const val USER_AGENT = "Remo/0.1 (Linux; Android)"

/** Talks to an Xtream Codes compatible server (player_api.php). */
class XtreamClient(private val http: OkHttpClient) {

    fun normalizeServer(raw: String): String {
        var s = raw.trim()
        if (!s.startsWith("http://", ignoreCase = true) && !s.startsWith("https://", ignoreCase = true)) {
            s = "http://$s"
        }
        s = s.substringBefore("/player_api.php").substringBefore("/get.php").trimEnd('/')
        return s
    }

    private fun apiUrl(p: Playlist, action: String?): HttpUrl {
        val base = "${p.server}/player_api.php".toHttpUrlOrNull()
            ?: throw IOException("The server address doesn't look right")
        return base.newBuilder()
            .addQueryParameter("username", p.username)
            .addQueryParameter("password", p.password)
            .apply { if (action != null) addQueryParameter("action", action) }
            .build()
    }

    private suspend fun get(url: HttpUrl): String = withContext(Dispatchers.IO) {
        val req = Request.Builder().url(url).header("User-Agent", USER_AGENT).build()
        http.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) throw IOException("Server returned HTTP ${resp.code}")
            resp.body?.string() ?: throw IOException("Empty response from server")
        }
    }

    suspend fun authenticate(p: Playlist): AccountInfo {
        val body = get(apiUrl(p, null))
        val root = runCatching { JSONObject(body) }.getOrNull()
            ?: throw IOException("That address didn't respond like an Xtream server")
        val user = root.optJSONObject("user_info")
            ?: return AccountInfo(false, null, null, null, null, "Login failed. Check username and password.")
        val ok = user.str("auth") == "1"
        return AccountInfo(
            ok = ok,
            status = user.str("status"),
            expiresAtSec = user.str("exp_date")?.toLongOrNull(),
            maxConnections = user.str("max_connections")?.toIntOrNull(),
            activeConnections = user.str("active_cons")?.toIntOrNull(),
            message = if (ok) null else (user.str("message") ?: "Login failed. Check username and password."),
        )
    }

    suspend fun rawLiveCategories(p: Playlist): String = get(apiUrl(p, "get_live_categories"))
    suspend fun rawLiveStreams(p: Playlist): String = get(apiUrl(p, "get_live_streams"))

    fun parseCategories(raw: String): List<Category> {
        val arr = JSONArray(raw)
        val out = ArrayList<Category>(arr.length())
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            val id = o.str("category_id") ?: continue
            out += Category(id, o.str("category_name") ?: "Category $id")
        }
        return out
    }

    fun parseStreams(raw: String, playlistId: String): List<Channel> {
        val arr = JSONArray(raw)
        val out = ArrayList<Channel>(arr.length())
        val seen = HashSet<String>()
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            val id = o.str("stream_id") ?: continue
            if (!seen.add(id)) continue
            out += Channel(
                playlistId = playlistId,
                streamId = id,
                num = o.str("num")?.toIntOrNull() ?: (i + 1),
                name = o.str("name") ?: "Channel $id",
                logo = o.str("stream_icon")?.takeIf { it.startsWith("http") },
                categoryId = o.str("category_id") ?: "",
                epgId = o.str("epg_channel_id"),
            )
        }
        return out
    }

    fun streamUrl(p: Playlist, ch: Channel, format: String): String {
        val ext = if (format == "m3u8") "m3u8" else "ts"
        val base = p.server.toHttpUrlOrNull() ?: return "${p.server}/live/${p.username}/${p.password}/${ch.streamId}.$ext"
        return base.newBuilder()
            .addPathSegment("live")
            .addPathSegment(p.username)
            .addPathSegment(p.password)
            .addPathSegment("${ch.streamId}.$ext")
            .build()
            .toString()
    }
}

/** Reads a field as a trimmed string, whether the server sent it as text or a number. */
internal fun JSONObject.str(name: String): String? {
    if (isNull(name)) return null
    return optString(name).trim().takeIf { it.isNotEmpty() && it != "null" }
}
