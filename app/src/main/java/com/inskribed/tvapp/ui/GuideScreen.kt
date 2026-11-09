package com.inskribed.tvapp.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key as composeKey
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
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
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEvent
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.ClickableSurfaceDefaults
import androidx.tv.material3.LocalContentColor
import androidx.tv.material3.Surface
import androidx.tv.material3.Text
import coil.compose.AsyncImage
import com.inskribed.tvapp.ALL_CATEGORIES
import com.inskribed.tvapp.AppViewModel
import com.inskribed.tvapp.FAVORITES_CATEGORY
import com.inskribed.tvapp.data.Channel
import com.inskribed.tvapp.data.Program
import kotlinx.coroutines.delay
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

private const val HOUR_MS = 60 * 60 * 1000L
private const val SLOT_MS = 30 * 60 * 1000L
private const val WINDOW_MS = 2 * HOUR_MS
private const val MAX_OFFSET_HOURS = 12

private data class GuideFocus(val channel: Channel, val program: Program?)

fun formatTime(ms: Long): String = SimpleDateFormat("h:mm a", Locale.US).format(Date(ms))

@Composable
fun GuideScreen(vm: AppViewModel) {
    when {
        vm.playlists.isEmpty() -> {
            CenterMessage("No playlist yet", "Add your Xtream Codes login to see the guide.") {
                TvButton("Add playlist", onClick = { vm.showAddPlaylist = true })
            }
            return
        }
        vm.channels.isEmpty() -> {
            CenterMessage(if (vm.loading) "Loading channels…" else "No channels found")
            return
        }
    }

    // Tick every minute so "on now" stays correct.
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(60_000)
            now = System.currentTimeMillis()
        }
    }
    var offsetHours by remember { mutableIntStateOf(0) }
    val windowStart = now - now % SLOT_MS + offsetHours * HOUR_MS
    val windowEnd = windowStart + WINDOW_MS

    val cat = vm.guideCategory
    val list = remember(vm.channels, vm.favorites, cat) { vm.guideChannels(cat) }
    var focus by remember { mutableStateOf<GuideFocus?>(null) }
    val listState = rememberLazyListState()

    val pending = vm.pendingFocusKey
    LaunchedEffect(pending, list) {
        if (pending == null) return@LaunchedEffect
        val idx = list.indexOfFirst { it.key == pending }
        if (idx >= 0) listState.scrollToItem(maxOf(0, idx - 2)) else vm.pendingFocusKey = null
    }

    Column(Modifier.fillMaxSize()) {
        GuideHeader(focus, now)
        CategoryChips(vm)
        Spacer(Modifier.height(10.dp))

        BoxWithConstraints(Modifier.fillMaxSize()) {
            val chWidth = if (vm.compact) 190.dp else 220.dp
            val timeline = maxWidth - chWidth
            val rowHeight = if (vm.compact) 46.dp else 58.dp
            fun widthOf(ms: Long): Dp = timeline * (ms.toFloat() / WINDOW_MS)

            Column(Modifier.fillMaxSize()) {
                TimeRuler(windowStart, chWidth, ::widthOf, offsetHours)
                if (list.isEmpty()) {
                    DimText(
                        if (cat == FAVORITES_CATEGORY) "No favorites yet. Hold OK on a channel to add one."
                        else "No channels here.",
                        Modifier.padding(top = 16.dp),
                    )
                } else {
                    LazyColumn(
                        state = listState,
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(bottom = 24.dp),
                    ) {
                        itemsIndexed(list, key = { _, c -> c.key }) { index, ch ->
                            GuideRow(
                                vm = vm,
                                channel = ch,
                                onPlay = { vm.play(list, index) },
                                windowStart = windowStart,
                                windowEnd = windowEnd,
                                now = now,
                                chWidth = chWidth,
                                timeline = timeline,
                                rowHeight = rowHeight,
                                widthOf = ::widthOf,
                                canGoBack = offsetHours > 0,
                                onShift = { delta ->
                                    offsetHours = (offsetHours + delta).coerceIn(0, MAX_OFFSET_HOURS)
                                },
                                onFocus = { focus = it },
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun GuideHeader(focus: GuideFocus?, now: Long) {
    Column(Modifier.fillMaxWidth().height(118.dp)) {
        if (focus == null) {
            ScreenTitle("TV Guide", "OK to watch  ·  Hold OK to favorite  ·  ◀ ▶ to move through time")
            return@Column
        }
        val p = focus.program
        Text(
            p?.title ?: focus.channel.name,
            fontSize = 26.sp,
            fontWeight = FontWeight.SemiBold,
            color = AppColors.Text,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        Spacer(Modifier.height(4.dp))
        val line = buildList {
            add(focus.channel.name)
            if (p != null) {
                add("${formatTime(p.startMs)} – ${formatTime(p.endMs)}")
                if (now >= p.startMs && now < p.endMs) {
                    add("${(p.endMs - now) / 60_000 + 1} min left")
                }
            } else {
                add(if (focus.channel.epgId.isNullOrBlank()) "No guide info for this channel" else "No guide info right now")
            }
        }.joinToString("  ·  ")
        Text(line, fontSize = 15.sp, color = AppColors.Accent, maxLines = 1, overflow = TextOverflow.Ellipsis)
        if (p?.description != null) {
            Spacer(Modifier.height(6.dp))
            DimText(p.description, size = 14)
        }
    }
}

@Composable
private fun CategoryChips(vm: AppViewModel) {
    val channels = vm.channels
    val counts = remember(channels) { channels.groupingBy { it.categoryId }.eachCount() }
    val chips = remember(vm.categories, counts, vm.favorites.isEmpty()) {
        buildList {
            if (vm.favorites.isNotEmpty()) add(FAVORITES_CATEGORY to "★ Favorites")
            add(ALL_CATEGORIES to "All channels")
            vm.categories.filter { (counts[it.id] ?: 0) > 0 }.forEach { add(it.id to it.name) }
        }
    }
    LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp), contentPadding = PaddingValues(vertical = 4.dp)) {
        items(chips, key = { it.first }) { (id, name) ->
            val selected = vm.guideCategory == id
            Surface(
                onClick = { vm.guideCategory = id },
                shape = ClickableSurfaceDefaults.shape(RoundedCornerShape(18.dp)),
                colors = ClickableSurfaceDefaults.colors(
                    containerColor = if (selected) AppColors.Card else Color.Transparent,
                    contentColor = if (selected) AppColors.Text else AppColors.TextDim,
                    focusedContainerColor = AppColors.Focused,
                    focusedContentColor = AppColors.OnFocused,
                    pressedContainerColor = AppColors.Focused,
                    pressedContentColor = AppColors.OnFocused,
                ),
                scale = ClickableSurfaceDefaults.scale(focusedScale = 1.05f),
            ) {
                Text(
                    name,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 7.dp),
                    fontSize = 14.sp,
                    fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                    maxLines = 1,
                )
            }
        }
    }
}

@Composable
private fun TimeRuler(windowStart: Long, chWidth: Dp, widthOf: (Long) -> Dp, offsetHours: Int) {
    Row(Modifier.fillMaxWidth().height(28.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(
            if (offsetHours == 0) "Now" else "+${offsetHours}h",
            modifier = Modifier.width(chWidth).padding(start = 12.dp),
            fontSize = 13.sp,
            color = AppColors.Accent,
            fontWeight = FontWeight.SemiBold,
        )
        Box(Modifier.weight(1f)) {
            for (i in 0 until (WINDOW_MS / SLOT_MS).toInt()) {
                Text(
                    formatTime(windowStart + i * SLOT_MS),
                    modifier = Modifier.offset(x = widthOf(i * SLOT_MS)).padding(start = 8.dp),
                    fontSize = 13.sp,
                    color = AppColors.TextDim,
                )
            }
        }
    }
}

@Composable
private fun GuideRow(
    vm: AppViewModel,
    channel: Channel,
    onPlay: () -> Unit,
    windowStart: Long,
    windowEnd: Long,
    now: Long,
    chWidth: Dp,
    timeline: Dp,
    rowHeight: Dp,
    widthOf: (Long) -> Dp,
    canGoBack: Boolean,
    onShift: (Int) -> Unit,
    onFocus: (GuideFocus) -> Unit,
) {
    // Wait a moment so fast scrolling doesn't request every channel along the way.
    LaunchedEffect(channel.key) {
        delay(250)
        vm.ensureEpg(channel)
    }
    val channelFocus = remember { FocusRequester() }
    if (channel.key == vm.pendingFocusKey) {
        LaunchedEffect(Unit) {
            delay(80)
            runCatching { channelFocus.requestFocus() }
            vm.pendingFocusKey = null
        }
    }

    val entry = vm.epg[channel.key]
    val programs = entry?.programs.orEmpty().filter { it.endMs > windowStart && it.startMs < windowEnd }

    Row(Modifier.fillMaxWidth().height(rowHeight)) {
        // Channel cell
        GuideCell(
            width = chWidth,
            onClick = onPlay,
            onLongClick = { vm.toggleFavorite(channel) },
            onFocus = { onFocus(GuideFocus(channel, vm.nowAndNext(channel).first)) },
            modifier = Modifier.focusRequester(channelFocus),
            background = AppColors.Panel,
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    Modifier
                        .size(width = 40.dp, height = 26.dp)
                        .clip(RoundedCornerShape(4.dp))
                        .background(Color(0x22FFFFFF)),
                    contentAlignment = Alignment.Center,
                ) {
                    if (channel.logo != null) {
                        AsyncImage(
                            model = channel.logo,
                            contentDescription = null,
                            contentScale = ContentScale.Fit,
                            modifier = Modifier.padding(2.dp),
                        )
                    } else {
                        Text(channel.name.take(2).uppercase(), fontSize = 10.sp, fontWeight = FontWeight.Bold)
                    }
                }
                Spacer(Modifier.width(10.dp))
                Text(
                    channel.name,
                    modifier = Modifier.weight(1f),
                    fontSize = 14.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                if (vm.isFavorite(channel)) Text("★", fontSize = 13.sp, color = AppColors.Star)
            }
        }

        // Programs
        Row(Modifier.width(timeline)) {
            if (programs.isEmpty()) {
                val label = when {
                    channel.epgId.isNullOrBlank() -> "No guide info"
                    entry == null -> "Loading…"
                    else -> "No guide info"
                }
                GuideCell(
                    width = timeline,
                    onClick = onPlay,
                    onLongClick = { vm.toggleFavorite(channel) },
                    onFocus = { onFocus(GuideFocus(channel, null)) },
                    onKey = { e -> e.key == Key.DirectionLeft && canGoBack && run { onShift(-1); true } },
                    background = AppColors.Bg,
                ) {
                    Text(label, fontSize = 14.sp, color = LocalContentColor.current.copy(alpha = 0.5f), maxLines = 1)
                }
            } else {
                var cursor = windowStart
                for (p in programs) {
                    val start = maxOf(p.startMs, windowStart)
                    val end = minOf(p.endMs, windowEnd)
                    if (start > cursor) Spacer(Modifier.width(widthOf(start - cursor)))
                    cursor = end
                    val w = widthOf(end - start)
                    if (w < 2.dp) continue
                    val onNow = now >= p.startMs && now < p.endMs
                    composeKey(p.startMs) {
                        GuideCell(
                            width = w,
                            onClick = onPlay,
                            onLongClick = { vm.toggleFavorite(channel) },
                            onFocus = { onFocus(GuideFocus(channel, p)) },
                            onKey = { e ->
                                when (e.key) {
                                    // At the edge of the visible time window, move the window instead of leaving the row.
                                    Key.DirectionRight -> p.endMs > windowEnd && run { onShift(1); true }
                                    Key.DirectionLeft -> p.startMs < windowStart && canGoBack && run { onShift(-1); true }
                                    else -> false
                                }
                            },
                            background = if (onNow) AppColors.Card else AppColors.Panel,
                        ) {
                            Text(
                                p.title,
                                fontSize = 14.sp,
                                fontWeight = if (onNow) FontWeight.Medium else FontWeight.Normal,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                            if (w > 110.dp && rowHeight > 50.dp) {
                                Text(
                                    "${formatTime(p.startMs)} – ${formatTime(p.endMs)}",
                                    fontSize = 11.sp,
                                    color = LocalContentColor.current.copy(alpha = 0.6f),
                                    maxLines = 1,
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun GuideCell(
    width: Dp,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
    onFocus: () -> Unit,
    background: Color,
    modifier: Modifier = Modifier,
    onKey: (KeyEvent) -> Boolean = { false },
    content: @Composable ColumnScope.() -> Unit,
) {
    Surface(
        onClick = onClick,
        onLongClick = onLongClick,
        modifier = modifier
            .width(width)
            .fillMaxHeight()
            .padding(2.dp)
            .onFocusChanged { if (it.isFocused) onFocus() }
            .onPreviewKeyEvent { e -> e.type == KeyEventType.KeyDown && onKey(e) },
        shape = ClickableSurfaceDefaults.shape(RoundedCornerShape(6.dp)),
        colors = ClickableSurfaceDefaults.colors(
            containerColor = background,
            contentColor = AppColors.Text,
            focusedContainerColor = AppColors.Focused,
            focusedContentColor = AppColors.OnFocused,
            pressedContainerColor = AppColors.Focused,
            pressedContentColor = AppColors.OnFocused,
        ),
        scale = ClickableSurfaceDefaults.scale(focusedScale = 1f),
    ) {
        Column(
            Modifier.fillMaxSize().padding(horizontal = 10.dp),
            verticalArrangement = Arrangement.Center,
            content = content,
        )
    }
}
