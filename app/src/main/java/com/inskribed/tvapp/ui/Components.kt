package com.inskribed.tvapp.ui

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.basicMarquee
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.compositeOver
import androidx.tv.material3.Border
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.ClickableSurfaceDefaults
import androidx.tv.material3.LocalContentColor
import androidx.tv.material3.Surface
import androidx.tv.material3.Text
import coil.compose.AsyncImage
import com.inskribed.tvapp.AppViewModel
import com.inskribed.tvapp.data.Channel
import kotlinx.coroutines.delay

private const val GLASS_FILL = 0.20f
private const val GLASS_PRESSED = 0.32f

/**
 * The app's highlight ("glass"): the user's accent color as a translucent tint over [base],
 * with light text. Pair with [glassBorder] and [glassSheen].
 */
@Composable
fun glassColors(
    base: Color,
    content: Color = AppColors.Text,
    accent: Color = AppColors.Accent,
) = ClickableSurfaceDefaults.colors(
    containerColor = base,
    contentColor = content,
    focusedContainerColor = accent.copy(alpha = GLASS_FILL).compositeOver(base),
    focusedContentColor = if (content == AppColors.Danger) content else AppColors.Text,
    pressedContainerColor = accent.copy(alpha = GLASS_PRESSED).compositeOver(base),
    pressedContentColor = AppColors.Text,
)

/** 2px accent outline while highlighted. */
@Composable
fun glassBorder(shape: Shape, accent: Color = AppColors.Accent) = ClickableSurfaceDefaults.border(
    focusedBorder = Border(BorderStroke(2.dp, accent), shape = shape),
    pressedBorder = Border(BorderStroke(2.dp, accent), shape = shape),
)

/** Soft light sheen across the top of a highlighted item, for the glass look. */
fun Modifier.glassSheen(focused: Boolean, shape: Shape): Modifier =
    if (!focused) this
    else background(Brush.verticalGradient(listOf(Color.White.copy(alpha = 0.10f), Color.Transparent)), shape)

/** A focusable row: transparent at rest, accent glass when focused. */
@Composable
fun TvRow(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    onLongClick: (() -> Unit)? = null,
    selected: Boolean = false,
    verticalPadding: Int = 10,
    content: @Composable RowScope.() -> Unit,
) {
    val shape = RoundedCornerShape(10.dp)
    var focused by remember { mutableStateOf(false) }
    Surface(
        onClick = onClick,
        onLongClick = onLongClick,
        modifier = modifier.fillMaxWidth().onFocusChanged { focused = it.isFocused },
        shape = ClickableSurfaceDefaults.shape(shape),
        colors = glassColors(if (selected) AppColors.Card else Color.Transparent),
        border = glassBorder(shape),
        scale = ClickableSurfaceDefaults.scale(focusedScale = 1.02f),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .glassSheen(focused, shape)
                .padding(horizontal = 16.dp, vertical = verticalPadding.dp),
            verticalAlignment = Alignment.CenterVertically,
            content = content,
        )
    }
}

@Composable
fun TvButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, danger: Boolean = false) {
    val shape = RoundedCornerShape(percent = 50)
    val accent = if (danger) AppColors.Danger else AppColors.Accent
    var focused by remember { mutableStateOf(false) }
    Surface(
        onClick = onClick,
        modifier = modifier.onFocusChanged { focused = it.isFocused },
        shape = ClickableSurfaceDefaults.shape(shape),
        colors = glassColors(AppColors.Card, content = if (danger) AppColors.Danger else AppColors.Text, accent = accent),
        border = glassBorder(shape, accent),
        scale = ClickableSurfaceDefaults.scale(focusedScale = 1.05f),
    ) {
        Text(
            text,
            modifier = Modifier.glassSheen(focused, shape).padding(horizontal = 22.dp, vertical = 10.dp),
            fontSize = 16.sp,
            fontWeight = FontWeight.Medium,
        )
    }
}

@Composable
fun DimText(text: String, modifier: Modifier = Modifier, size: Int = 14) {
    Text(
        text,
        modifier = modifier,
        fontSize = size.sp,
        color = LocalContentColor.current.copy(alpha = 0.6f),
        maxLines = 2,
        overflow = TextOverflow.Ellipsis,
    )
}

@Composable
fun ScreenTitle(title: String, subtitle: String? = null) {
    Column(Modifier.padding(bottom = 16.dp)) {
        Text(title, fontSize = 28.sp, fontWeight = FontWeight.SemiBold, color = AppColors.Text)
        if (subtitle != null) {
            Spacer(Modifier.height(4.dp))
            Text(subtitle, fontSize = 14.sp, color = AppColors.TextDim)
        }
    }
}

/**
 * Single-line text input that behaves on a remote: up/down move focus out,
 * OK opens the on-screen keyboard.
 */
