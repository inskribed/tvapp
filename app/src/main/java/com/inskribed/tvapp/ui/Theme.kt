package com.inskribed.tvapp.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.graphics.Color
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

object AppColors {
    val Bg = Color(0xFF0B0B0F)
    val Panel = Color(0xFF121219)
    val Card = Color(0xFF1C1C26)
    val Focused = Color(0xFFF2F2F5)
    val OnFocused = Color(0xFF0B0B0F)
    val Accent = Color(0xFF8AA4FF)
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
