package com.inskribed.tvapp.ui

import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.darkColorScheme

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
        content = content,
    )
}
