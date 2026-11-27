package com.inskribed.tvapp

import android.util.Log
import androidx.activity.ComponentActivity
import androidx.lifecycle.lifecycleScope
import com.inskribed.tvapp.data.League
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

/**
 * Debug builds only (not in the release APK). Lets .github/workflows/screenshots.yml set the app up
 * with a free playlist and arrange a screen through intent extras:
 *
 *   demo_m3u        playlist link to add on a fresh install
 *   demo_keep       comma-separated group names to keep shown (the rest are hidden)
 *   demo_favorites  how many channels to mark as favorites
 *   demo_teams      "NFL:Dallas Cowboys|NBA:Los Angeles Lakers"
 *   demo_section    guide | sports | favorites | search | settings
 *   demo_group      group name to show in the TV Guide
 *
 * Logs "READY" under the tag OrkaDemo when everything is loaded.
 */
object DemoHook {
    private const val TAG = "OrkaDemo"

    fun run(activity: ComponentActivity, vm: AppViewModel) {
        val i = activity.intent ?: return
        val m3u = i.getStringExtra("demo_m3u")
        val keep = i.getStringExtra("demo_keep")?.split(',')?.map { it.trim() }.orEmpty()
        val favorites = i.getStringExtra("demo_favorites")?.toIntOrNull() ?: 0
        val teams = i.getStringExtra("demo_teams")?.split('|').orEmpty()
        val section = i.getStringExtra("demo_section")
        val group = i.getStringExtra("demo_group")
        if (m3u == null && section == null && keep.isEmpty() && teams.isEmpty() && group == null) return

        activity.lifecycleScope.launch {
            if (vm.playlists.isEmpty() && m3u != null) {
                val error = suspendCancellableCoroutine<String?> { c ->
                    vm.addM3uPlaylist("Free-TV", m3u, "") { c.resume(it) }
                }
                Log.i(TAG, "playlist added: ${error ?: "ok"}")
            }
            var waited = 0
            while (vm.allChannels.isEmpty() && waited < 90_000) { delay(250); waited += 250 }

            // Only the groups to keep (this also decides which guide files get downloaded).
            var changedGroups = false
            if (keep.isNotEmpty() && vm.hiddenGroups.isEmpty()) {
                val hide = vm.groupsWithChannels().filter { it.name !in keep }.map { it.id }
                if (hide.isNotEmpty()) {
                    vm.setGroups(hide, visible = false)
                    changedGroups = true
                }
            }
            if (favorites > 0 && vm.favorites.isEmpty()) {
                vm.groupsWithChannels().filter { vm.isGroupVisible(it.id) }
                    .flatMap { g -> vm.channels.filter { it.categoryId == g.id && it.logo != null }.take(2) }
                    .take(favorites)
                    .forEach { vm.toggleFavorite(it) }
            }
            for (spec in teams) {
                val league = runCatching { League.valueOf(spec.substringBefore(':').trim()) }.getOrNull() ?: continue
                val name = spec.substringAfter(':').trim()
                vm.loadTeams(league)
                var t = 0
                while (vm.teams[league] == null && t < 20_000) { delay(250); t += 250 }
                vm.teams[league]?.firstOrNull { it.displayName == name }?.let { if (!vm.isFavoriteTeam(it)) vm.toggleTeam(it) }
            }
            if (section != null) {
                runCatching { Section.valueOf(section.uppercase()) }.getOrNull()?.let { vm.section = it }
            }
            if (group != null) vm.groupsWithChannels().firstOrNull { it.name == group }?.let { vm.guideCategory = it.id }

            if (vm.active?.isM3u == true) {
                if (changedGroups) vm.reloadGuide()
                var g = 0
                while (vm.guideUpdatedMs == null && g < 150_000) { delay(500); g += 500 }
                Log.i(TAG, "guide: ${vm.guideChannelCount} channels")
            }
            delay(1500)
            Log.i(TAG, "READY")
        }
    }
}
