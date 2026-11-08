package com.inskribed.tvapp

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import com.inskribed.tvapp.data.AccountInfo
import com.inskribed.tvapp.data.Category
import com.inskribed.tvapp.data.Channel
import com.inskribed.tvapp.data.LiveData
import com.inskribed.tvapp.data.Playlist
import com.inskribed.tvapp.data.Prefs
import com.inskribed.tvapp.data.Repository
import com.inskribed.tvapp.data.XtreamClient
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import okhttp3.OkHttpClient
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.util.UUID
import java.util.concurrent.TimeUnit

enum class Section(val label: String) {
    LIVE("Live TV"),
    FAVORITES("Favorites"),
    SEARCH("Search"),
    SETTINGS("Settings"),
}

const val ALL_CATEGORIES = "__all__"
private const val REFRESH_AFTER_MS = 12 * 60 * 60 * 1000L

class AppViewModel(app: Application) : AndroidViewModel(app) {

    private val prefs = Prefs(app)

    val http: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .followRedirects(true)
        .followSslRedirects(true)
        .retryOnConnectionFailure(true)
        .build()

    private val client = XtreamClient(http)
    private val repo = Repository(app, client)

    // Playlists
    var playlists by mutableStateOf(prefs.playlists())
        private set
    var activeId by mutableStateOf(prefs.activePlaylistId)
        private set
    val active: Playlist? get() = playlists.find { it.id == activeId } ?: playlists.firstOrNull()
    var account by mutableStateOf<AccountInfo?>(null)
        private set
    var showAddPlaylist by mutableStateOf(false)

    // Channels
    var categories by mutableStateOf<List<Category>>(emptyList())
        private set
    var channels by mutableStateOf<List<Channel>>(emptyList())
        private set
    var loading by mutableStateOf(false)
        private set
    var loadError by mutableStateOf<String?>(null)
        private set
    var favorites by mutableStateOf(prefs.favorites())
        private set

    // Navigation
    var section by mutableStateOf(Section.LIVE)
    var selectedCategory by mutableStateOf(ALL_CATEGORIES)
    var searchQuery by mutableStateOf("")

    // Settings
    var streamFormat by mutableStateOf(prefs.streamFormat)
        private set
    var invertKeys by mutableStateOf(prefs.invertChannelKeys)
        private set
    var compact by mutableStateOf(prefs.compactList)
        private set

    /** Text filter for the Live TV channel list. */
    var liveFilter by mutableStateOf("")

    // Playback
    var playQueue by mutableStateOf<List<Channel>>(emptyList())
        private set
    var playIndex by mutableStateOf(-1)
        private set
    val currentChannel: Channel? get() = playQueue.getOrNull(playIndex)

    /** After leaving the player, the list focuses this channel again. */
    var pendingFocusKey by mutableStateOf<String?>(null)

    private var loadJob: Job? = null

    init {
        loadActive()
    }

    fun categoryName(id: String): String? = categories.firstOrNull { it.id == id }?.name

    // ---- Playlists -------------------------------------------------------

    fun addPlaylist(name: String, server: String, username: String, password: String, onResult: (String?) -> Unit) {
        if (server.isBlank() || username.isBlank() || password.isBlank()) {
            onResult("Please fill in the server, username and password.")
            return
        }
        viewModelScope.launch {
            val p = Playlist(
                id = UUID.randomUUID().toString().take(8),
                name = name.trim().ifBlank { "Playlist ${playlists.size + 1}" },
                server = client.normalizeServer(server),
                username = username.trim(),
                password = password.trim(),
            )
            try {
                val info = client.authenticate(p)
                if (!info.ok) {
                    onResult(info.message ?: "Login failed.")
                    return@launch
                }
                playlists = playlists + p
                prefs.savePlaylists(playlists)
                showAddPlaylist = false
                setActive(p.id)
                account = info
                onResult(null)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                onResult("Couldn't connect: ${friendly(e)}")
            }
        }
    }

    fun setActive(id: String) {
        activeId = id
        prefs.activePlaylistId = id
        categories = emptyList()
        channels = emptyList()
        account = null
        selectedCategory = ALL_CATEGORIES
        loadActive()
    }

