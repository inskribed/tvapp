package com.inskribed.tvapp.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.Text
import com.inskribed.tvapp.AppViewModel
import com.inskribed.tvapp.data.ChannelSearch
import kotlinx.coroutines.delay

/**
 * Show or hide whole channel groups. Hidden groups disappear from the TV Guide, Search and the
 * channels suggested for games. Favorites aren't affected. Same feature as the iPhone app.
 */
@Composable
fun ChannelGroupsScreen(vm: AppViewModel) {
    var filter by remember { mutableStateOf("") }
    val firstFocus = remember { FocusRequester() }
    BackHandler { vm.showGroupPicker = false }
    LaunchedEffect(Unit) {
        delay(80)
        runCatching { firstFocus.requestFocus() }
    }

    val groups = remember(vm.categories, vm.groupCounts) { vm.groupsWithChannels() }
    val prefixes = remember(groups) { vm.groupPrefixes() }
    val shownGroups = remember(groups, filter) {
        val q = ChannelSearch.words(filter)
        if (q.isEmpty()) groups else groups.filter { ChannelSearch.matches(ChannelSearch.words(it.name), q) }
    }
    val visibleCount = groups.count { vm.isGroupVisible(it.id) }

    Row(Modifier.fillMaxSize().background(AppColors.Bg).padding(horizontal = 40.dp, vertical = 36.dp)) {
        // Left: quick actions and countries
        Column(Modifier.width(260.dp)) {
            ScreenTitle(
                "Channel groups",
                if (visibleCount == groups.size) "All ${groups.size} shown" else "$visibleCount of ${groups.size} shown",
            )
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                TvButton(
                    "Show all",
                    onClick = { vm.setGroups(groups.map { it.id }, visible = true) },
                    modifier = Modifier.focusRequester(firstFocus),
                )
                TvButton("Hide all", onClick = { vm.setGroups(groups.map { it.id }, visible = false) })
            }
            Spacer(Modifier.height(18.dp))
            if (prefixes.isNotEmpty()) {
                Text("By country", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = AppColors.Accent,
                    modifier = Modifier.padding(start = 4.dp, bottom = 6.dp))
                LazyColumn(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(2.dp),
                    contentPadding = PaddingValues(vertical = 4.dp),
                ) {
                    items(prefixes, key = { it.first }) { (tag, ids) ->
                        val shown = ids.count { vm.isGroupVisible(it) }
                        TvRow(
                            onClick = { vm.setGroups(ids, visible = shown == 0) },
                            selected = shown == ids.size,
                            verticalPadding = 8,
                        ) {
                            Text(tag, fontSize = 17.sp, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f))
                            DimText(
                                when (shown) {
                                    ids.size -> "${ids.size} shown"
                                    0 -> "hidden"
                                    else -> "$shown of ${ids.size}"
                                },
                                size = 13,
                            )
                        }
                    }
                }
            } else {
                Spacer(Modifier.weight(1f))
            }
            Spacer(Modifier.height(12.dp))
            TvButton("Done", onClick = { vm.showGroupPicker = false })
        }

        Spacer(Modifier.width(32.dp))

        // Right: every group
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.Bottom) {
                TvTextField(
                    value = filter,
                    onValueChange = { filter = it },
                    label = "Find a group",
                    placeholder = "Type a group name…",
                    imeAction = ImeAction.Done,
                    modifier = Modifier.width(380.dp),
                )
                Spacer(Modifier.width(16.dp))
                DimText("OK shows or hides a group. A country on the left switches all of its groups.")
            }
            Spacer(Modifier.height(12.dp))
            if (shownGroups.isEmpty()) {
                DimText("No groups match \"$filter\".")
            } else {
                LazyColumn(
                    verticalArrangement = Arrangement.spacedBy(2.dp),
                    contentPadding = PaddingValues(vertical = 6.dp),
                ) {
                    items(shownGroups, key = { it.id }) { c ->
                        val visible = vm.isGroupVisible(c.id)
                        TvRow(
                            onClick = { vm.setGroups(listOf(c.id), visible = !visible) },
                            selected = visible,
                            verticalPadding = 8,
                        ) {
                            Text(
                                c.name,
                                modifier = Modifier.weight(1f),
                                fontSize = 16.sp,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                            Spacer(Modifier.width(12.dp))
                            DimText("${vm.groupCounts[c.id] ?: 0}", size = 13)
                            Spacer(Modifier.width(16.dp))
                            Text(
                                if (visible) "Shown" else "Hidden",
                                fontSize = 14.sp,
                                fontWeight = FontWeight.Medium,
                                color = if (visible) AppColors.Accent else AppColors.TextDim,
                                modifier = Modifier.width(64.dp),
                            )
                        }
                    }
                }
            }
        }
    }
}
