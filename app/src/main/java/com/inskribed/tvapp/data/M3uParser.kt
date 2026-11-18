package com.inskribed.tvapp.data

import java.security.MessageDigest

/**
 * Reads M3U playlists (the format legal IPTV sources use: Free-TV, iptv-org, HDHomeRun,
 * Plex/Jellyfin live TV...). Same rules as the iPhone app's OrkaCore/M3UParser.swift,
 * which has the unit tests.
 */
object M3uParser {

    class Result(val data: LiveData, val guideUrls: List<String>)

    fun parse(text: String, playlistId: String): Result {
        val guideUrls = ArrayList<String>()
        val groups = LinkedHashSet<String>()
        val channels = ArrayList<Channel>()
        val usedIds = HashSet<String>()

        var info: Pair<Map<String, String>, String>? = null
        var userAgent: String? = null
        var referrer: String? = null
        var extGroup: String? = null

        for (raw in text.lineSequence()) {
            val line = raw.trim().removePrefix("﻿")
            if (line.isEmpty()) continue
            when {
                line.startsWith("#EXTM3U") -> {
                    val attrs = attributes(line)
                    for (key in listOf("url-tvg", "x-tvg-url")) {
                        attrs[key]?.split(',')?.map { it.trim() }?.forEach { u ->
                            if (u.startsWith("http") && u !in guideUrls) guideUrls += u
                        }
                    }
                }
                line.startsWith("#EXTINF") -> {
                    info = parseExtinf(line)
                    userAgent = null
                    referrer = null
                    extGroup = null
                }
                line.startsWith("#EXTVLCOPT:") -> {
                    val opt = line.removePrefix("#EXTVLCOPT:")
                    val eq = opt.indexOf('=')
                    if (eq > 0) {
                        val key = opt.substring(0, eq).lowercase()
                        val value = opt.substring(eq + 1).trim()
                        if (key == "http-user-agent") userAgent = value
                        if (key == "http-referrer" || key == "http-referer") referrer = value
                    }
                }
                line.startsWith("#EXTGRP:") -> extGroup = line.removePrefix("#EXTGRP:").trim()
                line.startsWith("#") -> Unit // #KODIPROP, other options, comments
                else -> {
                    // A stream address. Only the entry right after an #EXTINF counts.
                    val entry = info ?: continue
                    info = null
                    if (!isPlayable(line)) continue
                    val (attrs, rawTitle) = entry
                    val group = groupName(attrs, extGroup)
                    groups += group

                    var id = stableId(line)
                    var n = 2
                    while (id in usedIds) { id = stableId("$line#$n"); n++ }
                    usedIds += id

                    channels += Channel(
                        playlistId = playlistId,
                        streamId = id,
                        num = attrs["tvg-chno"]?.toIntOrNull() ?: (channels.size + 1),
                        name = rawTitle.ifEmpty { attrs["tvg-name"] ?: "Channel ${channels.size + 1}" },
                        logo = attrs["tvg-logo"]?.takeIf { it.startsWith("http") },
                        categoryId = group,
                        epgId = attrs["tvg-id"]?.trim()?.takeIf { it.isNotEmpty() },
                        url = line,
                        userAgent = userAgent,
                        referrer = referrer,
                    )
                }
            }
        }
        return Result(LiveData(groups.map { Category(it, it) }, channels), guideUrls)
    }

    /** `#EXTINF:-1 tvg-id="x" group-title="News, Sports",Channel Name`: the title starts after the first comma outside quotes. */
    fun parseExtinf(line: String): Pair<Map<String, String>, String> {
        var inQuotes = false
        for (i in line.indices) {
            val c = line[i]
            if (c == '"') inQuotes = !inQuotes
            if (c == ',' && !inQuotes) return attributes(line.substring(0, i)) to line.substring(i + 1).trim()
        }
        return attributes(line) to ""
    }

    private val attrRegex = Regex("""([A-Za-z0-9_-]+)="([^"]*)"""")

    fun attributes(s: String): Map<String, String> =
        attrRegex.findAll(s).associate { it.groupValues[1].lowercase() to it.groupValues[2].trim() }

    /** group-title (first of "A;B"), then #EXTGRP, then the country (tvg-country or the ".us" in tvg-id). */
    fun groupName(attrs: Map<String, String>, extGroup: String?): String {
        attrs["group-title"]?.split(';')?.first()?.trim()?.takeIf { it.isNotEmpty() }?.let { return it }
        extGroup?.trim()?.takeIf { it.isNotEmpty() }?.let { return it }
        attrs["tvg-country"]?.split(';')?.first()?.trim()?.takeIf { it.isNotEmpty() }?.let { return it.uppercase() }
        attrs["tvg-id"]?.let { id ->
            val dot = id.lastIndexOf('.')
            if (dot >= 0) {
                val code = id.substring(dot + 1).substringBefore('@')
                if (code.length in 2..3 && code.all { it.isLetter() }) return code.uppercase()
            }
        }
        return "Other"
    }

    /** Real stream addresses only; video web pages (YouTube, Twitch) and placeholders are skipped. */
    fun isPlayable(url: String): Boolean {
        val l = url.lowercase()
        if (!(l.startsWith("http://") || l.startsWith("https://") || l.startsWith("rtmp://") || l.startsWith("rtsp://"))) return false
        return listOf("youtube.com/", "youtu.be/", "twitch.tv/", "dailymotion.com/video").none { l.contains(it) }
    }

    /** Same address -> same id across refreshes, so favorites stick. Matches the iPhone app ("m" + 12 hex of SHA-1). */
    fun stableId(s: String): String {
        val d = MessageDigest.getInstance("SHA-1").digest(s.toByteArray(Charsets.UTF_8))
        return "m" + d.take(6).joinToString("") { "%02x".format(it) }
    }
}
