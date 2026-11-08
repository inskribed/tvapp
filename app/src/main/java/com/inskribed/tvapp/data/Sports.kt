package com.inskribed.tvapp.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.time.Instant
import java.time.LocalDate
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter

enum class League(val label: String, val path: String, val daily: Boolean) {
    NFL("NFL", "football/nfl", false),
    NBA("NBA", "basketball/nba", true),
    MLB("MLB", "baseball/mlb", true),
    NHL("NHL", "hockey/nhl", true),
    NCAAF("NCAAF", "football/college-football", false),
}

data class Team(
    val league: League,
    val id: String,
    val displayName: String,
    val shortName: String,
    val nickname: String,
    val abbr: String,
    val logo: String?,
) {
    val key: String get() = "${league.name}:$id"
}

data class GameTeam(val team: Team, val score: String?, val home: Boolean, val record: String?)

enum class GameState { PRE, LIVE, POST }

data class Game(
    val id: String,
    val league: League,
    val startMs: Long,
    val state: GameState,
    val detail: String,
    val away: GameTeam,
    val home: GameTeam,
    val networks: List<String>,
) {
    val title: String get() = "${away.team.shortName} at ${home.team.shortName}"
    fun involves(teamKeys: Collection<String>) = away.team.key in teamKeys || home.team.key in teamKeys
}

/** Reads ESPN's public scoreboard and team lists. */
class SportsClient(private val http: OkHttpClient) {

    private val base = "https://site.api.espn.com/apis/site/v2/sports"
    private val dayFmt = DateTimeFormatter.ofPattern("yyyyMMdd")

    private suspend fun getJson(url: String): JSONObject = withContext(Dispatchers.IO) {
        val req = Request.Builder().url(url).header("User-Agent", USER_AGENT).build()
        http.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) throw IOException("Scores service returned HTTP ${resp.code}")
            JSONObject(resp.body?.string() ?: "{}")
        }
    }

    suspend fun games(league: League): List<Game> {
        val urls = if (league.daily) {
            val tomorrow = LocalDate.now().plusDays(1).format(dayFmt)
            listOf("$base/${league.path}/scoreboard", "$base/${league.path}/scoreboard?dates=$tomorrow")
        } else if (league == League.NCAAF) {
            listOf("$base/${league.path}/scoreboard?groups=80&limit=300")
        } else {
            listOf("$base/${league.path}/scoreboard")
        }
        val out = LinkedHashMap<String, Game>()
        var lastError: Exception? = null
        for (u in urls) {
            val root = try {
                getJson(u)
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Exception) {
                lastError = e
                null
            } ?: continue
            val events = root.optJSONArray("events") ?: continue
            for (i in 0 until events.length()) {
                val g = runCatching { parseGame(league, events.getJSONObject(i)) }.getOrNull() ?: continue
                out[g.id] = g
            }
        }
        if (out.isEmpty() && lastError != null) throw lastError
        return out.values.toList()
    }

    private fun parseGame(league: League, ev: JSONObject): Game? {
        val comp = ev.optJSONArray("competitions")?.optJSONObject(0) ?: return null
        val status = ev.optJSONObject("status") ?: comp.optJSONObject("status")
        val type = status?.optJSONObject("type")
        val state = when (type?.str("state")) {
            "in" -> GameState.LIVE
            "post" -> GameState.POST
            else -> GameState.PRE
        }
        val detail = type?.str("shortDetail") ?: type?.str("detail") ?: ""
        val competitors = comp.optJSONArray("competitors") ?: return null
        var home: GameTeam? = null
        var away: GameTeam? = null
        for (i in 0 until competitors.length()) {
            val c = competitors.optJSONObject(i) ?: continue
            val t = c.optJSONObject("team") ?: continue
            val team = parseTeam(league, t) ?: continue
            val record = c.optJSONArray("records")?.optJSONObject(0)?.str("summary")
            val gt = GameTeam(team, c.str("score"), c.str("homeAway") == "home", record)
            if (gt.home) home = gt else away = gt
        }
        if (home == null || away == null) return null

        val networks = LinkedHashSet<String>()
        comp.optJSONArray("broadcasts")?.let { arr ->
            for (i in 0 until arr.length()) {
                val names = arr.optJSONObject(i)?.optJSONArray("names") ?: continue
                for (j in 0 until names.length()) names.optString(j).trim().takeIf { it.isNotEmpty() }?.let { networks += it }
            }
        }
        comp.optJSONArray("geoBroadcasts")?.let { arr ->
            for (i in 0 until arr.length()) {
                arr.optJSONObject(i)?.optJSONObject("media")?.str("shortName")?.let { networks += it }
            }
        }
        return Game(
            id = ev.str("id") ?: return null,
            league = league,
            startMs = parseTime(ev.str("date") ?: comp.str("date")),
            state = state,
            detail = detail,
            away = away,
            home = home,
            networks = networks.toList(),
        )
    }

    private fun parseTime(s: String?): Long {
        if (s == null) return 0
        return runCatching { OffsetDateTime.parse(s, DateTimeFormatter.ISO_OFFSET_DATE_TIME).toInstant().toEpochMilli() }
            .recoverCatching { Instant.parse(s).toEpochMilli() }
            .getOrDefault(0)
    }

    private fun parseTeam(league: League, t: JSONObject): Team? {
        val id = t.str("id") ?: return null
        val display = t.str("displayName") ?: t.str("name") ?: return null
        val logo = t.str("logo") ?: t.optJSONArray("logos")?.optJSONObject(0)?.str("href")
        return Team(
            league = league,
            id = id,
            displayName = display,
            shortName = t.str("shortDisplayName") ?: display,
            nickname = t.str("name") ?: t.str("shortDisplayName") ?: display,
            abbr = t.str("abbreviation") ?: display.take(3).uppercase(),
            logo = logo,
        )
    }

    suspend fun teams(league: League): List<Team> {
        val root = getJson("$base/${league.path}/teams?limit=1000")
        val teams = root.optJSONArray("sports")?.optJSONObject(0)
            ?.optJSONArray("leagues")?.optJSONObject(0)
            ?.optJSONArray("teams") ?: JSONArray()
        val out = ArrayList<Team>()
        for (i in 0 until teams.length()) {
            val t = teams.optJSONObject(i)?.optJSONObject("team") ?: continue
            parseTeam(league, t)?.let { out += it }
        }
        return out.sortedBy { it.displayName }
    }
}

