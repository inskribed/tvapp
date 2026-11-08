package com.inskribed.tvapp.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.ClickableSurfaceDefaults
import androidx.tv.material3.LocalContentColor
import androidx.tv.material3.Surface
import androidx.tv.material3.Text
import coil.compose.AsyncImage
import com.inskribed.tvapp.AppViewModel
import com.inskribed.tvapp.data.Game
import com.inskribed.tvapp.data.GameState
import com.inskribed.tvapp.data.GameTeam
import com.inskribed.tvapp.data.League
import kotlinx.coroutines.delay
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

private val LiveRed = Color(0xFFFF4D4D)

@Composable
fun SportsScreen(vm: AppViewModel) {
    LaunchedEffect(Unit) {
        while (true) {
            vm.refreshSports()
            delay(if (vm.anyLive) 30_000 else 120_000)
        }
    }

    val myGames = vm.myGames()
    val live = vm.liveGames()

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(bottom = 40.dp),
        verticalArrangement = Arrangement.spacedBy(22.dp),
    ) {
        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    val updated = if (vm.sportsUpdatedMs == 0L) {
                        if (vm.sportsLoading) "Loading games…" else null
                    } else {
                        "Updated " + SimpleDateFormat("h:mm a", Locale.US).format(Date(vm.sportsUpdatedMs))
                    }
                    ScreenTitle("Sports", listOfNotNull(updated, vm.sportsError).joinToString("  ·  ").ifEmpty { null })
                }
                TvButton(
                    if (vm.showScores) "Scores: shown" else "Scores: hidden",
                    onClick = { vm.updateShowScores(!vm.showScores) },
                )
                Spacer(Modifier.width(12.dp))
                TvButton("My teams", onClick = { vm.showTeamPicker = true })
            }
        }

        item(key = "mine") {
            if (vm.favoriteTeams.isEmpty()) {
                SectionBlock("My teams") {
                    PromptCard("Add your teams", "Pick favorites in each league to see their games here.") {
                        vm.showTeamPicker = true
                    }
                }
            } else if (myGames.isEmpty()) {
                SectionBlock("My teams") {
                    PromptCard("No games right now", "Your teams have no games today or coming up.") {
                        vm.showTeamPicker = true
                    }
                }
            } else {
                GameRow("My teams", myGames, vm)
            }
        }

        if (live.isNotEmpty()) {
            item(key = "live") { GameRow("Live now", live, vm) }
        }

        League.entries.forEach { league ->
            val list = vm.games[league].orEmpty()
            if (list.isNotEmpty()) {
                item(key = league.name) { GameRow(league.label, vm.sortedGames(list), vm) }
            }
        }

        if (vm.games.isEmpty() && !vm.sportsLoading && vm.sportsError != null) {
            item {
                CenterMessage("Couldn't load games", vm.sportsError) {
                    TvButton("Try again", onClick = { vm.refreshSports() })
                }
            }
        }
    }
}

@Composable
private fun SectionBlock(title: String, content: @Composable () -> Unit) {
    Column {
        Text(title, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = AppColors.Text)
        Spacer(Modifier.height(10.dp))
        content()
    }
}

@Composable
private fun GameRow(title: String, games: List<Game>, vm: AppViewModel) {
    SectionBlock(title) {
        LazyRow(
            horizontalArrangement = Arrangement.spacedBy(16.dp),
            contentPadding = PaddingValues(vertical = 6.dp, horizontal = 4.dp),
        ) {
            items(games, key = { it.league.name + it.id }) { g -> GameCard(g, vm) }
        }
    }
}

@Composable
private fun cardColors() = ClickableSurfaceDefaults.colors(
    containerColor = AppColors.Card,
    contentColor = AppColors.Text,
    focusedContainerColor = AppColors.Focused,
    focusedContentColor = AppColors.OnFocused,
    pressedContainerColor = AppColors.Focused,
    pressedContentColor = AppColors.OnFocused,
)

@Composable
private fun PromptCard(title: String, body: String, onClick: () -> Unit) {
    Surface(
        onClick = onClick,
        modifier = Modifier.width(420.dp).height(120.dp),
        shape = ClickableSurfaceDefaults.shape(RoundedCornerShape(14.dp)),
        colors = cardColors(),
        scale = ClickableSurfaceDefaults.scale(focusedScale = 1.04f),
    ) {
        Column(Modifier.padding(18.dp)) {
            Text(title, fontSize = 19.sp, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(6.dp))
            DimText(body)
        }
    }
}

