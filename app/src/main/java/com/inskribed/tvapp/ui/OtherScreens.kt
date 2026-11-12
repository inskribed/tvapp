package com.inskribed.tvapp.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.focus.onFocusChanged
import androidx.tv.material3.Border
import androidx.tv.material3.ClickableSurfaceDefaults
import androidx.tv.material3.Surface
import androidx.tv.material3.Text
import com.inskribed.tvapp.AppViewModel
import com.inskribed.tvapp.BuildConfig
import kotlinx.coroutines.delay
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@Composable
fun FavoritesScreen(vm: AppViewModel) {
    val list = remember(vm.channels, vm.favorites) { vm.favoriteChannels() }
    Column(Modifier.fillMaxSize()) {
        ScreenTitle("Favorites", if (list.isEmpty()) null else "${list.size} channels  ·  Hold OK to remove")
        if (list.isEmpty()) {
            CenterMessage("No favorites yet", "On any channel in Live TV, hold OK to add it here.")
        } else {
            ChannelList(list, vm, Modifier.fillMaxSize())
        }
    }
}

@Composable
fun SearchScreen(vm: AppViewModel) {
    val results = remember(vm.searchQuery, vm.channels) { vm.search(vm.searchQuery) }
    Column(Modifier.fillMaxSize()) {
        ScreenTitle("Search")
        TvTextField(
            value = vm.searchQuery,
            onValueChange = { vm.searchQuery = it },
            label = "Channel name",
            placeholder = "Try ESPN, Fox, NBC…",
            imeAction = ImeAction.Search,
            modifier = Modifier.width(520.dp),
        )
        Spacer(Modifier.height(16.dp))
        when {
            vm.searchQuery.isBlank() ->
                DimText("Press OK on the box above to type. Your remote's mic button works on the keyboard too.")
            results.isEmpty() -> DimText("No channels match \"${vm.searchQuery}\".")
            else -> {
                DimText("${results.size} results")
                ChannelList(results, vm, Modifier.fillMaxSize())
            }
        }
    }
}

@Composable
fun SettingsScreen(vm: AppViewModel) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(bottom = 40.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        item { ScreenTitle("Settings") }

        item { SettingHeader("Playlists") }
        vm.playlists.forEach { p ->
            item(key = "pl_${p.id}") {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    TvRow(
                        onClick = { if (p.id != vm.active?.id) vm.setActive(p.id) },
                        selected = p.id == vm.active?.id,
                        modifier = Modifier.weight(1f),
                    ) {
                        Column(Modifier.weight(1f)) {
                            Text(p.name, fontSize = 17.sp)
                            DimText(p.server, size = 13)
                        }
                        if (p.id == vm.active?.id) DimText("In use", size = 13)
                    }
                    Spacer(Modifier.width(12.dp))
                    TvButton("Remove", onClick = { vm.deletePlaylist(p.id) }, danger = true)
                }
            }
        }
        item {
            Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                TvButton("Add playlist", onClick = { vm.showAddPlaylist = true })
                TvButton(if (vm.loading) "Refreshing…" else "Refresh channels", onClick = { vm.loadActive(force = true) })
            }
        }
        item {
            val a = vm.account
            if (a != null) {
                val parts = buildList {
                    a.status?.let { add(it) }
                    a.expiresAtSec?.let {
                        add("expires " + SimpleDateFormat("MMM d, yyyy", Locale.US).format(Date(it * 1000)))
                    }
                    a.maxConnections?.let { add("$it connection${if (it == 1) "" else "s"} allowed") }
                }
                DimText("Account: " + parts.joinToString("  ·  "), Modifier.padding(top = 10.dp, start = 4.dp))
            }
        }

        item { SettingHeader("Sports") }
        item {
            SettingToggle(
                title = "Scores",
                value = if (vm.showScores) "Shown" else "Hidden",
                hint = "Hide scores to avoid spoilers. Game times and channels still show.",
                onClick = { vm.updateShowScores(!vm.showScores) },
            )
        }
        item {
            SettingToggle(
                title = "My teams",
                value = if (vm.favoriteTeams.isEmpty()) "None yet" else "${vm.favoriteTeams.size} selected",
                hint = "Choose favorite teams in the NFL, NBA, MLB, NHL and NCAAF.",
                onClick = { vm.showTeamPicker = true },
            )
        }

        item { SettingHeader("Appearance") }
        item { AccentPicker(vm) }
        item {
            SettingToggle(
                title = "Channel list size",
                value = if (vm.compact) "Compact" else "Comfortable",
                hint = "Compact fits more channels on screen.",
                onClick = { vm.updateCompact(!vm.compact) },
            )
        }

        item { SettingHeader("Playback") }
        item {
            SettingToggle(
                title = "Stream format",
                value = if (vm.streamFormat == "m3u8") "HLS (.m3u8)" else "MPEG-TS (.ts)",
                hint = "Switch if channels won't start or keep stuttering.",
                onClick = { vm.updateStreamFormat(if (vm.streamFormat == "m3u8") "ts" else "m3u8") },
            )
        }
        item {
            SettingToggle(
                title = "Up/down in player",
                value = if (vm.invertKeys) "Up = next channel" else "Up = previous channel",
                hint = "Which way the remote's up/down buttons change channels.",
                onClick = { vm.updateInvertKeys(!vm.invertKeys) },
            )
        }

        item { SettingHeader("About") }
        item {
            val u = vm.update
            SettingToggle(
                title = "Check for updates",
                value = when {
                    vm.checkingUpdate -> "Checking…"
                    u != null -> "Version ${u.versionName} available"
                    else -> ""
                },
                hint = "You have version ${BuildConfig.VERSION_NAME}. Remo also checks each time it starts.",
                onClick = { if (u != null) vm.showUpdatePrompt = true else vm.checkForUpdate(manual = true) },
            )
        }
        item {
            val status = vm.updateStatus
            if (status != null && vm.update == null) DimText(status, Modifier.padding(start = 4.dp, top = 6.dp))
        }
    }
}

