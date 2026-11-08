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
import androidx.compose.ui.focus.FocusDirection
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

@Composable
fun AppRoot(vm: AppViewModel) {
    Box(Modifier.fillMaxSize().background(AppColors.Bg)) {
        if (vm.showAddPlaylist) {
            AddPlaylistScreen(vm)
        } else {
            MainScreen(vm)
            if (vm.currentChannel != null) {
                PlayerScreen(vm)
            }
        }
    }
}

@Composable
private fun MainScreen(vm: AppViewModel) {
    Row(Modifier.fillMaxSize()) {
        Sidebar(vm)
        Box(
            Modifier
                .weight(1f)
                .fillMaxHeight()
                .padding(start = 8.dp, top = 32.dp, end = 40.dp)
        ) {
            when (vm.section) {
                Section.LIVE -> LiveTvScreen(vm)
                Section.FAVORITES -> FavoritesScreen(vm)
                Section.SEARCH -> SearchScreen(vm)
                Section.SETTINGS -> SettingsScreen(vm)
            }
        }
    }
}

@Composable
private fun Sidebar(vm: AppViewModel) {
    val focusManager = LocalFocusManager.current
    val firstFocus = remember { FocusRequester() }
    LaunchedEffect(Unit) {
        delay(100)
        runCatching { firstFocus.requestFocus() }
    }
    Column(
        Modifier
            .width(220.dp)
            .fillMaxHeight()
            .background(AppColors.Panel)
            .padding(horizontal = 14.dp, vertical = 32.dp)
    ) {
        Text(
            "Remo",
            fontSize = 22.sp,
            fontWeight = FontWeight.Bold,
            color = AppColors.Text,
            modifier = Modifier.padding(start = 16.dp, bottom = 4.dp),
        )
        Text(
            vm.active?.name ?: "",
            fontSize = 13.sp,
            color = AppColors.TextDim,
            modifier = Modifier.padding(start = 16.dp),
        )
        Spacer(Modifier.height(28.dp))
        Section.entries.forEach { s ->
            val mod = if (s == vm.section) Modifier.focusRequester(firstFocus) else Modifier
            TvRow(
                onClick = { focusManager.moveFocus(FocusDirection.Right) },
                selected = vm.section == s,
                modifier = mod.onFocusChanged { if (it.isFocused) vm.section = s },
            ) {
                Text(s.label, fontSize = 17.sp)
            }
            Spacer(Modifier.height(4.dp))
        }
    }
}