@Composable
fun TvTextField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    modifier: Modifier = Modifier,
    placeholder: String = "",
    password: Boolean = false,
    keyboardType: KeyboardType = KeyboardType.Text,
    imeAction: ImeAction = ImeAction.Next,
    onDone: () -> Unit = {},
) {
    val focusManager = LocalFocusManager.current
    val keyboard = LocalSoftwareKeyboardController.current
    var focused by remember { mutableStateOf(false) }
    val shape = RoundedCornerShape(10.dp)
    Column(modifier) {
        Text(label, fontSize = 14.sp, color = AppColors.TextDim)
        Spacer(Modifier.height(6.dp))
        BasicTextField(
            value = value,
            onValueChange = onValueChange,
            singleLine = true,
            textStyle = TextStyle(color = AppColors.Text, fontSize = 20.sp, fontFamily = Inter),
            cursorBrush = SolidColor(AppColors.Accent),
            visualTransformation = if (password) PasswordVisualTransformation() else VisualTransformation.None,
            keyboardOptions = KeyboardOptions(
                keyboardType = if (password) KeyboardType.Password else keyboardType,
                imeAction = imeAction,
                autoCorrectEnabled = false,
            ),
            keyboardActions = KeyboardActions(
                onNext = { focusManager.moveFocus(FocusDirection.Down) },
                onDone = { keyboard?.hide(); onDone() },
                onSearch = { keyboard?.hide(); onDone() },
            ),
            modifier = Modifier
                .fillMaxWidth()
                .onFocusChanged { focused = it.isFocused }
                .onPreviewKeyEvent { e ->
                    if (e.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
                    when (e.key) {
                        Key.DirectionDown -> { focusManager.moveFocus(FocusDirection.Down); true }
                        Key.DirectionUp -> { focusManager.moveFocus(FocusDirection.Up); true }
                        Key.DirectionCenter -> { keyboard?.show(); true }
                        else -> false
                    }
                }
                .clip(shape)
                .background(if (focused) AppColors.Card else AppColors.Panel)
                .border(2.dp, if (focused) AppColors.Accent else Color.Transparent, shape)
                .padding(horizontal = 16.dp, vertical = 14.dp),
            decorationBox = { inner ->
                Box {
                    if (value.isEmpty() && placeholder.isNotEmpty()) {
                        Text(placeholder, fontSize = 20.sp, color = AppColors.TextDim.copy(alpha = 0.6f))
                    }
                    inner()
                }
            },
        )
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun ChannelRow(
    channel: Channel,
    favorite: Boolean,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
    modifier: Modifier = Modifier,
    playing: Boolean = false,
    compact: Boolean = false,
) {
    var focused by remember { mutableStateOf(false) }
    TvRow(
        onClick = onClick,
        onLongClick = onLongClick,
        modifier = modifier.onFocusChanged { focused = it.isFocused },
        verticalPadding = if (compact) 4 else 10,
    ) {
        Text(
            channel.num.toString(),
            modifier = Modifier.width(if (compact) 48.dp else 56.dp),
            fontSize = if (compact) 13.sp else 15.sp,
            color = LocalContentColor.current.copy(alpha = 0.55f),
        )
        Box(
            modifier = Modifier
                .size(width = if (compact) 44.dp else 64.dp, height = if (compact) 26.dp else 40.dp)
                .clip(RoundedCornerShape(6.dp))
                .background(Color(0x22FFFFFF)),
            contentAlignment = Alignment.Center,
        ) {
            if (channel.logo != null) {
                AsyncImage(
                    model = channel.logo,
                    contentDescription = null,
                    contentScale = ContentScale.Fit,
                    modifier = Modifier.padding(if (compact) 2.dp else 4.dp),
                )
            } else {
                Text(channel.name.take(2).uppercase(), fontSize = if (compact) 10.sp else 13.sp, fontWeight = FontWeight.Bold)
            }
        }
        Spacer(Modifier.width(if (compact) 12.dp else 16.dp))
        Text(
            channel.name,
            // The highlighted row scrolls its full name if it doesn't fit.
            modifier = Modifier.weight(1f).then(
                if (focused) Modifier.basicMarquee(iterations = Int.MAX_VALUE, initialDelayMillis = 800) else Modifier
            ),
            fontSize = if (compact) 15.sp else 18.sp,
            maxLines = 1,
            overflow = if (focused) TextOverflow.Clip else TextOverflow.Ellipsis,
            fontWeight = if (playing) FontWeight.Bold else FontWeight.Normal,
        )
        if (favorite) {
            Text("★", fontSize = 18.sp, color = AppColors.Star)
        }
    }
}

/** A scrolling list of channels that plays on OK and toggles favorite on long-press. */
@Composable
fun ChannelList(
    channels: List<Channel>,
    vm: AppViewModel,
    modifier: Modifier = Modifier,
) {
    val listState = rememberLazyListState()
    val pending = vm.pendingFocusKey
    LaunchedEffect(pending, channels) {
        if (pending == null) return@LaunchedEffect
        val idx = channels.indexOfFirst { it.key == pending }
        if (idx >= 0) listState.scrollToItem(maxOf(0, idx - 3)) else vm.pendingFocusKey = null
    }
    LazyColumn(
        state = listState,
        modifier = modifier,
        contentPadding = PaddingValues(vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(if (vm.compact) 0.dp else 2.dp),
    ) {
        itemsIndexed(channels, key = { _, c -> c.key }) { index, ch ->
            val fr = remember { FocusRequester() }
            if (ch.key == vm.pendingFocusKey) {
                LaunchedEffect(Unit) {
                    delay(60)
                    runCatching { fr.requestFocus() }
                    vm.pendingFocusKey = null
                }
            }
            ChannelRow(
                channel = ch,
                favorite = vm.isFavorite(ch),
                onClick = { vm.play(channels, index) },
                onLongClick = { vm.toggleFavorite(ch) },
                modifier = Modifier.focusRequester(fr),
                compact = vm.compact,
            )
        }
    }
}

@Composable
fun CenterMessage(title: String, body: String? = null, action: (@Composable () -> Unit)? = null) {
    Box(Modifier.fillMaxWidth().padding(top = 80.dp), contentAlignment = Alignment.TopCenter) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(title, fontSize = 20.sp, color = AppColors.Text)
            if (body != null) {
                Spacer(Modifier.height(8.dp))
                Text(body, fontSize = 15.sp, color = AppColors.TextDim)
            }
            if (action != null) {
                Spacer(Modifier.height(20.dp))
                action()
            }
        }
    }
}