    fun deletePlaylist(id: String) {
        playlists = playlists.filterNot { it.id == id }
        prefs.savePlaylists(playlists)
        repo.clear(id)
        favorites = favorites.filterNot { it.startsWith("$id:") }
        prefs.saveFavorites(favorites)
        if (activeId == id || playlists.none { it.id == activeId }) {
            val next = playlists.firstOrNull()
            if (next != null) setActive(next.id) else {
                activeId = null
                prefs.activePlaylistId = null
                categories = emptyList()
                channels = emptyList()
                account = null
            }
        }
    }

    // ---- Loading ---------------------------------------------------------

    fun loadActive(force: Boolean = false) {
        val p = active ?: return
        loadJob?.cancel()
        loadJob = viewModelScope.launch {
            loadError = null
            if (!force) repo.loadCached(p)?.let { apply(it) }
            val age = repo.cacheAgeMs(p.id)
            if (force || channels.isEmpty() || age == null || age > REFRESH_AFTER_MS) {
                loading = true
                try {
                    apply(repo.fetch(p))
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    if (channels.isEmpty()) loadError = friendly(e)
                } finally {
                    loading = false
                }
            }
            try {
                account = client.authenticate(p)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
            }
        }
    }

    private fun apply(data: LiveData) {
        categories = data.categories
        channels = data.channels
    }

    private fun friendly(e: Exception): String = when (e) {
        is UnknownHostException -> "Can't find that server. Check the address."
        is SocketTimeoutException -> "The server took too long to respond."
        else -> e.message ?: "Something went wrong."
    }

    // ---- Favorites -------------------------------------------------------

    fun isFavorite(ch: Channel) = ch.key in favorites

    fun toggleFavorite(ch: Channel) {
        favorites = if (ch.key in favorites) favorites - ch.key else favorites + ch.key
        prefs.saveFavorites(favorites)
    }

    fun favoriteChannels(): List<Channel> {
        val byKey = channels.associateBy { it.key }
        return favorites.mapNotNull { byKey[it] }
    }

    // ---- Search ----------------------------------------------------------

    fun search(query: String): List<Channel> {
        val q = normalize(query)
        if (q.isEmpty()) return emptyList()
        val starts = ArrayList<Channel>()
        val contains = ArrayList<Channel>()
        for (ch in channels) {
            val n = normalize(ch.name)
            when {
                n.startsWith(q) -> starts += ch
                n.contains(q) -> contains += ch
            }
            if (starts.size >= 300) break
        }
        return (starts + contains).take(300)
    }

    private fun normalize(s: String) = buildString(s.length) {
        for (c in s) if (c.isLetterOrDigit()) append(c.lowercaseChar())
    }

    // ---- Settings --------------------------------------------------------

    fun updateStreamFormat(format: String) {
        streamFormat = format
        prefs.streamFormat = format
    }

    fun updateCompact(value: Boolean) {
        compact = value
        prefs.compactList = value
    }

    fun filterChannels(list: List<Channel>, filter: String): List<Channel> {
        val words = filter.trim().split(' ').map { normalize(it) }.filter { it.isNotEmpty() }
        if (words.isEmpty()) return list
        return list.filter { ch ->
            val n = normalize(ch.name)
            words.all { n.contains(it) }
        }
    }

    fun updateInvertKeys(value: Boolean) {
        invertKeys = value
        prefs.invertChannelKeys = value
    }

    // ---- Playback --------------------------------------------------------

    fun play(queue: List<Channel>, index: Int) {
        playQueue = queue
        playIndex = index
    }

    fun zap(delta: Int) {
        if (playQueue.isEmpty()) return
        playIndex = (playIndex + delta).mod(playQueue.size)
    }

    fun stopPlayback() {
        pendingFocusKey = currentChannel?.key
        playQueue = emptyList()
        playIndex = -1
    }

    fun mediaItem(ch: Channel): MediaItem? {
        val p = playlists.find { it.id == ch.playlistId } ?: return null
        val url = client.streamUrl(p, ch, streamFormat)
        return MediaItem.Builder()
            .setUri(url)
            .setMimeType(if (streamFormat == "m3u8") MimeTypes.APPLICATION_M3U8 else MimeTypes.VIDEO_MP2T)
            .build()
    }
}
