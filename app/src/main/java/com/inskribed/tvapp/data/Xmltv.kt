package com.inskribed.tvapp.data

import android.util.Xml
import org.xmlpull.v1.XmlPullParser
import java.io.BufferedInputStream
import java.io.File
import java.io.InputStream
import java.util.zip.GZIPInputStream

/**
 * TV guide for M3U playlists, from XMLTV files (often .xml.gz). Same rules as the iPhone app's
 * OrkaCore/XMLTV.swift, which has the unit tests. Built for the 2GB onn: files are read as they
 * download (never held whole), and only your channels from 2 hours ago to 24 hours ahead are kept.
 */
object Xmltv {
    const val MAX_FILES = 8
    const val LOOK_BACK_MS = 2 * 3600_000L
    const val LOOK_AHEAD_MS = 24 * 3600_000L
    private const val MAX_SUMMARY = 400

    // ---- Which guide files to download ----------------------------------

    /** Country codes of the given channels, from their guide ids ("Rai1.it" -> IT, "ABC.us@East" -> US). */
    fun countryCodes(channels: List<Channel>): Map<String, Int> {
        val out = HashMap<String, Int>()
        for (ch in channels) {
            val id = ch.epgId ?: continue
            val dot = id.lastIndexOf('.')
            if (dot < 0) continue
            val tail = id.substring(dot + 1).substringBefore('@')
            if (tail.length != 2 || !tail.all { it.isLetter() }) continue
            val code = tail.uppercase()
            out[code] = (out[code] ?: 0) + 1
            if (code == "GB") out["UK"] = (out["UK"] ?: 0) + 1
            if (code == "UK") out["GB"] = (out["GB"] ?: 0) + 1
        }
        return out
    }

    private val fileCodeRegex = Regex("""(?:^|[_\-.])([a-z]{2})\d*\.xml(?:\.gz)?$""")

    private fun fileName(url: String) = url.substringAfterLast('/').lowercase()

    /** "epg_ripper_IT1.xml.gz" -> IT; null for network files like "epg_ripper_ALJAZEERA1.xml.gz". */
    fun fileCountryCode(url: String): String? =
        fileCodeRegex.find(fileName(url))?.groupValues?.get(1)?.uppercase()

    /**
     * Small lists are used whole (minus huge "all sources" and dummy files). Long lists, like
     * Free-TV's 100+ files, are cut down to your shown channels' countries, most channels first,
     * at most [MAX_FILES], preferring each country's plainest file.
     */
    fun chooseSources(urls: List<String>, countries: Map<String, Int>): List<String> {
        val usable = urls.map { it.trim() }
            .filter { val l = it.lowercase(); l.startsWith("http") && "all_sources" !in l && "dummy" !in l }
            .distinct()
        if (usable.size <= 3) return usable
        val shortest = HashMap<String, Int>()
        for (u in usable) {
            val code = fileCountryCode(u) ?: continue
            shortest[code] = minOf(shortest[code] ?: Int.MAX_VALUE, fileName(u).length)
        }
        return usable.withIndex()
            .mapNotNull { (i, u) ->
                val code = fileCountryCode(u) ?: return@mapNotNull null
                val n = countries[code] ?: return@mapNotNull null
                if (fileName(u).length != shortest[code]) return@mapNotNull null
                Triple(u, n, i)
            }
            .sortedWith(compareByDescending<Triple<String, Int, Int>> { it.second }.thenBy { it.third })
            .take(MAX_FILES)
            .map { it.first }
    }

    // ---- Matching guide channels to playlist channels -------------------

    /** By guide id, then the id without punctuation ("Rai.1.it" = "Rai1.it"), then by name ("Rai 1 HD" = "RAI 1"). */
    class Matcher(channels: List<Channel>) {
        private val byId = HashMap<String, MutableList<String>>()
        private val byLooseId = HashMap<String, MutableList<String>>()
        private val byName = HashMap<String, MutableList<String>>()

        init {
            fun add(map: HashMap<String, MutableList<String>>, key: String, value: String) {
                if (key.isEmpty()) return
                val list = map.getOrPut(key) { ArrayList(1) }
                if (value !in list) list += value
            }
            for (ch in channels) {
                val e = ch.epgId?.trim()
                if (!e.isNullOrEmpty()) {
                    val l = e.lowercase()
                    add(byId, l, ch.key)
                    val base = l.substringBefore('@')
                    add(byId, base, ch.key)
                    add(byLooseId, looseId(base), ch.key)
                }
                add(byName, looseName(ch.name), ch.key)
            }
        }

