package com.inskribed.tvapp.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Image
import androidx.compose.animation.core.tween
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.res.painterResource
import com.inskribed.tvapp.R
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.focusGroup
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.tv.material3.Icon
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.ui.graphics.Brush
import androidx.tv.material3.Border
import androidx.tv.material3.ClickableSurfaceDefaults
import androidx.tv.material3.Surface
import androidx.tv.material3.LocalContentColor
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.Text
import com.inskribed.tvapp.AppViewModel
import com.inskribed.tvapp.Section
import com.inskribed.tvapp.ui.player.PlayerScreen
import kotlinx.coroutines.delay

const val MINI_PLAYER_WIDTH = 320
const val MINI_PLAYER_HEIGHT = 180
private val SIDEBAR_COLLAPSED = 76.dp
private val SIDEBAR_EXPANDED = 230.dp

@Composable
fun AppRoot(vm: AppViewModel) {
    // Back while the small player window is showing stops it. Registered first so
    // screens below (game detail, dialogs) handle Back before this does.
    BackHandler(enabled = vm.currentChannel != null && vm.playerMini) { vm.stopPlayback() }

    Box(Modifier.fillMaxSize().background(AppColors.Bg)) {
        when {
            vm.showUpdatePrompt && vm.update != null && vm.currentChannel == null -> UpdateScreen(vm)
            vm.showAddPlaylist -> AddPlaylistScreen(vm)
            vm.showTeamPicker -> TeamPickerScreen(vm)
            vm.showGroupPicker -> ChannelGroupsScreen(vm)
            vm.gameDetail != null -> GameDetailScreen(vm)
            else -> MainScreen(vm)
        }
        if (vm.currentChannel != null && !vm.showAddPlaylist && !vm.showTeamPicker && !vm.showGroupPicker) {
            val mod = if (vm.playerMini) {
                Modifier
                    .align(Alignment.TopEnd)
                    .padding(top = 24.dp, end = 24.dp)
                    .size(MINI_PLAYER_WIDTH.dp, MINI_PLAYER_HEIGHT.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .border(2.dp, AppColors.Accent.copy(alpha = 0.7f), RoundedCornerShape(12.dp))
            } else {
                Modifier.fillMaxSize()
            }
            PlayerScreen(vm, mod)
        }
    }
}

@Composable
private fun MainScreen(vm: AppViewModel) {
    val contentFocus = remember { FocusRequester() }
    val menuFocus = remember { FocusRequester() }
    var sidebarOpen by remember { mutableStateOf(true) }
    // Back with nothing else to close opens the side menu; Back again from the menu leaves Orka
    // (this handler is off while the menu has focus, so Android closes the app as usual).
    // Registered before the screens below, so their own Back steps (guide groups, game details,
    // the player...) come first.
    BackHandler(enabled = !sidebarOpen) { runCatching { menuFocus.requestFocus() } }
    val isGuide = vm.section == Section.GUIDE
    // TV Guide, TiviMate-style: inside the channels the menu slides away and the guide uses the full
    // width; otherwise the guide sits beside the collapsed menu. Done as a slide (read only while
    // drawing), so the guide isn't re-laid out on every animation frame.
    val guideHidesMenu = isGuide && vm.guideImmersive
    val contentShift by animateDpAsState(
        if (isGuide && !guideHidesMenu) SIDEBAR_COLLAPSED + 4.dp else 0.dp,
        animationSpec = tween(220),
        label = "content",
    )
    Box(Modifier.fillMaxSize()) {
        Box(
            Modifier
                .fillMaxSize()
                .padding(start = if (isGuide) 24.dp else SIDEBAR_COLLAPSED + 28.dp, top = 32.dp, end = if (isGuide) 24.dp else 40.dp)
                .graphicsLayer { translationX = contentShift.toPx() }
                .focusRequester(contentFocus)
                .focusGroup()
        ) {
            when (vm.section) {
                Section.GUIDE -> GuideScreen(vm)
                Section.SPORTS -> SportsScreen(vm)
                Section.FAVORITES -> FavoritesScreen(vm)
                Section.SEARCH -> SearchScreen(vm)
                Section.SETTINGS -> SettingsScreen(vm)
            }
        }
        MenuDim(sidebarOpen)
        Sidebar(
            vm,
            open = sidebarOpen,
            hidden = guideHidesMenu,
            onOpenChange = { sidebarOpen = it },
            toContent = { runCatching { contentFocus.requestFocus() } },
            firstFocus = menuFocus,
        )
    }
}

/** Dims the screen behind the open menu. Its own composable so the fade doesn't redraw the screen behind it. */
@Composable
private fun MenuDim(open: Boolean) {
    val dim by animateFloatAsState(if (open) 0.55f else 0f, label = "dim")
    Box(Modifier.fillMaxSize().graphicsLayer { alpha = dim }.background(Color.Black))
}

@OptIn(ExperimentalComposeUiApi::class)
@Composable
private fun Sidebar(
    vm: AppViewModel,
    open: Boolean,
    hidden: Boolean,
    onOpenChange: (Boolean) -> Unit,
    toContent: () -> Unit,
    firstFocus: FocusRequester,
) {
    LaunchedEffect(Unit) {
        delay(100)
        runCatching { firstFocus.requestFocus() }
    }
    val width by animateDpAsState(if (open) SIDEBAR_EXPANDED else SIDEBAR_COLLAPSED, label = "sidebar")
    // Slides off to the left while you're inside the TV Guide's channels.
    val slide by animateDpAsState(if (hidden && !open) -(SIDEBAR_COLLAPSED + 12.dp) else 0.dp, tween(220), label = "slide")
    Column(
        Modifier
            .graphicsLayer { translationX = slide.toPx() }
            .onFocusChanged { onOpenChange(it.hasFocus) }
            // Entering the menu from the right always lands on the current section.
            .focusProperties { enter = { firstFocus } }
            .focusGroup()
            .onPreviewKeyEvent { e ->
                if (e.type == KeyEventType.KeyDown && e.key == Key.DirectionRight) { toContent(); true } else false
            }
            .width(width)
            .fillMaxHeight()
            .background(AppColors.Panel)
            .padding(horizontal = 10.dp, vertical = 32.dp)
    ) {
        Row(Modifier.height(48.dp).padding(start = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Image(painterResource(R.drawable.orka_mark), contentDescription = "Orka", modifier = Modifier.size(width = 30.dp, height = 34.dp))
            if (open) {
                Spacer(Modifier.width(12.dp))
                Column {
                    Text("Orka", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = AppColors.Text, maxLines = 1)
                    Text(vm.active?.name ?: "", fontSize = 12.sp, color = AppColors.TextDim, maxLines = 1)
                }
            }
        }
        Spacer(Modifier.height(20.dp))
        Section.entries.forEach { s ->
            val mod = if (s == vm.section) Modifier.focusRequester(firstFocus) else Modifier
            SidebarItem(
                onClick = toContent,
                selected = vm.section == s,
                modifier = mod.onFocusChanged { if (it.isFocused) vm.section = s },
            ) { focused ->
                Icon(
                    OrkaIcons.of(s),
                    contentDescription = s.label,
                    // The current section's icon carries the accent so you can tell where you are when collapsed.
                    tint = if (vm.section == s && !focused) AppColors.Accent else LocalContentColor.current,
                    modifier = Modifier.size(24.dp),
                )
                if (open) {
                    Spacer(Modifier.width(16.dp))
                    Text(s.label, fontSize = 17.sp, maxLines = 1, softWrap = false)
                }
            }
            Spacer(Modifier.height(4.dp))
        }

        // While something plays in the small window, a shortcut back to full screen.
        val playing = vm.currentChannel
        if (playing != null && vm.playerMini) {
            Spacer(Modifier.weight(1f))
            SidebarItem(onClick = { vm.maximizePlayer() }, selected = false) {
                Icon(OrkaIcons.NowPlaying, contentDescription = "Now playing", tint = AppColors.Highlight, modifier = Modifier.size(24.dp))
                if (open) {
                    Spacer(Modifier.width(16.dp))
                    Column {
                        Text("Now playing", fontSize = 12.sp, color = LocalContentColor.current.copy(alpha = 0.6f), maxLines = 1)
                        Text(playing.name, fontSize = 15.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        }
    }
}

/**
 * Side menu item. Highlighted = a pill with a 2px accent border over a faint, glassy
 * tint of the accent (translucent fill plus a soft light sheen at the top).
 */
@Composable
private fun SidebarItem(
    onClick: () -> Unit,
    selected: Boolean,
    modifier: Modifier = Modifier,
    content: @Composable RowScope.(focused: Boolean) -> Unit,
) {
    val pill = RoundedCornerShape(percent = 50)
    val accent = AppColors.Accent
    var focused by remember { mutableStateOf(false) }
    Surface(
        onClick = onClick,
        modifier = modifier.fillMaxWidth().onFocusChanged { focused = it.isFocused },
        shape = ClickableSurfaceDefaults.shape(pill),
        colors = ClickableSurfaceDefaults.colors(
            containerColor = if (selected) AppColors.Card else Color.Transparent,
            contentColor = AppColors.Text,
            focusedContainerColor = accent.copy(alpha = 0.16f),
            focusedContentColor = AppColors.Text,
            pressedContainerColor = accent.copy(alpha = 0.28f),
            pressedContentColor = AppColors.Text,
        ),
        border = ClickableSurfaceDefaults.border(
            focusedBorder = Border(BorderStroke(2.dp, accent), shape = pill),
            pressedBorder = Border(BorderStroke(2.dp, accent), shape = pill),
        ),
        scale = ClickableSurfaceDefaults.scale(focusedScale = 1.03f),
    ) {
        Row(
            Modifier
                .fillMaxWidth()
                .then(
                    if (focused) Modifier.background(
                        Brush.verticalGradient(listOf(Color.White.copy(alpha = 0.12f), Color.Transparent)),
                        pill,
                    ) else Modifier
                )
                .padding(horizontal = 16.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) { content(focused) }
    }
}
