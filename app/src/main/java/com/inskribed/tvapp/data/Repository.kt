package com.inskribed.tvapp.data

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/** Fetches channel lists and keeps a copy on disk so the app opens instantly. */
class Repository(private val context: Context, private val client: XtreamClient) {

    private fun file(playlistId: String, kind: String) =
        File(context.filesDir, "cache_${playlistId}_$kind.json")

    fun cacheAgeMs(playlistId: String): Long? {
        val f = file(playlistId, "streams")
        return if (f.exists()) System.currentTimeMillis() - f.lastModified() else null
    }

    suspend fun loadCached(p: Playlist): LiveData? = withContext(Dispatchers.Default) {
        runCatching {
            val c = file(p.id, "cats")
            val s = file(p.id, "streams")
            if (!c.exists() || !s.exists()) return@runCatching null
            LiveData(client.parseCategories(c.readText()), client.parseStreams(s.readText(), p.id))
        }.getOrNull()
    }

    suspend fun fetch(p: Playlist): LiveData {
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
    }
}
