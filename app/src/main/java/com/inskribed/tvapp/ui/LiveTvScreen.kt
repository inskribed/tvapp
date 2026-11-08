package com.inskribed.tvapp.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.Text
import com.inskribed.tvapp.ALL_CATEGORIES
import com.inskribed.tvapp.AppViewModel

@Composable
fun LiveTvScreen(vm: AppViewModel) {
    val focusManager = LocalFocusManager.current
    val channels = vm.channels
    val counts = remember(channels) { channels.groupingBy { it.categoryId }.eachCount() }
    val cats = remember(vm.categories, counts) { vm.categories.filter { (counts[it.id] ?: 0) > 0 } }
    val selected = vm.selectedCategory
    val inCategory = remember(channels, selected) {
        if (selected == ALL_CATEGORIES) channels else channels.filter { it.categoryId == selected }
    }
    val list = remember(inCategory, vm.liveFilter) { vm.filterChannels(inCategory, vm.liveFilter) }

    when {
        vm.playlists.isEmpty() ->
            CenterMessage("Welcome to Remo", "Add your Xtream Codes login to start watching.") {
                TvButton("Add playlist", onClick = { vm.showAddPlaylist = true })
            }
        channels.isEmpty() && vm.loading ->
            CenterMessage("Loading channels…", "Big playlists can take a moment the first time.")
        channels.isEmpty() && vm.loadError != null ->
            CenterMessage("Couldn't load channels", vm.loadError) {
                TvButton("Try again", onClick = { vm.loadActive(force = true) })
            }
        channels.isEmpty() ->
            CenterMessage("No channels found", "Check your playlist in Settings.")
        else -> Row(Modifier.fillMaxSize()) {
            LazyColumn(
                modifier = Modifier.width(if (vm.compact) 250.dp else 300.dp).fillMaxHeight(),
                contentPadding = PaddingValues(vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(if (vm.compact) 0.dp else 2.dp),
            ) {
                item(key = ALL_CATEGORIES) {
                    CategoryRow("All channels", channels.size, selected == ALL_CATEGORIES,
                        onFocus = { vm.selectedCategory = ALL_CATEGORIES },
                        onClick = { focusManager.moveFocus(FocusDirection.Right) }, compact = vm.compact)
                }
                items(cats, key = { it.id }) { c ->
                    CategoryRow(c.name, counts[c.id] ?: 0, selected == c.id,
                        onFocus = { vm.selectedCategory = c.id },
                        onClick = { focusManager.moveFocus(FocusDirection.Right) }, compact = vm.compact)
                }
            }
            Spacer(Modifier.width(24.dp))
            Column(Modifier.weight(1f)) {
                val title = if (selected == ALL_CATEGORIES) "All channels" else vm.categoryName(selected) ?: ""
                ScreenTitle(title, "${list.size} channels  ·  Hold OK to add or remove a favorite")
                Row(verticalAlignment = Alignment.Bottom) {
                    TvTextField(
                        value = vm.liveFilter,
                        onValueChange = { vm.liveFilter = it },
                        label = "Filter",
                        placeholder = "Type to filter this list…",
                        imeAction = ImeAction.Done,
                        modifier = Modifier.width(420.dp),
                    )
                    if (vm.liveFilter.isNotEmpty()) {
                        Spacer(Modifier.width(12.dp))
                        TvButton("Clear", onClick = { vm.liveFilter = "" })
                    }
                }
                Spacer(Modifier.height(8.dp))
                if (list.isEmpty()) {
                    DimText("No channels match \"${vm.liveFilter}\" here.", Modifier.padding(top = 12.dp))
                } else {
                    ChannelList(list, vm, Modifier.fillMaxSize())
                }
            }
        }
    }
}

@Composable
private fun CategoryRow(name: String, count: Int, selected: Boolean, onFocus: () -> Unit, onClick: () -> Unit, compact: Boolean) {
    TvRow(
        onClick = onClick,
        selected = selected,
        verticalPadding = if (compact) 5 else 10,
        modifier = Modifier.onFocusChanged { if (it.isFocused) onFocus() },
    ) {
        Text(name, modifier = Modifier.weight(1f), fontSize = if (compact) 14.sp else 16.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Spacer(Modifier.width(8.dp))
        DimText(count.toString(), size = 13)
    }
}
