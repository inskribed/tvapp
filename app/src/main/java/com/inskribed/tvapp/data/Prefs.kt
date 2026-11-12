package com.inskribed.tvapp.data

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/** Small settings store. Everything stays on the device. */
class Prefs(context: Context) {
    private val sp = context.getSharedPreferences("tvapp", Context.MODE_PRIVATE)

    fun playlists(): List<Playlist> {
        val raw = sp.getString(KEY_PLAYLISTS, null) ?: return emptyList()
        return runCatching {
            val arr = JSONArray(raw)
            (0 until arr.length()).mapNotNull { i ->
                val o = arr.optJSONObject(i) ?: return@mapNotNull null
                Playlist(
                    id = o.getString("id"),
                    name = o.optString("name"),
                    server = o.getString("server"),
                    username = o.getString("username"),
                    password = o.getString("password"),
                )
            }
        }.getOrDefault(emptyList())
    }

    fun savePlaylists(list: List<Playlist>) {
        val arr = JSONArray()
        list.forEach { p ->
            arr.put(
                JSONObject()
                    .put("id", p.id)
                    .put("name", p.name)
                    .put("server", p.server)
                    .put("username", p.username)
                    .put("password", p.password)
            )
        }
        sp.edit().putString(KEY_PLAYLISTS, arr.toString()).apply()
    }

    var activePlaylistId: String?
        get() = sp.getString(KEY_ACTIVE, null)
        set(v) = sp.edit().putString(KEY_ACTIVE, v).apply()

    /** Favorite channel keys, in the order they were added. */
    fun favorites(): List<String> {
        val raw = sp.getString(KEY_FAVORITES, null) ?: return emptyList()
        return runCatching {
            val arr = JSONArray(raw)
            (0 until arr.length()).map { arr.getString(it) }
        }.getOrDefault(emptyList())
    }

    fun saveFavorites(keys: List<String>) {
        val arr = JSONArray()
        keys.forEach { arr.put(it) }
        sp.edit().putString(KEY_FAVORITES, arr.toString()).apply()
    }

    /** "ts" or "m3u8" */
    var streamFormat: String
        get() = sp.getString(KEY_FORMAT, "ts") ?: "ts"
        set(v) = sp.edit().putString(KEY_FORMAT, v).apply()

    var invertChannelKeys: Boolean
        get() = sp.getBoolean(KEY_INVERT, false)
        set(v) = sp.edit().putBoolean(KEY_INVERT, v).apply()

    var compactList: Boolean
        get() = sp.getBoolean(KEY_COMPACT, false)
        set(v) = sp.edit().putBoolean(KEY_COMPACT, v).apply()

    /** ARGB; 0 = not chosen yet. */
    var accentColor: Int
        get() = sp.getInt(KEY_ACCENT, 0)
        set(v) = sp.edit().putInt(KEY_ACCENT, v).apply()

    var showScores: Boolean
        get() = sp.getBoolean(KEY_SCORES, true)
        set(v) = sp.edit().putBoolean(KEY_SCORES, v).apply()

    fun favoriteTeams(): List<String> {
        val raw = sp.getString(KEY_TEAMS, null) ?: return emptyList()
        return runCatching {
            val arr = JSONArray(raw)
            (0 until arr.length()).map { arr.getString(it) }
        }.getOrDefault(emptyList())
    }

    fun saveFavoriteTeams(keys: List<String>) {
        val arr = JSONArray()
        keys.forEach { arr.put(it) }
        sp.edit().putString(KEY_TEAMS, arr.toString()).apply()
    }

    private companion object {
        const val KEY_SCORES = "show_scores"
        const val KEY_ACCENT = "accent_color"
        const val KEY_TEAMS = "favorite_teams"
        const val KEY_COMPACT = "compact_list"
        const val KEY_PLAYLISTS = "playlists"
        const val KEY_ACTIVE = "active_playlist"
        const val KEY_FAVORITES = "favorites"
        const val KEY_FORMAT = "stream_format"
        const val KEY_INVERT = "invert_channel_keys"
    }
}
