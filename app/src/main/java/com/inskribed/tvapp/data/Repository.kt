package com.inskribed.tvapp.data

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/** Fetches channel lists and keeps a copy on disk so the app opens instantly. */
class Repository(private val context: Context, private val client: XtreamClient) {

    private fun file(playlistId: String, kind: String) =
        File(context.filesDir, "cache_${playlistId}_$kind.json")

    fun cacheAgeMs(p: Playlist): Long? {
        val f = file(p.id, if (p.isM3u) "m3u" else "streams")
        return if (f.exists()) System.currentTimeMillis() - f.lastModified() else null
    }

    suspend fun loadCached(p: Playlist): LiveData? = withContext(Dispatchers.Default) {
        runCatching {
            if (p.isM3u) {
                val m = file(p.id, "m3u")
                return@runCatching if (m.exists()) M3uParser.parse(m.readText(), p.id).data else null
            }
            val c = file(p.id, "cats")
            val s = file(p.id, "streams")
            if (!c.exists() || !s.exists()) return@runCatching null
            LiveData(client.parseCategories(c.readText()), client.parseStreams(s.readText(), p.id))
        }.getOrNull()
    }

    /** Downloads an M3U playlist, checks it, and saves it for instant starts. */
    suspend fun fetchM3u(p: Playlist): M3uParser.Result {
        val text = client.fetchText(p.server)
        if (!text.contains("#EXTINF")) throw java.io.IOException("That link didn't return an M3U playlist")
        val result = withContext(Dispatchers.Default) { M3uParser.parse(text, p.id) }
        withContext(Dispatchers.IO) { file(p.id, "m3u").writeText(text) }
        return result
    }

    suspend fun fetch(p: Playlist): LiveData {
        if (p.isM3u) return fetchM3u(p).data
        val rawCats = client.rawLiveCategories(p)
        val rawStreams = client.rawLiveStreams(p)
        val data = withContext(Dispatchers.Default) {
            LiveData(client.parseCategories(rawCats), client.parseStreams(rawStreams, p.id))
        }
        withContext(Dispatchers.IO) {
            file(p.id, "cats").writeText(rawCats)
            file(p.id, "streams").writeText(rawStreams)
        }
        return data
    }

    fun clear(playlistId: String) {
        file(playlistId, "cats").delete()
        file(playlistId, "streams").delete()
        file(playlistId, "m3u").delete()
    }
}
