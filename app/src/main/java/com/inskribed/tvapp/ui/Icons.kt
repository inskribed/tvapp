package com.inskribed.tvapp.ui

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.addPathNodes
import androidx.compose.ui.unit.dp
import com.inskribed.tvapp.Section

/** Simple line icons (24x24, 2px stroke). Tinted by the Icon that draws them. */
private fun lineIcon(name: String, vararg paths: String): ImageVector {
    val b = ImageVector.Builder(name, 24.dp, 24.dp, 24f, 24f)
    for (p in paths) {
        b.addPath(
            pathData = addPathNodes(p),
            stroke = SolidColor(Color.White),
            strokeLineWidth = 2f,
            strokeLineCap = StrokeCap.Round,
            strokeLineJoin = StrokeJoin.Round,
        )
    }
    return b.build()
}

object RemoIcons {
    val LiveTv = lineIcon(
        "LiveTv",
        "M4,7 H20 A2,2 0 0 1 22,9 V18 A2,2 0 0 1 20,20 H4 A2,2 0 0 1 2,18 V9 A2,2 0 0 1 4,7 Z",
        "M8,3 L12,7 L16,3",
    )
    val Guide = lineIcon(
        "Guide",
        "M5,4 H19 A2,2 0 0 1 21,6 V18 A2,2 0 0 1 19,20 H5 A2,2 0 0 1 3,18 V6 A2,2 0 0 1 5,4 Z",
        "M3,10 H21",
        "M3,15 H21",
        "M9,10 V20",
        "M15,4 V10",
    )
    val Sports = lineIcon(
        "Sports",
        "M12,3 A9,9 0 1 1 11.99,3 Z",
        "M12,3 V21",
        "M3,12 H21",
        "M5.6,5.6 A9,9 0 0 1 5.6,18.4",
        "M18.4,5.6 A9,9 0 0 0 18.4,18.4",
    )
    val Favorites = lineIcon(
        "Favorites",
        "M12,3 L14.8,8.6 L21,9.5 L16.5,13.9 L17.6,20.1 L12,17.2 L6.4,20.1 L7.5,13.9 L3,9.5 L9.2,8.6 Z",
    )
    val Search = lineIcon(
        "Search",
        "M10.5,4 A6.5,6.5 0 1 1 10.49,4 Z",
        "M15.5,15.5 L21,21",
    )
    val Settings = lineIcon(
        "Settings",
        "M3,6 H21", "M3,12 H21", "M3,18 H21",
        "M8,4 V8", "M16,10 V14", "M10,16 V20",
    )

    fun of(s: Section): ImageVector = when (s) {
        Section.LIVE -> LiveTv
        Section.GUIDE -> Guide
        Section.SPORTS -> Sports
        Section.FAVORITES -> Favorites
        Section.SEARCH -> Search
        Section.SETTINGS -> Settings
    }
}
