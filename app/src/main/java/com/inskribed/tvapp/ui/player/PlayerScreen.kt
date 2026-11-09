package com.inskribed.tvapp.ui.player

import android.content.Context
import android.graphics.Color as AndroidColor
import android.view.KeyEvent
import android.view.ViewGroup
import androidx.activity.compose.BackHandler
import androidx.annotation.OptIn
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import androidx.tv.material3.Text
import coil.compose.AsyncImage
import com.inskribed.tvapp.AppViewModel
import com.inskribed.tvapp.data.USER_AGENT
import com.inskribed.tvapp.ui.AppColors
import com.inskribed.tvapp.ui.formatTime
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import okhttp3.OkHttpClient

private const val MAX_RETRIES = 6

@OptIn(UnstableApi::class)
private fun buildPlayer(context: Context, http: OkHttpClient): ExoPlayer {
    val dataSource = OkHttpDataSource.Factory(http).setUserAgent(USER_AGENT)
    val mediaSources = DefaultMediaSourceFactory(context).setDataSourceFactory(dataSource)
    val loadControl = DefaultLoadControl.Builder()
        .setBufferDurationsMs(20_000, 60_000, 1_500, 3_000)
        .build()
    val renderers = DefaultRenderersFactory(context).setEnableDecoderFallback(true)
    return ExoPlayer.Builder(context, renderers)
        .setMediaSourceFactory(mediaSources)
        .setLoadControl(loadControl)
        .build()
        .apply { playWhenReady = true }
}