        fun keys(xmlId: String, names: List<String>): List<String> {
            val l = xmlId.trim().lowercase()
            byId[l]?.let { return it }
            val base = l.substringBefore('@')
            byId[base]?.let { return it }
            byLooseId[looseId(base)]?.let { return it }
            for (n in names) byName[looseName(n)]?.let { return it }
            return emptyList()
        }
    }

    fun looseId(s: String): String = s.lowercase().filter { it.isLetterOrDigit() }

    private val qualityWords = setOf("hd", "fhd", "uhd", "sd", "4k", "8k", "hevc", "h265", "1080p", "720p", "576p", "480p", "backup")

    /** "Rai 1 HD (1080p) Ⓢ" -> "rai1". Words in brackets and picture-quality words are ignored. */
    fun looseName(s: String): String {
        val cleaned = StringBuilder()
        var depth = 0
        for (c in s) {
            when (c) {
                '(', '[' -> depth++
                ')', ']' -> depth = maxOf(0, depth - 1)
                else -> if (depth == 0) cleaned.append(c)
            }
        }
        return ChannelMatcher.tokenize(cleaned.toString()).filter { it !in qualityWords }.joinToString("")
    }

    // ---- Reading a guide file -------------------------------------------

    /** "20261119120000 +0100" (no offset = UTC) -> epoch ms. */
    fun parseTime(s: String?): Long? {
        val t = s?.trim() ?: return null
        if (t.length < 12) return null
        fun num(from: Int, len: Int): Int? {
            if (from + len > t.length) return null
            var v = 0
            for (i in from until from + len) {
                val d = t[i]
                if (d !in '0'..'9') return null
                v = v * 10 + (d - '0')
            }
            return v
        }
        val y = num(0, 4) ?: return null
        val mo = num(4, 2) ?: return null
        val d = num(6, 2) ?: return null
        val h = num(8, 2) ?: return null
        val mi = num(10, 2) ?: return null
        val sec = num(12, 2) ?: 0
        var offset = 0
        val sign = t.indexOfFirst { it == '+' || it == '-' }
        if (sign >= 12) {
            val oh = num(sign + 1, 2)
            val om = num(sign + 3, 2)
            if (oh != null && om != null) offset = (oh * 3600 + om * 60) * (if (t[sign] == '-') -1 else 1)
        }
        val days = daysFromCivil(y, mo, d)
        return (days * 86400L + h * 3600L + mi * 60L + sec - offset) * 1000L
    }

    private fun daysFromCivil(year: Int, month: Int, day: Int): Long {
        val y = if (month <= 2) year - 1 else year
        val era = (if (y >= 0) y else y - 399) / 400
        val yoe = y - era * 400
        val doy = (153 * (month + (if (month > 2) -3 else 9)) + 2) / 5 + day - 1
        val doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097L + doe - 719468L
    }

    /** Unzips on the fly if the stream is gzip (.xml.gz); otherwise passes it through. */
    fun maybeGunzip(input: InputStream): InputStream {
        val b = BufferedInputStream(input, 64 * 1024)
        b.mark(2)
        val first = b.read()
        val second = b.read()
        b.reset()
        return if (first == 0x1f && second == 0x8b) BufferedInputStream(GZIPInputStream(b, 64 * 1024), 64 * 1024) else b
    }