/**
 * Finds channels in the playlist that are likely carrying a game, using the
 * broadcast network names and event-style channel names ("NBA 03: Warriors vs Lakers").
 */
class ChannelMatcher(private val channels: List<Channel>) {

    private val tokens: List<List<String>> = channels.map { tokenize(it.name) }
    private val index: Map<String, List<Int>> = HashMap<String, MutableList<Int>>().also { map ->
        tokens.forEachIndexed { i, toks -> toks.toSet().forEach { map.getOrPut(it) { ArrayList() }.add(i) } }
    }

    fun match(game: Game, limit: Int = 12): List<Channel> {
        val scores = HashMap<Int, Int>()
        fun bump(i: Int, s: Int) { if ((scores[i] ?: 0) < s) scores[i] = s }

        // Event or team channels named after the teams.
        val awayNick = tokenize(game.away.team.nickname)
        val homeNick = tokenize(game.home.team.nickname)
        val leagueTokens = LEAGUE_TOKENS[game.league].orEmpty()
        val awayHits = findSequence(awayNick)
        val homeHits = findSequence(homeNick)
        for (i in awayHits intersect homeHits) bump(i, 100)
        for (i in (awayHits union homeHits)) {
            if (tokens[i].any { it in leagueTokens }) bump(i, 80)
        }

        // Broadcast networks.
        for (network in game.networks) {
            val key = normalize(network)
            val aliases = ALIASES[key] ?: listOf(tokenize(network))
            for (alias in aliases) {
                if (alias.isEmpty()) continue
                for (i in findSequence(alias, strict = alias.size == 1 && alias[0] in GENERIC)) bump(i, 50)
            }
        }

        return scores.entries
            .map { (i, s) -> i to s + quality(tokens[i]) }
            .sortedWith(compareByDescending<Pair<Int, Int>> { it.second }.thenBy { channels[it.first].name.length })
            .take(limit)
            .map { channels[it.first] }
    }

    /** Channel indices whose name contains [seq] as consecutive words. */
    private fun findSequence(seq: List<String>, strict: Boolean = false): Set<Int> {
        if (seq.isEmpty()) return emptySet()
        val candidates = index[seq[0]] ?: return emptySet()
        val out = HashSet<Int>()
        for (i in candidates) {
            val t = tokens[i]
            for (start in 0..(t.size - seq.size)) {
                var ok = true
                for (k in seq.indices) if (t[start + k] != seq[k]) { ok = false; break }
                if (!ok) continue
                if (strict) {
                    val next = t.getOrNull(start + seq.size)
                    if (next != null && next in EXCLUDE_AFTER) continue
                }
                out += i
                break
            }
        }
        return out
    }