@Composable
private fun GameCard(game: Game, vm: AppViewModel) {
    val matches = remember(game, vm.channels) { vm.matchesFor(game) }
    val showScore = vm.showScores && game.state != GameState.PRE
    Surface(
        onClick = { vm.gameDetail = game },
        modifier = Modifier.width(300.dp).height(160.dp),
        shape = ClickableSurfaceDefaults.shape(RoundedCornerShape(14.dp)),
        colors = cardColors(),
        scale = ClickableSurfaceDefaults.scale(focusedScale = 1.05f),
    ) {
        Column(Modifier.padding(horizontal = 16.dp, vertical = 12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                DimText(game.league.label, size = 12)
                Spacer(Modifier.weight(1f))
                StatusText(game, 13)
            }
            Spacer(Modifier.height(8.dp))
            TeamLine(game.away, showScore, game)
            Spacer(Modifier.height(6.dp))
            TeamLine(game.home, showScore, game)
            Spacer(Modifier.weight(1f))
            val net = game.networks.take(2).joinToString(", ")
            val chan = when (matches.size) {
                0 -> "No channel found"
                1 -> "1 channel"
                else -> "${matches.size} channels"
            }
            DimText(listOf(net, chan).filter { it.isNotEmpty() }.joinToString("  ·  "), size = 12)
        }
    }
}

@Composable
private fun TeamLine(t: GameTeam, showScore: Boolean, game: Game, big: Boolean = false) {
    val other = if (t.home) game.away else game.home
    val leading = showScore && game.state == GameState.POST &&
        (t.score?.toIntOrNull() ?: 0) > (other.score?.toIntOrNull() ?: 0)
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(if (big) 44.dp else 26.dp), contentAlignment = Alignment.Center) {
            if (t.team.logo != null) {
                AsyncImage(model = t.team.logo, contentDescription = null, contentScale = ContentScale.Fit)
            }
        }
        Spacer(Modifier.width(10.dp))
        Text(
            if (big) t.team.displayName else t.team.shortName,
            modifier = Modifier.weight(1f),
            fontSize = if (big) 24.sp else 16.sp,
            fontWeight = if (leading) FontWeight.Bold else FontWeight.Medium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        if (showScore && t.score != null) {
            Text(t.score, fontSize = if (big) 30.sp else 18.sp, fontWeight = FontWeight.Bold)
        } else if (game.state == GameState.PRE && t.record != null) {
            DimText(t.record, size = if (big) 16 else 12)
        }
    }
}

@Composable
private fun StatusText(game: Game, size: Int) {
    when (game.state) {
        GameState.LIVE -> Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(8.dp).clip(CircleShape).background(LiveRed))
            Spacer(Modifier.width(6.dp))
            Text(game.detail.ifEmpty { "Live" }, fontSize = size.sp, color = LiveRed, fontWeight = FontWeight.SemiBold)
        }
        GameState.PRE -> Text(startLabel(game.startMs), fontSize = size.sp, color = LocalContentColor.current.copy(alpha = 0.7f))
        GameState.POST -> Text(
            if (game.detail.startsWith("Final")) game.detail else "Final",
            fontSize = size.sp,
            color = LocalContentColor.current.copy(alpha = 0.7f),
        )
    }
}

private fun startLabel(ms: Long): String {
    if (ms == 0L) return "Upcoming"
    val now = Calendar.getInstance()
    val then = Calendar.getInstance().apply { timeInMillis = ms }
    val time = SimpleDateFormat("h:mm a", Locale.US).format(Date(ms))
    val sameYear = now.get(Calendar.YEAR) == then.get(Calendar.YEAR)
    val dayDiff = then.get(Calendar.DAY_OF_YEAR) - now.get(Calendar.DAY_OF_YEAR)
    return when {
        sameYear && dayDiff == 0 -> "Today $time"
        sameYear && dayDiff == 1 -> "Tomorrow $time"
        else -> SimpleDateFormat("EEE MMM d, h:mm a", Locale.US).format(Date(ms))
    }
}

/** Full-screen view of one game with the channels that carry it. */
@Composable
fun GameDetailScreen(vm: AppViewModel) {
    val selected = vm.gameDetail ?: return
    // Keep the score fresh while this screen is open.
    val game = vm.games[selected.league]?.firstOrNull { it.id == selected.id } ?: selected
    val matches = remember(game, vm.channels) { vm.matchesFor(game) }
    val showScore = vm.showScores && game.state != GameState.PRE
    val firstFocus = remember { FocusRequester() }
    BackHandler { vm.gameDetail = null }
    LaunchedEffect(Unit) {
        delay(80)
        runCatching { firstFocus.requestFocus() }
    }

    Row(Modifier.fillMaxSize().background(AppColors.Bg).padding(horizontal = 56.dp, vertical = 40.dp)) {
        Column(Modifier.width(460.dp).fillMaxHeight()) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                DimText(game.league.label, size = 15)
                Spacer(Modifier.width(12.dp))
                StatusText(game, 16)
            }
            Spacer(Modifier.height(24.dp))
            TeamLine(game.away, showScore, game, big = true)
            Spacer(Modifier.height(16.dp))
            TeamLine(game.home, showScore, game, big = true)
            Spacer(Modifier.height(28.dp))
            if (game.networks.isNotEmpty()) {
                DimText("Broadcast: " + game.networks.joinToString(", "), size = 15)
                Spacer(Modifier.height(20.dp))
            }
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                TvButton(
                    if (vm.showScores) "Hide scores" else "Show scores",
                    onClick = { vm.updateShowScores(!vm.showScores) },
                    modifier = if (matches.isEmpty()) Modifier.focusRequester(firstFocus) else Modifier,
                )
                TvButton("Back", onClick = { vm.gameDetail = null })
            }
        }
        Spacer(Modifier.width(48.dp))
        Column(Modifier.weight(1f)) {
            ScreenTitle("Watch on", if (matches.isEmpty()) null else "Best matches from your playlist")
            if (matches.isEmpty()) {
                DimText("Remo couldn't find a channel carrying this game. Try searching your channels:")
                Spacer(Modifier.height(16.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    TvButton(game.away.team.nickname, onClick = { vm.openSearch(game.away.team.nickname) })
                    TvButton(game.home.team.nickname, onClick = { vm.openSearch(game.home.team.nickname) })
                    game.networks.firstOrNull()?.let { n -> TvButton(n, onClick = { vm.openSearch(n) }) }
                }
            } else {
                Box(Modifier.focusRequester(firstFocus)) {
                    ChannelList(matches, vm, Modifier.fillMaxWidth())
                }
            }
        }
    }
}