@Composable
private fun SettingHeader(text: String) {
    Text(
        text,
        fontSize = 15.sp,
        fontWeight = FontWeight.SemiBold,
        color = AppColors.Accent,
        modifier = Modifier.padding(top = 20.dp, bottom = 6.dp, start = 4.dp),
    )
}

@Composable
private fun SettingToggle(title: String, value: String, hint: String, onClick: () -> Unit) {
    TvRow(onClick = onClick) {
        Column(Modifier.weight(1f)) {
            Text(title, fontSize = 17.sp)
            DimText(hint, size = 13)
        }
        Text(value, fontSize = 15.sp, fontWeight = FontWeight.Medium)
    }
}

@Composable
fun AddPlaylistScreen(vm: AppViewModel) {
    var name by rememberSaveable { mutableStateOf("") }
    var server by rememberSaveable { mutableStateOf("") }
    var user by rememberSaveable { mutableStateOf("") }
    var pass by rememberSaveable { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    val first = remember { FocusRequester() }
    val canCancel = true
    androidx.activity.compose.BackHandler(enabled = canCancel) { vm.showAddPlaylist = false }

    LaunchedEffect(Unit) {
        delay(100)
        runCatching { first.requestFocus() }
    }

    fun submit() {
        if (busy) return
        busy = true
        error = null
        vm.addPlaylist(name, server, user, pass) { err ->
            busy = false
            error = err
        }
    }

    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(Modifier.width(620.dp)) {
            ScreenTitle(
                "Add a playlist",
                "Enter the Xtream Codes login from your provider.",
            )
            TvTextField(name, { name = it }, "Name (optional)", Modifier.fillMaxWidth().focusRequester(first),
                placeholder = "My provider")
            Spacer(Modifier.height(14.dp))
            TvTextField(server, { server = it }, "Server URL", Modifier.fillMaxWidth(),
                placeholder = "http://example.com:8080", keyboardType = KeyboardType.Uri)
            Spacer(Modifier.height(14.dp))
            TvTextField(user, { user = it }, "Username", Modifier.fillMaxWidth())
            Spacer(Modifier.height(14.dp))
            TvTextField(pass, { pass = it }, "Password", Modifier.fillMaxWidth(), password = true,
                imeAction = ImeAction.Done, onDone = { submit() })
            Spacer(Modifier.height(22.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                TvButton(if (busy) "Connecting…" else "Save and connect", onClick = { submit() })
                if (canCancel) TvButton("Cancel", onClick = { vm.showAddPlaylist = false })
            }
            error?.let {
                Spacer(Modifier.height(14.dp))
                Text(it, color = AppColors.Danger, fontSize = 15.sp)
            }
            Spacer(Modifier.height(22.dp))
            DimText("Tip: the Google TV app on your phone can act as a keyboard for this screen.")
        }
    }
}

@Composable
fun UpdateScreen(vm: AppViewModel) {
    val info = vm.update ?: return
    val installFocus = remember { FocusRequester() }
    androidx.activity.compose.BackHandler { vm.showUpdatePrompt = false }
    LaunchedEffect(Unit) {
        delay(100)
        runCatching { installFocus.requestFocus() }
    }
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(Modifier.width(640.dp)) {
            ScreenTitle(
                "Update available",
                "Remo ${info.versionName} is ready. You have ${BuildConfig.VERSION_NAME}.",
            )
            if (info.notes.isNotBlank()) {
                Text("What's new", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = AppColors.Accent)
                Spacer(Modifier.height(6.dp))
                Text(info.notes.take(600), fontSize = 15.sp, color = AppColors.TextDim, maxLines = 8)
                Spacer(Modifier.height(22.dp))
            }
            val progress = vm.updateProgress
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                TvButton(
                    if (progress != null) "Downloading… ${(progress * 100).toInt()}%" else "Install now",
                    onClick = { vm.installUpdate() },
                    modifier = Modifier.focusRequester(installFocus),
                )
                TvButton("Later", onClick = { vm.showUpdatePrompt = false })
            }
            val status = vm.updateStatus
            if (status != null && progress == null) {
                Spacer(Modifier.height(16.dp))
                Text(status, fontSize = 15.sp, color = AppColors.Text)
            }
            Spacer(Modifier.height(22.dp))
            DimText("Your playlists, favorites and settings are kept when you update.")
        }
    }
}

