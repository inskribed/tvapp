package com.inskribed.tvapp

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.lifecycle.AndroidViewModel
import com.inskribed.tvapp.ui.AppColors
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
import com.inskribed.tvapp.data.ChannelMatcher
import com.inskribed.tvapp.data.Game
import com.inskribed.tvapp.data.GameState
import com.inskribed.tvapp.data.League
import com.inskribed.tvapp.data.SportsClient
import com.inskribed.tvapp.data.Team
import com.inskribed.tvapp.data.Program
import com.inskribed.tvapp.data.UpdateInfo
import com.inskribed.tvapp.data.Updater
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import okhttp3.OkHttpClient
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.util.UUID
import java.util.concurrent.TimeUnit

enum class Section(val label: String) {
    GUIDE("TV Guide"),
    SPORTS("Sports"),
    FAVORITES("Favorites"),
    SEARCH("Search"),
    SETTINGS("Settings"),
}

const val ALL_CATEGORIES = "__all__"
const val FAVORITES_CATEGORY = "__fav__"
private const val EPG_FRESH_MS = 30 * 60 * 1000L
private const val EPG_RETRY_MS = 5 * 60 * 1000L
private const val EPG_MAX_CHANNELS = 800

/** Guide data for one channel. */
class EpgEntry(val programs: List<Program>, val fetchedMs: Long, val failed: Boolean)
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
    var section by mutableStateOf(Section.GUIDE)
    var searchQuery by mutableStateOf("")

    // Settings
    var streamFormat by mutableStateOf(prefs.streamFormat)
        private set
    var invertKeys by mutableStateOf(prefs.invertChannelKeys)
        private set
    var compact by mutableStateOf(prefs.compactList)
        private set

    /** TV Guide shows a simple channel list (with what's on now) instead of the time grid. */
    var guideList by mutableStateOf(prefs.guideListView)
        private set

    // Playback
    var playQueue by mutableStateOf<List<Channel>>(emptyList())
        private set
    var playIndex by mutableStateOf(-1)
        private set
    val currentChannel: Channel? get() = playQueue.getOrNull(playIndex)
    /** True while the player is shrunk to a small window so you can browse. */
    var playerMini by mutableStateOf(false)
        private set

    // Sports
    private val sports = SportsClient(http)
    var games by mutableStateOf<Map<League, List<Game>>>(emptyMap())
        private set
    var sportsLoading by mutableStateOf(false)
        private set
    var sportsError by mutableStateOf<String?>(null)
        private set
    var sportsUpdatedMs by mutableStateOf(0L)
        private set
    var favoriteTeams by mutableStateOf(prefs.favoriteTeams())
        private set
    var showScores by mutableStateOf(prefs.showScores)
        private set
    var teams by mutableStateOf<Map<League, List<Team>>>(emptyMap())
        private set
    var teamsError by mutableStateOf<String?>(null)
        private set
    var gameDetail by mutableStateOf<Game?>(null)
    var showTeamPicker by mutableStateOf(false)
    private var matcher: ChannelMatcher? = null
    private var matcherFor: List<Channel>? = null
    private val matchCache = HashMap<String, List<Channel>>()

    // TV guide
    /** Guide data by channel key. Only channels that have been on screen are fetched. */
    val epg = mutableStateMapOf<String, EpgEntry>()
    private val epgGate = Semaphore(4)
    var guideCategory by mutableStateOf(if (favorites.isNotEmpty()) FAVORITES_CATEGORY else ALL_CATEGORIES)

    // In-app updates
    private val updater = Updater(app, http)
    var update by mutableStateOf<UpdateInfo?>(null)
        private set
    var showUpdatePrompt by mutableStateOf(false)
    var checkingUpdate by mutableStateOf(false)
        private set
    var updateStatus by mutableStateOf<String?>(null)
        private set
    var updateProgress by mutableStateOf<Float?>(null)
        private set
    private var updateJob: Job? = null

    /** After leaving the player, the list focuses this channel again. */
    var pendingFocusKey by mutableStateOf<String?>(null)

    private var loadJob: Job? = null

    init {
        prefs.accentColor.takeIf { it != 0 }?.let { AppColors.setAccent(Color(it)) }
        loadActive()
        checkForUpdate(manual = false)
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
        epg.clear()
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

    // ---- Sports ----------------------------------------------------------

    fun refreshSports() {
        if (sportsLoading) return
        viewModelScope.launch {
            sportsLoading = true
            try {
                val results = League.entries.map { l -> async { l to runCatching { sports.games(l) } } }.awaitAll()
                val next = games.toMutableMap()
                var failures = 0
                for ((l, r) in results) {
                    r.onSuccess { next[l] = it }.onFailure { failures++ }
                }
                games = next
                matchCache.clear()
                sportsError = if (failures == League.entries.size) "Couldn't reach the scores service." else null
                sportsUpdatedMs = System.currentTimeMillis()
            } finally {
                sportsLoading = false
            }
        }
    }

    val anyLive: Boolean get() = games.values.any { list -> list.any { it.state == GameState.LIVE } }

    fun sortedGames(list: List<Game>): List<Game> = list.sortedWith(
        compareBy<Game> { when (it.state) { GameState.LIVE -> 0; GameState.PRE -> 1; GameState.POST -> 2 } }
            .thenBy { if (it.state == GameState.POST) -it.startMs else it.startMs }
    )

    fun myGames(): List<Game> =
        sortedGames(games.values.flatten().filter { it.involves(favoriteTeams) })

    fun liveGames(): List<Game> = sortedGames(games.values.flatten().filter { it.state == GameState.LIVE })

    fun matchesFor(game: Game): List<Channel> {
        if (matcherFor !== channels) {
            matcher = ChannelMatcher(channels)
            matcherFor = channels
            matchCache.clear()
        }
        val key = game.id + "|" + game.networks.joinToString(",")
        return matchCache.getOrPut(key) { matcher?.match(game).orEmpty() }
    }

    fun loadTeams(league: League) {
        if (teams[league] != null) return
        viewModelScope.launch {
            teamsError = null
            try {
                val list = sports.teams(league)
                teams = teams + (league to list)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                teamsError = "Couldn't load teams: ${friendly(e)}"
            }
        }
    }

    fun isFavoriteTeam(t: Team) = t.key in favoriteTeams

    fun toggleTeam(t: Team) {
        favoriteTeams = if (t.key in favoriteTeams) favoriteTeams - t.key else favoriteTeams + t.key
        prefs.saveFavoriteTeams(favoriteTeams)
    }

    fun updateShowScores(value: Boolean) {
        showScores = value
        prefs.showScores = value
    }

    fun openSearch(query: String) {
        gameDetail = null
        searchQuery = query
        section = Section.SEARCH
    }

    // ---- TV guide --------------------------------------------------------

    fun guideChannels(category: String): List<Channel> = when (category) {
        FAVORITES_CATEGORY -> favoriteChannels()
        ALL_CATEGORIES -> channels
        else -> channels.filter { it.categoryId == category }
    }

    /** Fetches guide data for a channel if it's missing or stale. At most 4 requests run at once. */
    suspend fun ensureEpg(ch: Channel) {
        if (ch.epgId.isNullOrBlank()) return
        val p = playlists.find { it.id == ch.playlistId } ?: return
        fun fresh(e: EpgEntry?): Boolean {
            if (e == null) return false
            val age = System.currentTimeMillis() - e.fetchedMs
            return age < if (e.failed) EPG_RETRY_MS else EPG_FRESH_MS
        }
        if (fresh(epg[ch.key])) return
        epgGate.withPermit {
            if (fresh(epg[ch.key])) return
            val entry = try {
                EpgEntry(client.shortEpg(p, ch.streamId), System.currentTimeMillis(), false)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                EpgEntry(emptyList(), System.currentTimeMillis(), true)
            }
            if (epg.size > EPG_MAX_CHANNELS) epg.keys.take(EPG_MAX_CHANNELS / 4).toList().forEach { epg.remove(it) }
            epg[ch.key] = entry
        }
    }

    /** The program on now and the one after it, if the guide has them. */
    fun nowAndNext(ch: Channel): Pair<Program?, Program?> {
        val list = epg[ch.key]?.programs ?: return null to null
        val now = System.currentTimeMillis()
        val i = list.indexOfFirst { now >= it.startMs && now < it.endMs }
        if (i < 0) return null to list.firstOrNull { it.startMs > now }
        return list[i] to list.getOrNull(i + 1)
    }

    // ---- Updates ---------------------------------------------------------

    fun checkForUpdate(manual: Boolean) {
        if (checkingUpdate) return
        viewModelScope.launch {
            checkingUpdate = true
            if (manual) updateStatus = null
            try {
                val info = updater.latest()
                if (info != null && info.versionCode > BuildConfig.VERSION_CODE) {
                    update = info
                    showUpdatePrompt = true
                } else if (manual) {
                    updateStatus = "You're on the latest version."
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (manual) updateStatus = "Couldn't check for updates: ${friendly(e)}"
            } finally {
                checkingUpdate = false
            }
        }
    }

    fun installUpdate() {
        val info = update ?: return
        if (updateJob?.isActive == true) return
        if (!updater.canInstall()) {
            updateStatus = if (updater.openInstallPermission()) {
                "First, allow Remo to install updates: turn Remo on in the screen that opened, press Back, then choose Install again."
            } else {
                "First, allow Remo to install updates: Settings → Apps (or Device Preferences) → Security & restrictions → Unknown sources → turn on Remo. Then choose Install again."
            }
            return
        }
        updateJob = viewModelScope.launch {
            updateStatus = "Downloading…"
            updateProgress = 0f
            try {
                val file = updater.download(info) { updateProgress = it }
                updateStatus = "Opening the installer…"
                updater.install(file)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                updateStatus = "Update failed: ${friendly(e)}"
            } finally {
                updateProgress = null
            }
        }
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

    fun updateAccent(c: Color) {
        AppColors.setAccent(c)
        prefs.accentColor = c.toArgb()
    }

    fun updateGuideList(value: Boolean) {
        guideList = value
        prefs.guideListView = value
    }

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
        playerMini = false
    }

    /** Back to full screen from the small window. */
    fun maximizePlayer() {
        playerMini = false
    }

    /** Back in the player: keep watching in a small window and return to the screen behind. */
    fun minimizePlayer() {
        pendingFocusKey = currentChannel?.key
        playerMini = true
    }

    fun zap(delta: Int) {
        if (playQueue.isEmpty()) return
        playIndex = (playIndex + delta).mod(playQueue.size)
    }

    fun stopPlayback() {
        pendingFocusKey = currentChannel?.key
        playQueue = emptyList()
        playIndex = -1
        playerMini = false
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
