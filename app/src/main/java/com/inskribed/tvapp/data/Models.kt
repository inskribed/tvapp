package com.inskribed.tvapp.data

data class Playlist(
    val id: String,
    val name: String,
    /** Xtream server address, or the playlist link for M3U playlists. */
    val server: String,
    val username: String,
    val password: String,
    /** "xtream" or "m3u" (legal sources such as Free-TV, iptv-org, HDHomeRun, Plex). */
    val kind: String = KIND_XTREAM,
    /** Optional guide (XMLTV) link for M3U playlists. */
    val epgUrl: String? = null,
) {
    val isM3u: Boolean get() = kind == KIND_M3U

    companion object {
        const val KIND_XTREAM = "xtream"
        const val KIND_M3U = "m3u"
    }
}

data class Category(
    val id: String,
    val name: String,
)

data class Channel(
    val playlistId: String,
    val streamId: String,
    val num: Int,
    val name: String,
    val logo: String?,
    val categoryId: String,
    val epgId: String?,
    /** M3U channels carry their own stream address, and sometimes connection details. */
    val url: String? = null,
    val userAgent: String? = null,
    val referrer: String? = null,
) {
    /** Unique across all playlists. */
    val key: String get() = "$playlistId:$streamId"
}

data class LiveData(
    val categories: List<Category>,
    val channels: List<Channel>,
    /** Guide (XMLTV) links an M3U playlist names in its header. */
    val guideUrls: List<String> = emptyList(),
)

data class AccountInfo(
    val ok: Boolean,
    val status: String?,
    val expiresAtSec: Long?,
    val maxConnections: Int?,
    val activeConnections: Int?,
    val message: String?,
)

/** One TV guide entry. Times are epoch milliseconds. */
data class Program(
    val title: String,
    val description: String?,
    val startMs: Long,
    val endMs: Long,
)