/** Pick favorite teams in each league. */
@Composable
fun TeamPickerScreen(vm: AppViewModel) {
    var league by remember { mutableStateOf(League.NFL) }
    var filter by remember { mutableStateOf("") }
    val firstFocus = remember { FocusRequester() }
    BackHandler { vm.showTeamPicker = false }
    LaunchedEffect(league) { vm.loadTeams(league) }
    LaunchedEffect(Unit) {
        delay(80)
        runCatching { firstFocus.requestFocus() }
    }

    val all = vm.teams[league]
    val shown = remember(all, filter) {
        val q = filter.trim().lowercase()
        if (q.isEmpty()) all.orEmpty() else all.orEmpty().filter { it.displayName.lowercase().contains(q) || it.abbr.lowercase() == q }
    }
    val selectedHere = all.orEmpty().count { vm.isFavoriteTeam(it) }

    Row(Modifier.fillMaxSize().background(AppColors.Bg).padding(horizontal = 40.dp, vertical = 36.dp)) {
        Column(Modifier.width(220.dp)) {
            ScreenTitle("My teams", "${vm.favoriteTeams.size} selected")
            League.entries.forEachIndexed { i, l ->
                TvRow(
                    onClick = { league = l },
                    selected = league == l,
                    modifier = (if (i == 0) Modifier.focusRequester(firstFocus) else Modifier)
                        .onFocusChanged { if (it.isFocused && league != l) { league = l; filter = "" } },
                ) {
                    Text(l.label, fontSize = 17.sp, modifier = Modifier.weight(1f))
                    val n = vm.favoriteTeams.count { it.startsWith(l.name + ":") }
                    if (n > 0) Text("★ $n", fontSize = 14.sp, color = AppColors.Star)
                }
                Spacer(Modifier.height(4.dp))
            }
            Spacer(Modifier.height(20.dp))
            TvButton("Done", onClick = { vm.showTeamPicker = false })
        }
        Spacer(Modifier.width(32.dp))
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.Bottom) {
                TvTextField(
                    value = filter,
                    onValueChange = { filter = it },
                    label = "Find a ${league.label} team",
                    placeholder = "Type a team or city…",
                    imeAction = ImeAction.Done,
                    modifier = Modifier.width(420.dp),
                )
                Spacer(Modifier.width(16.dp))
                DimText("Press OK to add or remove  ·  $selectedHere selected in ${league.label}")
            }
            Spacer(Modifier.height(12.dp))
            when {
                all == null && vm.teamsError != null -> DimText(vm.teamsError ?: "")
                all == null -> DimText("Loading teams…")
                shown.isEmpty() -> DimText("No teams match \"$filter\".")
                else -> LazyColumn(
                    verticalArrangement = Arrangement.spacedBy(2.dp),
                    contentPadding = PaddingValues(vertical = 6.dp),
                ) {
                    items(shown, key = { it.key }) { t ->
                        val fav = vm.isFavoriteTeam(t)
                        TvRow(onClick = { vm.toggleTeam(t) }, verticalPadding = 8) {
                            Box(Modifier.size(32.dp), contentAlignment = Alignment.Center) {
                                if (t.logo != null) AsyncImage(model = t.logo, contentDescription = null, contentScale = ContentScale.Fit)
                            }
                            Spacer(Modifier.width(14.dp))
                            Text(t.displayName, fontSize = 17.sp, modifier = Modifier.weight(1f))
                            Text(if (fav) "★" else "☆", fontSize = 20.sp, color = if (fav) AppColors.Star else LocalContentColor.current.copy(alpha = 0.4f))
                        }
                    }
                }
            }
        }
    }
}