@OptIn(UnstableApi::class)
@Composable
fun PlayerScreen(vm: AppViewModel) {
    val channel = vm.currentChannel ?: return
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val player = remember { buildPlayer(context, vm.http) }
    val focus = remember { FocusRequester() }

    var status by remember { mutableStateOf("") }
    var failed by remember { mutableStateOf(false) }
    var retries by remember { mutableIntStateOf(0) }
    var showInfo by remember { mutableStateOf(true) }
    var infoToken by remember { mutableIntStateOf(0) }
    var firstStart by remember { mutableStateOf(true) }
    var retryJob by remember { mutableStateOf<Job?>(null) }
    var paused by remember { mutableStateOf(false) }

    fun showOverlay() {
        showInfo = true
        infoToken++
    }

    fun setPaused(value: Boolean) {
        paused = value
        player.playWhenReady = !value
        showOverlay()
    }

    fun start() {
        retryJob?.cancel()
        failed = false
        retries = 0
        paused = false
        val item = vm.mediaItem(channel)
        if (item == null) {
            failed = true
            status = "This channel's playlist is missing."
            return
        }
        player.setMediaItem(item)
        player.prepare()
        player.playWhenReady = true
    }

    DisposableEffect(player) {
        val listener = object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                when (state) {
                    Player.STATE_BUFFERING -> if (!failed) status = if (retries > 0) "Reconnecting…" else "Loading…"
                    Player.STATE_READY -> { status = ""; retries = 0 }
                    Player.STATE_ENDED -> {
                        // Live streams shouldn't end; treat it as a dropped connection.
                        scope.launch { delay(500); player.prepare() }
                    }
                    else -> Unit
                }
            }

            override fun onPlayerError(error: PlaybackException) {
                if (error.errorCode == PlaybackException.ERROR_CODE_BEHIND_LIVE_WINDOW) {
                    player.seekToDefaultPosition()
                    player.prepare()
                    return
                }
                if (retries < MAX_RETRIES) {
                    retries++
                    status = "Reconnecting… ($retries)"
                    retryJob = scope.launch {
                        delay(1_000L * retries)
                        player.prepare()
                    }
                } else {
                    failed = true
                    status = "This channel isn't responding. Press OK to try again."
                    showOverlay()
                }
            }
        }
        player.addListener(listener)
        onDispose {
            retryJob?.cancel()
            player.removeListener(listener)
            player.release()
        }
    }

    // Change channel. The short delay lets you press up/down several times
    // quickly without starting every stream along the way.
    LaunchedEffect(channel.key) {
        showOverlay()
        if (firstStart) {
            firstStart = false
        } else {
            player.stop()
            status = "Loading…"
            delay(400)
        }
        start()
    }

    // Guide info for the info bar.
    LaunchedEffect(channel.key) { vm.ensureEpg(channel) }

    LaunchedEffect(infoToken) {
        delay(5_000)
        if (!failed && !paused) showInfo = false
    }

    LaunchedEffect(Unit) {
        runCatching { focus.requestFocus() }
    }

    BackHandler { vm.stopPlayback() }

    val upDelta = if (vm.invertKeys) 1 else -1

    Box(
        Modifier
            .fillMaxSize()
            .background(Color.Black)
            .focusRequester(focus)
            .focusable()
            .onPreviewKeyEvent { e ->
                val code = e.nativeKeyEvent.keyCode
                val isDown = e.type == KeyEventType.KeyDown
                when (code) {
                    KeyEvent.KEYCODE_DPAD_UP -> { if (isDown) vm.zap(upDelta); true }
                    KeyEvent.KEYCODE_DPAD_DOWN -> { if (isDown) vm.zap(-upDelta); true }
                    KeyEvent.KEYCODE_CHANNEL_UP -> { if (isDown) vm.zap(1); true }
                    KeyEvent.KEYCODE_CHANNEL_DOWN -> { if (isDown) vm.zap(-1); true }
                    KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER,
                    KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, KeyEvent.KEYCODE_SPACE -> {
                        if (isDown && e.nativeKeyEvent.repeatCount == 0) {
                            if (failed) { start(); showOverlay() } else setPaused(!paused)
                        }
                        true
                    }
                    KeyEvent.KEYCODE_MEDIA_PLAY -> { if (isDown) { if (failed) start() else setPaused(false) }; true }
                    KeyEvent.KEYCODE_MEDIA_PAUSE -> { if (isDown && !failed) setPaused(true); true }
                    KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.KEYCODE_INFO -> {
                        if (isDown) showOverlay(); true
                    }
                    KeyEvent.KEYCODE_MENU -> {
                        if (isDown) { vm.toggleFavorite(channel); showOverlay() }
                        true
                    }
                    else -> false
                }
            }
    ) {
        AndroidView(
            modifier = Modifier.fillMaxSize(),
            factory = { ctx ->
                PlayerView(ctx).apply {
                    layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                    useController = false
                    isFocusable = false
                    isFocusableInTouchMode = false
                    descendantFocusability = ViewGroup.FOCUS_BLOCK_DESCENDANTS
                    keepScreenOn = true
                    resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
                    setShutterBackgroundColor(AndroidColor.BLACK)
                    this.player = player
                }
            },
        )

        if (paused) {
            Box(
                Modifier
                    .align(Alignment.Center)
                    .clip(RoundedCornerShape(40.dp))
                    .background(Color(0xAA000000))
                    .padding(horizontal = 36.dp, vertical = 18.dp)
            ) {
                Text("❚❚  Paused", fontSize = 26.sp, color = Color.White, fontWeight = FontWeight.SemiBold)
            }
        }

        if (status.isNotEmpty() && !showInfo && !paused) {
            Text(
                status,
                fontSize = 15.sp,
                color = Color.White,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(28.dp)
                    .clip(RoundedCornerShape(16.dp))
                    .background(Color(0xAA000000))
                    .padding(horizontal = 14.dp, vertical = 6.dp),
            )
        }

        AnimatedVisibility(
            visible = showInfo,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier.align(Alignment.BottomCenter),
        ) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .background(Brush.verticalGradient(listOf(Color.Transparent, Color(0xE6000000))))
                    .padding(start = 48.dp, end = 48.dp, top = 80.dp, bottom = 36.dp)
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        Modifier
                            .size(width = 128.dp, height = 72.dp)
                            .clip(RoundedCornerShape(10.dp))
                            .background(Color(0x33FFFFFF)),
                        contentAlignment = Alignment.Center,
                    ) {
                        if (channel.logo != null) {
                            AsyncImage(
                                model = channel.logo,
                                contentDescription = null,
                                contentScale = ContentScale.Fit,
                                modifier = Modifier.padding(8.dp),
                            )
                        }
                    }
                    Spacer(Modifier.width(24.dp))
                    Column(Modifier.weight(1f)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("${channel.num}", fontSize = 22.sp, color = AppColors.TextDim)
                            Spacer(Modifier.width(14.dp))
                            Text(
                                channel.name,
                                fontSize = 28.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = Color.White,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                            if (vm.isFavorite(channel)) {
                                Spacer(Modifier.width(12.dp))
                                Text("★", fontSize = 24.sp, color = AppColors.Star)
                            }
                        }
                        Spacer(Modifier.height(6.dp))
                        val cat = vm.categoryName(channel.categoryId)
                        val line = listOfNotNull(
                            cat,
                            "${vm.playIndex + 1} of ${vm.playQueue.size}",
                            status.takeIf { it.isNotEmpty() },
                        ).joinToString("  ·  ")
                        Text(line, fontSize = 16.sp, color = if (failed) AppColors.Danger else AppColors.TextDim)
                        val (nowProg, nextProg) = vm.nowAndNext(channel)
                        if (nowProg != null || nextProg != null) {
                            Spacer(Modifier.height(6.dp))
                            val guide = listOfNotNull(
                                nowProg?.let { "Now: ${it.title} (until ${formatTime(it.endMs)})" },
                                nextProg?.let { "Next: ${it.title}" },
                            ).joinToString("   ·   ")
                            Text(guide, fontSize = 16.sp, color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                    Text("OK pause/play   ▲▼ channel   BACK exit", fontSize = 14.sp, color = AppColors.TextDim)
                }
            }
        }
    }
}