/** Row of color swatches. The chosen color tints the menu highlight and other small touches. */
@Composable
private fun AccentPicker(vm: AppViewModel) {
    var focusedName by remember { mutableStateOf<String?>(null) }
    val current = AccentPresets.firstOrNull { it.color == AppColors.Accent }
    Column(Modifier.padding(start = 16.dp, top = 6.dp, bottom = 10.dp)) {
        Row(verticalAlignment = Alignment.Bottom) {
            Text("Accent color", fontSize = 17.sp)
            Spacer(Modifier.width(12.dp))
            Text(focusedName ?: current?.name ?: "", fontSize = 15.sp, color = AppColors.Accent, fontWeight = FontWeight.Medium)
        }
        DimText("Used for the menu highlight and other small touches.", size = 13)
        Spacer(Modifier.height(12.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            AccentPresets.forEach { p ->
                val selected = p.color == AppColors.Accent
                Surface(
                    onClick = { vm.updateAccent(p.color) },
                    modifier = Modifier
                        .size(40.dp)
                        .onFocusChanged { if (it.isFocused) focusedName = p.name else if (focusedName == p.name) focusedName = null },
                    shape = ClickableSurfaceDefaults.shape(CircleShape),
                    colors = ClickableSurfaceDefaults.colors(
                        containerColor = p.color,
                        focusedContainerColor = p.color,
                        pressedContainerColor = p.color,
                    ),
                    border = ClickableSurfaceDefaults.border(
                        focusedBorder = Border(BorderStroke(3.dp, AppColors.Text), shape = CircleShape),
                    ),
                    scale = ClickableSurfaceDefaults.scale(focusedScale = 1.15f),
                ) {
                    if (selected) {
                        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                            Text("✓", fontSize = 18.sp, fontWeight = FontWeight.Bold, color = AppColors.Bg)
                        }
                    }
                }
            }
        }
    }
}
