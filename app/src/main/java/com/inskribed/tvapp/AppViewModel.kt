package com.inskribed.tvapp

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.MutableState
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
import com.inskribed.tvapp.data.ChannelSearch
import com.inskribed.tvapp.data.Xmltv
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
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
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
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
    /** Set while the add-playlist screen is editing an existing playlist (same screen, prefilled). */
    var editingPlaylist by mutableStateOf<Playlist?>(null)

    // Channels
    var categories by mutableStateOf<List<Category>>(emptyList())
        private set
    /** Channels from groups that aren't hidden. Guide, Search and game matching all use this. */
    var channels by mutableStateOf<List<Channel>>(emptyList())
        private set
    /** Every channel from the provider, hidden groups included (favorites use this). */
    var allChannels by mutableStateOf<List<Channel>>(emptyList())
        private set
    /** Group ids hidden in Settings > Channel groups (saved per playlist). */
    var hiddenGroups by mutableStateOf<Set<String>>(emptySet())
        private set
    /** Channel count per group, over all channels. */
    var groupCounts by mutableStateOf<Map<String, Int>>(emptyMap())
        private set
    var showGroupPicker by mutableStateOf(false)

    // M3U guide (XMLTV) status, shown in Settings
    var guideSyncing by mutableStateOf(false)
        private set
    var guideError by mutableStateOf<String?>(null)
        private set
    var guideUpdatedMs by mutableStateOf<Long?>(null)
        private set
    var guideChannelCount by mutableStateOf(0)
        private set
    var guideHasSource by mutableStateOf(false)
        private set
    private var guideJob: Job? = null
    private var guideLoadedFor: String? = null
    private var playlistGuideUrls: List<String> = emptyList()
    private var searchIndexFor: List<Channel>? = null
    private var searchWords: List<List<String>> = emptyList()
    private var searchSquashed: List<String> = emptyList()
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
    // One small state per channel, so guide data arriving for one row redraws only that row.
    // (A single shared map made every visible row redraw whenever any channel's data landed.)
    private val epgStates = LinkedHashMap<String, MutableState<EpgEntry?>>()
    private fun epgState(key: String) = epgStates.getOrPut(key) { mutableStateOf(null) }
    /** Guide data for one channel, or null if not loaded yet. Reading it in a composable observes only this channel. */
    fun epgFor(key: String): EpgEntry? = epgState(key).value
    /** True while focus is inside the TV Guide's channels, so the menu and group list slide away. */
    var guideImmersive by mutableStateOf(false)
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
        active?.id?.let { hiddenGroups = prefs.hiddenGroups(it) }
        loadActive()
        checkForUpdate(manual = false)
    }

    fun categoryName(id: String): String? = categories.firstOrNull { it.id == id }?.name

    // ---- Playlists -------------------------------------------------------

    /** Adds an M3U playlist (Free-TV, iptv-org, HDHomeRun, Plex...). It's downloaded once to check it. */
    fun addM3uPlaylist(name: String, link: String, guideLink: String, onResult: (String?) -> Unit) {
        if (link.isBlank()) {
            onResult("Please enter the playlist link.")
            return
        }
        viewModelScope.launch {
            val url = client.normalizeLink(link)
            val p = Playlist(
                id = UUID.randomUUID().toString().take(8),
                name = name.trim().ifBlank { url.toHttpUrlOrNull()?.host ?: "Playlist ${playlists.size + 1}" },
                server = url,
                username = "",
                password = "",
                kind = Playlist.KIND_M3U,
                epgUrl = guideLink.trim().takeIf { it.isNotEmpty() }?.let { client.normalizeLink(it) },
            )
            try {
                val result = repo.fetchM3u(p)
                if (result.data.channels.isEmpty()) {
                    onResult("That playlist has no channels Orka can play.")
                    return@launch
                }
                // The playlist may name its own guide; keep it for when guide support arrives.
                val saved = p
                playlists = playlists + saved
                prefs.savePlaylists(playlists)
                showAddPlaylist = false
                account = null
                setActive(saved.id)
                onResult(null)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                onResult("Couldn't load that playlist: ${friendly(e)}")
            }
        }
    }

    fun startEditing(p: Playlist) {
        editingPlaylist = p
        showAddPlaylist = true
    }

    fun closePlaylistEditor() {
        showAddPlaylist = false
        editingPlaylist = null
    }

    /**
     * Saves changes to an existing playlist after checking the new details work. The playlist keeps
     * its id, so favorites, hidden groups and recents stay attached to it.
     */
    fun updatePlaylist(
        old: Playlist,
        name: String,
        server: String,
        username: String,
        password: String,
        link: String,
        guideLink: String,
        onResult: (String?) -> Unit,
    ) {
        viewModelScope.launch {
            try {
                val updated: Playlist
                if (old.isM3u) {
                    if (link.isBlank()) {
                        onResult("Please enter the playlist link.")
                        return@launch
                    }
                    val url = client.normalizeLink(link)
                    val candidate = old.copy(
                        name = name.trim().ifBlank { old.name },
                        server = url,
                        epgUrl = guideLink.trim().takeIf { it.isNotEmpty() }?.let { client.normalizeLink(it) },
                    )
                    // Downloads the playlist again (and saves it, so the guide refreshes right away).
                    val result = repo.fetchM3u(candidate)
                    if (result.data.channels.isEmpty()) {
                        onResult("That playlist has no channels Orka can play.")
                        return@launch
                    }
                    updated = candidate
                    repo.clearGuide(old.id) // links may have changed; rebuild the guide
                } else {
                    if (server.isBlank() || username.isBlank() || password.isBlank()) {
                        onResult("Please fill in the server, username and password.")
                        return@launch
                    }
                    val candidate = old.copy(
                        name = name.trim().ifBlank { old.name },
                        server = client.normalizeServer(server),
                        username = username.trim(),
                        password = password.trim(),
                    )
                    val info = client.authenticate(candidate)
                    if (!info.ok) {
                        onResult(info.message ?: "Login failed.")
                        return@launch
                    }
                    // Login details changed: the saved channel list may be from the old account.
                    if (candidate.server != old.server || candidate.username != old.username) repo.clear(old.id)
                    updated = candidate
                }
                playlists = playlists.map { if (it.id == old.id) updated else it }
                prefs.savePlaylists(playlists)
                closePlaylistEditor()
                if (activeId == old.id || active?.id == old.id) setActive(old.id)
                onResult(null)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                onResult((if (old.isM3u) "Couldn't load that playlist: " else "Couldn't connect: ") + friendly(e))
            }
        }
    }

    /** Extra connection details some M3U channels need (iptv-org lists name them per channel). */
    fun streamHeaders(ch: Channel): Pair<String?, Map<String, String>> {
        val headers = ch.referrer?.takeIf { it.isNotBlank() }?.let { mapOf("Referer" to it) } ?: emptyMap()
        return ch.userAgent?.takeIf { it.isNotBlank() } to headers
    }

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
        allChannels = emptyList()
        groupCounts = emptyMap()
        hiddenGroups = prefs.hiddenGroups(id)
        account = null
        epgStates.values.forEach { it.value = null }
        guideJob?.cancel()
        guideJob = null
        guideLoadedFor = null
        guideUpdatedMs = null
        guideChannelCount = 0
        guideError = null
        playlistGuideUrls = emptyList()
        loadActive()
    }

    fun deletePlaylist(id: String) {
        playlists = playlists.filterNot { it.id == id }
        prefs.savePlaylists(playlists)
        repo.clear(id)
        prefs.clearHiddenGroups(id)
        favorites = favorites.filterNot { it.startsWith("$id:") }
        prefs.saveFavorites(favorites)
        if (activeId == id || playlists.none { it.id == activeId }) {
            val next = playlists.firstOrNull()
            if (next != null) setActive(next.id) else {
                activeId = null
                prefs.activePlaylistId = null
                categories = emptyList()
                channels = emptyList()
                allChannels = emptyList()
                groupCounts = emptyMap()
                hiddenGroups = emptySet()
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
            val age = repo.cacheAgeMs(p)
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
            // Account details (status, expiry, connections) only exist for Xtream logins.
            if (!p.isM3u) try {
                account = client.authenticate(p)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
            }
        }
    }

    private fun apply(data: LiveData) {
        categories = data.categories
        allChannels = data.channels
        groupCounts = data.channels.groupingBy { it.categoryId }.eachCount()
        playlistGuideUrls = data.guideUrls
        rebuildVisible()
        if (active?.isM3u == true) loadGuide()
    }

    // ---- M3U guide (XMLTV) ---------------------------------------------

    /**
     * Which guide files to use: a link you typed wins; otherwise the playlist's own list, cut down
     * to the countries of the channels you've kept shown (Free-TV lists 100+ files).
     */
    private fun guideSources(p: Playlist): List<String> {
        val typed = p.epgUrl?.trim()
        if (!typed.isNullOrEmpty() && typed !in playlistGuideUrls) {
            return typed.split(',').map { it.trim() }.filter { it.startsWith("http") }
        }
        val urls = playlistGuideUrls.ifEmpty { listOfNotNull(typed) }
        return Xmltv.chooseSources(urls, Xmltv.countryCodes(channels))
    }

    /**
     * Shows the saved guide right away, and downloads a fresh one when it's missing, older than
     * 12 hours, or [force] is set. Runs in the background; never holds up the app.
     */
    fun loadGuide(force: Boolean = false) {
        val p = active ?: return
        if (!p.isM3u || guideJob?.isActive == true) return
        val sources = guideSources(p)
        guideHasSource = sources.isNotEmpty()
        val chans = allChannels
        guideJob = viewModelScope.launch {
            val saved = repo.loadGuide(p.id)
            if (saved != null && active?.id == p.id) applyGuide(saved.first, saved.second, p.id)
            val stale = saved == null || System.currentTimeMillis() - saved.second > REFRESH_AFTER_MS
            if (!force && !stale) return@launch
            if (sources.isEmpty()) {
                if (active?.id == p.id) applyGuide(emptyMap(), null, p.id)
                return@launch
            }
            guideSyncing = true
            guideError = null
            try {
                val (programs, failures) = repo.downloadGuide(sources, chans)
                if (active?.id != p.id) return@launch
                if (failures == sources.size) {
                    guideError = "Couldn't download the guide."
                } else {
                    repo.saveGuide(p.id, programs)
                    applyGuide(programs, System.currentTimeMillis(), p.id)
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                guideError = friendly(e)
            } finally {
                guideSyncing = false
            }
        }
    }

    /**
     * Starts the M3U guide over, for example after the shown groups changed (which changes which
     * guide files are needed).
     */
    fun reloadGuide() {
        guideJob?.cancel()
        guideJob = null
        loadGuide(force = true)
    }

    /** Puts the guide on every channel of the playlist (channels it doesn't cover show "No guide info"). */
    private fun applyGuide(programs: Map<String, List<Program>>, savedAt: Long?, playlistId: String) {
        val now = System.currentTimeMillis()
        for (ch in allChannels) {
            if (ch.playlistId == playlistId) epgState(ch.key).value = EpgEntry(programs[ch.key].orEmpty(), now, false)
        }
        guideLoadedFor = playlistId
        guideUpdatedMs = savedAt
        guideChannelCount = programs.count { it.value.isNotEmpty() }
    }

    private fun rebuildVisible() {
        val hidden = hiddenGroups
        val visible = if (hidden.isEmpty()) allChannels else allChannels.filter { it.categoryId !in hidden }
        channels = visible
        if (guideCategory != ALL_CATEGORIES && guideCategory != FAVORITES_CATEGORY && guideCategory in hidden) {
            guideCategory = ALL_CATEGORIES
        }
        // Search words are prepared in the background so typing stays quick.
        viewModelScope.launch(Dispatchers.Default) {
            val words = visible.map { ChannelSearch.words(it.name) }
            val squashed = visible.map { ChannelMatcher.normalize(it.name) }
            withContext(Dispatchers.Main) {
                if (channels === visible) {
                    searchWords = words
                    searchSquashed = squashed
                    searchIndexFor = visible
                }
            }
        }
    }

    // ---- Channel groups --------------------------------------------------

    /** Groups that have channels, in the provider's order. */
    fun groupsWithChannels(): List<Category> = categories.filter { (groupCounts[it.id] ?: 0) > 0 }

    fun isGroupVisible(id: String) = id !in hiddenGroups

    fun setGroups(ids: Collection<String>, visible: Boolean) {
        hiddenGroups = if (visible) hiddenGroups - ids.toSet() else hiddenGroups + ids
        active?.id?.let { prefs.saveHiddenGroups(it, hiddenGroups) }
        rebuildVisible()
    }

    /** Region tags found in group names ("US", "FR", ...) with their group ids, biggest first. */
    fun groupPrefixes(): List<Pair<String, List<String>>> {
        val map = LinkedHashMap<String, MutableList<String>>()
        for (c in groupsWithChannels()) {
            val tag = ChannelSearch.groupPrefix(c.name) ?: continue
            map.getOrPut(tag) { ArrayList() }.add(c.id)
        }
        return map.entries.map { it.key to it.value.toList() }
            .sortedWith(compareByDescending<Pair<String, List<String>>> { it.second.size }.thenBy { it.first })
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
        val p = playlists.find { it.id == ch.playlistId } ?: return
        if (p.isM3u) {
            // M3U guides come from XMLTV files, loaded for the whole playlist at once.
            if (guideLoadedFor != p.id && guideJob?.isActive != true) loadGuide()
            return
        }
        if (ch.epgId.isNullOrBlank()) return
        fun fresh(e: EpgEntry?): Boolean {
            if (e == null) return false
            val age = System.currentTimeMillis() - e.fetchedMs
            return age < if (e.failed) EPG_RETRY_MS else EPG_FRESH_MS
        }
        if (fresh(epgStates[ch.key]?.value)) return
        epgGate.withPermit {
            if (fresh(epgStates[ch.key]?.value)) return
            val entry = try {
                EpgEntry(client.shortEpg(p, ch.streamId), System.currentTimeMillis(), false)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                EpgEntry(emptyList(), System.currentTimeMillis(), true)
            }
            // Keep memory in check on the 2GB onn: forget the oldest channels' programs.
            val loaded = epgStates.values.count { it.value != null }
            if (loaded > EPG_MAX_CHANNELS) {
                epgStates.values.filter { it.value != null }.take(EPG_MAX_CHANNELS / 4).forEach { it.value = null }
            }
            epgState(ch.key).value = entry
        }
    }

    /** The program on now and the one after it, if the guide has them. */
    fun nowAndNext(ch: Channel): Pair<Program?, Program?> {
        val list = epgFor(ch.key)?.programs ?: return null to null
        val now = System.currentTimeMillis()
        val i = list.indexOfFirst { now >= it.startMs && now < it.endMs }
        if (i < 0) return null to list.firstOrNull { it.startMs > now }
        return list[i] to list.getOrNull(i + 1)
    }

    // ---- Updates ---------------------------------------------------------

    fun checkForUpdate(manual: Boolean) {
        // Test builds (debug) carry a throwaway version number, so they'd always see "an update".
        if (BuildConfig.DEBUG && !manual) return
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
                "First, allow Orka to install updates: turn Orka on in the screen that opened, press Back, then choose Install again."
            } else {
                "First, allow Orka to install updates: Settings → Apps (or Device Preferences) → Security & restrictions → Unknown sources → turn on Orka. Then choose Install again."
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
        val byKey = allChannels.associateBy { it.key }
        return favorites.mapNotNull { byKey[it] }
    }

    // ---- Search ----------------------------------------------------------

    /** Whole-word search over visible channels ("|us|" finds |US| channels, not "Museum"). */
    fun search(query: String): List<Channel> {
        val list = channels
        if (searchIndexFor !== list) {
            searchWords = list.map { ChannelSearch.words(it.name) }
            searchSquashed = list.map { ChannelMatcher.normalize(it.name) }
            searchIndexFor = list
        }
        return ChannelSearch.search(query, searchWords, searchSquashed).map { list[it] }
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
        val words = ChannelSearch.words(filter)
        if (words.isEmpty()) return list
        return list.filter { ChannelSearch.matches(ChannelSearch.words(it.name), words) }
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
        ch.url?.let { url ->
            // M3U channels: let the player work out the format, with a hint for the common ones.
            val lower = url.substringBefore('?').lowercase()
            val mime = when {
                lower.endsWith(".m3u8") -> MimeTypes.APPLICATION_M3U8
                lower.endsWith(".mpd") -> MimeTypes.APPLICATION_MPD
                else -> null
            }
            return MediaItem.Builder().setUri(url).apply { if (mime != null) setMimeType(mime) }.build()
        }
        val p = playlists.find { it.id == ch.playlistId } ?: return null
        val url = client.streamUrl(p, ch, streamFormat)
        return MediaItem.Builder()
            .setUri(url)
            .setMimeType(if (streamFormat == "m3u8") MimeTypes.APPLICATION_M3U8 else MimeTypes.VIDEO_MP2T)
            .build()
    }
}
