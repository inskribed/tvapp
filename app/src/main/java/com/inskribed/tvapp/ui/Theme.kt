package com.inskribed.tvapp.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.tv.material3.LocalContentColor
import androidx.tv.material3.LocalTextStyle
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.darkColorScheme
import com.inskribed.tvapp.R

/** Inter, bundled in res/font (SIL Open Font License, see FONT-LICENSE-Inter.txt). */
val Inter = FontFamily(
    Font(R.font.inter_regular, FontWeight.Normal),
    Font(R.font.inter_medium, FontWeight.Medium),
    Font(R.font.inter_semibold, FontWeight.SemiBold),
    Font(R.font.inter_bold, FontWeight.Bold),
)

/** [highlight] is the small secondary accent (progress bars, "Now" labels). */
class AccentPreset(val name: String, val color: Color, val highlight: Color = lerp(color, Color.White, 0.4f))

val OrkaLime = Color(0xFFC9FF3F)

val AccentPresets = listOf(
    AccentPreset("Orka teal", Color(0xFF1FE3CC), highlight = OrkaLime), // the brand default
    AccentPreset("Lime", OrkaLime),
    AccentPreset("Sky", Color(0xFF5AC8FA)),
    AccentPreset("Mint", Color(0xFF4CD9A0)),
    AccentPreset("Amber", Color(0xFFFFB84D)),
    AccentPreset("Coral", Color(0xFFFF7A6B)),
    AccentPreset("Rose", Color(0xFFFF6FAE)),
    AccentPreset("Violet", Color(0xFFB48CFF)),
    AccentPreset("Periwinkle", Color(0xFF8AA4FF)),
    AccentPreset("Silver", Color(0xFFC8CCD6)),
)

object AppColors {
    val Bg = Color(0xFF0B0B0F)
    val Panel = Color(0xFF121219)
    val Card = Color(0xFF1C1C26)
    val Focused = Color(0xFFF2F2F5)
    val OnFocused = Color(0xFF0B0B0F)
    /** The user's chosen accent (Settings → Appearance). Reading it in a composable recomposes on change. */
    val Accent: Color get() = accentState.value
    private val accentState = mutableStateOf(AccentPresets.first().color)

    /** Secondary accent that goes with [Accent]: lime with the Orka teal. */
    val Highlight: Color get() = highlightState.value
    private val highlightState = mutableStateOf(AccentPresets.first().highlight)

    fun setAccent(c: Color) {
        accentState.value = c
        highlightState.value = AccentPresets.firstOrNull { it.color == c }?.highlight ?: lerp(c, Color.White, 0.4f)
    }
    val Text = Color(0xFFF2F2F5)
    val TextDim = Color(0xFF9A9AA8)
    val Star = Color(0xFFFFC94D)
    val Danger = Color(0xFFFF7A7A)
}

@Composable
fun TvAppTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = darkColorScheme(
            primary = AppColors.Accent,
            background = AppColors.Bg,
            surface = AppColors.Panel,
            onSurface = AppColors.Text,
            onBackground = AppColors.Text,
        ),
    ) {
        CompositionLocalProvider(
            LocalTextStyle provides LocalTextStyle.current.copy(fontFamily = Inter),
            // Text outside a row/button has no color of its own; without this it falls back to black.
            LocalContentColor provides AppColors.Text,
            content = content,
        )
    }
}
