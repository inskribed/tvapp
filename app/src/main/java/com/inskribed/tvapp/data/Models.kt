package com.inskribed.tvapp.data

data class Playlist(
    val id: String,
    val name: String,
    val server: String,
    val username: String,
    val password: String,
)

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
) {
    /** Unique across all playlists. */
    val key: String get() = "$playlistId:$streamId"
}

data class LiveData(
    val categories: List<Category>,
    val channels: List<Channel>,
)

data class AccountInfo(
    val ok: Boolean,
    val status: String?,
    val expiresAtSec: Long?,
    val maxConnections: Int?,
    val activeConnections: Int?,
    val message: String?,
)