    /**
     * Streams a guide file, adding programs for matched channels in [fromMs, toMs] to [into]
     * (keyed by channel key). A broken file keeps whatever was read before the problem.
     */
    fun parse(input: InputStream, matcher: Matcher, fromMs: Long, toMs: Long, into: HashMap<String, MutableList<Program>>): Int {
        val p = Xml.newPullParser()
        p.setFeature(XmlPullParser.FEATURE_PROCESS_NAMESPACES, false)
        p.setInput(input, null)
        val channelKeys = HashMap<String, List<String>>()
        val names = ArrayList<String>()
        var channelId: String? = null
        var inProgramme = false
        var progChannel = ""
        var start = -1L
        var stop = -1L
        var title: String? = null
        var desc: String? = null
        var matched = 0
        fun text(): String? = runCatching { p.nextText().trim() }.getOrNull()
        try {
            var ev = p.eventType
            while (ev != XmlPullParser.END_DOCUMENT) {
                if (ev == XmlPullParser.START_TAG) {
                    when (p.name) {
                        "channel" -> {
                            channelId = p.getAttributeValue(null, "id")
                            names.clear()
                        }
                        "display-name" -> if (channelId != null) text()?.let { names += it }
                        "programme" -> {
                            inProgramme = true
                            progChannel = p.getAttributeValue(null, "channel") ?: ""
                            start = parseTime(p.getAttributeValue(null, "start")) ?: -1L
                            stop = parseTime(p.getAttributeValue(null, "stop")) ?: -1L
                            title = null
                            desc = null
                        }
                        "title" -> if (inProgramme && title == null) title = text()
                        "desc" -> if (inProgramme && desc == null) desc = text()?.take(MAX_SUMMARY)
                    }
                } else if (ev == XmlPullParser.END_TAG) {
                    when (p.name) {
                        "channel" -> {
                            channelId?.let { id ->
                                val keys = matcher.keys(id, names)
                                channelKeys[id] = keys
                                if (keys.isNotEmpty()) matched++
                            }
                            channelId = null
                        }
                        "programme" -> {
                            inProgramme = false
                            if (start >= 0 && stop > start && stop > fromMs && start < toMs) {
                                // A guide may list programmes for channels it didn't describe first.
                                val keys = channelKeys.getOrPut(progChannel) { matcher.keys(progChannel, emptyList()) }
                                if (keys.isNotEmpty()) {
                                    val program = Program(
                                        title = title?.takeIf { it.isNotEmpty() } ?: "Untitled",
                                        description = desc?.takeIf { it.isNotEmpty() },
                                        startMs = start,
                                        endMs = stop,
                                    )
                                    for (k in keys) into.getOrPut(k) { ArrayList() }.add(program)
                                }
                            }
                        }
                    }
                }
                ev = p.next()
            }
        } catch (_: Exception) {
            // Keep what was read.
        }
        return matched
    }

    /** Sorts each channel's programs and drops overlapping duplicates (two files can cover one channel). */
    fun tidy(guide: Map<String, List<Program>>): Map<String, List<Program>> =
        guide.mapValues { (_, list) ->
            val clean = ArrayList<Program>(list.size)
            for (p in list.sortedBy { it.startMs }) {
                val last = clean.lastOrNull()
                if (last != null && p.startMs < last.endMs) continue
                clean += p
            }
            clean
        }

    // ---- Saved copy ------------------------------------------------------

    private fun clean(s: String) = s.replace('\t', ' ').replace('\n', ' ').replace('\r', ' ')

    /** Simple tab-separated file: fast to write and read on the TV boxes. */
    fun save(file: File, programs: Map<String, List<Program>>, savedAt: Long) {
        val tmp = File(file.parentFile, file.name + ".tmp")
        tmp.bufferedWriter().use { w ->
            w.write(savedAt.toString()); w.newLine()
            for ((key, list) in programs) for (p in list) {
                w.write(key); w.write("\t")
                w.write(p.startMs.toString()); w.write("\t")
                w.write(p.endMs.toString()); w.write("\t")
                w.write(clean(p.title)); w.write("\t")
                w.write(clean(p.description ?: "")); w.newLine()
            }
        }
        tmp.renameTo(file)
    }

    fun load(file: File): Pair<Map<String, List<Program>>, Long>? {
        if (!file.exists()) return null
        return runCatching {
            val out = HashMap<String, MutableList<Program>>()
            var savedAt = 0L
            file.bufferedReader().useLines { lines ->
                lines.forEachIndexed { i, line ->
                    if (i == 0) {
                        savedAt = line.trim().toLongOrNull() ?: 0L
                        return@forEachIndexed
                    }
                    val f = line.split('\t')
                    if (f.size < 5) return@forEachIndexed
                    val start = f[1].toLongOrNull() ?: return@forEachIndexed
                    val end = f[2].toLongOrNull() ?: return@forEachIndexed
                    out.getOrPut(f[0]) { ArrayList() } += Program(f[3], f[4].ifEmpty { null }, start, end)
                }
            }
            out to savedAt
        }.getOrNull()
    }
}
