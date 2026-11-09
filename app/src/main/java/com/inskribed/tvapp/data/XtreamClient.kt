package com.inskribed.tvapp.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import android.util.Base64
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.text.SimpleDateFormat
import java.util.Locale

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

    /** Guide entries for one channel, from now on. */
    suspend fun shortEpg(p: Playlist, streamId: String, limit: Int = 24): List<Program> {
        val url = apiUrl(p, "get_short_epg").newBuilder()
            .addQueryParameter("stream_id", streamId)
            .addQueryParameter("limit", limit.toString())
            .build()
        return parseEpg(get(url))
    }

    fun parseEpg(raw: String): List<Program> {
        // Servers with no data sometimes answer with [] instead of an object.
        val root = runCatching { JSONObject(raw) }.getOrNull() ?: return emptyList()
        val arr = root.optJSONArray("epg_listings") ?: return emptyList()
        val out = ArrayList<Program>(arr.length())
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            val start = o.str("start_timestamp")?.toLongOrNull()?.times(1000) ?: parseTime(o.str("start")) ?: continue
            val end = (o.str("stop_timestamp") ?: o.str("end_timestamp"))?.toLongOrNull()?.times(1000)
                ?: parseTime(o.str("end") ?: o.str("stop")) ?: continue
            if (end <= start) continue
            out += Program(
                title = decode(o.str("title")) ?: "Untitled",
                description = decode(o.str("description")),
                startMs = start,
                endMs = end,
            )
        }
        out.sortBy { it.startMs }
        // Drop overlapping duplicates so the guide grid lines up.
        val clean = ArrayList<Program>(out.size)
        for (prog in out) {
            val last = clean.lastOrNull()
            if (last != null && prog.startMs < last.endMs) continue
            clean += prog
        }
        return clean
    }

    /** Xtream sends guide text base64-encoded. Falls back to the raw text if it isn't. */
    private fun decode(s: String?): String? {
        if (s.isNullOrBlank()) return null
        val decoded = runCatching { String(Base64.decode(s, Base64.DEFAULT), Charsets.UTF_8) }.getOrNull()
        val text = if (decoded == null || decoded.contains('\uFFFD')) s else decoded
        return text.trim().takeIf { it.isNotEmpty() }
    }

    private fun parseTime(s: String?): Long? {
        if (s == null) return null
        return runCatching { SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).parse(s)?.time }.getOrNull()
    }

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