    private fun quality(t: List<String>): Int {
        var s = 0
        if (t.any { it == "4k" || it == "uhd" }) s += 3
        else if (t.any { it == "fhd" }) s += 2
        else if (t.any { it == "hd" }) s += 1
        if (t.any { it == "us" || it == "usa" }) s += 5
        if (t.any { it in FOREIGN }) s -= 20
        return s
    }

    companion object {
        fun tokenize(s: String): List<String> =
            s.lowercase().replace("+", " plus ").split(Regex("[^a-z0-9]+")).filter { it.isNotEmpty() }

        fun normalize(s: String) = s.lowercase().replace("+", "plus").filter { it.isLetterOrDigit() }

        private val LEAGUE_TOKENS = mapOf(
            League.NFL to setOf("nfl"),
            League.NBA to setOf("nba"),
            League.MLB to setOf("mlb"),
            League.NHL to setOf("nhl"),
            League.NCAAF to setOf("ncaaf", "ncaa", "cfb", "college"),
        )

        private val GENERIC = setOf("fox", "abc", "cbs", "nbc", "espn", "tnt", "tbs")
        private val EXCLUDE_AFTER = setOf(
            "news", "business", "sports", "sport", "soccer", "deportes", "life", "kids", "weather",
            "classic", "nation", "music", "movies", "docs", "now", "2", "u", "plus", "network", "comedy",
        )
        private val FOREIGN = setOf("uk", "ca", "mx", "es", "latino", "ar", "br", "fr", "de", "it", "pt", "au", "nz", "in")

        private fun seqs(vararg s: String) = s.map { tokenize(it) }

        private val ALIASES: Map<String, List<List<String>>> = mapOf(
            "espn" to seqs("espn"),
            "espn2" to seqs("espn2", "espn 2"),
            "espnu" to seqs("espnu", "espn u"),
            "espnews" to seqs("espnews", "espn news"),
            "espnplus" to seqs("espn plus", "espnplus"),
            "abc" to seqs("abc"),
            "cbs" to seqs("cbs"),
            "nbc" to seqs("nbc"),
            "fox" to seqs("fox"),
            "fs1" to seqs("fs1", "fox sports 1"),
            "fs2" to seqs("fs2", "fox sports 2"),
            "tnt" to seqs("tnt"),
            "tbs" to seqs("tbs"),
            "trutv" to seqs("trutv", "tru tv"),
            "nbatv" to seqs("nba tv", "nbatv"),
            "nflnet" to seqs("nfl network", "nfl net"),
            "nflnetwork" to seqs("nfl network", "nfl net"),
            "nflredzone" to seqs("redzone", "red zone"),
            "mlbnet" to seqs("mlb network", "mlb net"),
            "mlbnetwork" to seqs("mlb network", "mlb net"),
            "nhlnet" to seqs("nhl network", "nhl net"),
            "nhlnetwork" to seqs("nhl network", "nhl net"),
            "cbssn" to seqs("cbs sports network", "cbssn", "cbs sports net"),
            "cbssportsnetwork" to seqs("cbs sports network", "cbssn"),
            "btn" to seqs("btn", "big ten network", "big 10 network"),
            "bigtennetwork" to seqs("btn", "big ten network"),
            "secn" to seqs("sec network", "secn"),
            "secnetwork" to seqs("sec network", "secn"),
            "accn" to seqs("acc network", "accn"),
            "accnetwork" to seqs("acc network", "accn"),
            "mwn" to seqs("mountain west", "mw network"),
            "mountainwestnetwork" to seqs("mountain west", "mw network"),
            "nbcsba" to seqs("nbc sports bay area", "nbcs bay area", "nbcsba", "nbcs ba", "nbc bay area sports"),
            "nbcsbayarea" to seqs("nbc sports bay area", "nbcs bay area", "nbcsba"),
            "nbcsportsbayarea" to seqs("nbc sports bay area", "nbcs bay area", "nbcsba"),
            "nbcscal" to seqs("nbc sports california", "nbcs california", "nbcs ca"),
            "nbcsportscalifornia" to seqs("nbc sports california", "nbcs california"),
            "primevideo" to seqs("prime video", "amazon prime", "prime"),
            "prime" to seqs("prime video", "amazon prime"),
            "peacock" to seqs("peacock"),
            "netflix" to seqs("netflix"),
            "kmcc" to seqs("vegas 34", "kmcc", "knighttime", "knight time"),
            "vegas34" to seqs("vegas 34", "kmcc", "knighttime"),
            "scripps" to seqs("vegas 34", "kmcc", "knighttime", "scripps"),
            "knighttimeplus" to seqs("knighttime", "knight time"),
        )
    }
}
