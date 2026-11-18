package com.inskribed.tvapp.data

/**
 * Channel search that matches whole words, so "|us|" finds "|US| CBS 2" but not "Museum"
 * or "Business". Same rules as the iPhone app (ios/OrkaCore/.../ChannelSearch.swift).
 */
object ChannelSearch {

    /** "|US| ESPN 2 HD+" -> [us, espn, 2, hd, plus] */
    fun words(s: String): List<String> = ChannelMatcher.tokenize(s)

    /** Every query word must be the start of a word in the name. */
    fun matches(nameWords: List<String>, query: List<String>): Boolean =
        query.isNotEmpty() && query.all { q -> nameWords.any { it.startsWith(q) } }

    /** The name begins with the query's words in order ("us cbs" ranks "|US| CBS 2" first). */
    fun startsWith(nameWords: List<String>, query: List<String>): Boolean =
        query.size <= nameWords.size && query.indices.all { nameWords[it].startsWith(query[it]) }

    /**
     * Indexes of matching names, best first. Falls back to matching inside words only when
     * nothing matches whole words, so squashed names like "ESPNews" are still found.
     */
    fun search(query: String, words: List<List<String>>, squashed: List<String>, limit: Int = 300): List<Int> {
        val q = words(query)
        if (q.isEmpty()) return emptyList()
        val first = ArrayList<Int>()
        val rest = ArrayList<Int>()
        for (i in words.indices) {
            val w = words[i]
            if (startsWith(w, q)) first += i else if (matches(w, q)) rest += i
            if (first.size >= limit) break
        }
        if (first.isEmpty() && rest.isEmpty()) {
            val s = ChannelMatcher.normalize(query)
            if (s.length < 3) return emptyList()
            return squashed.indices.filter { squashed[it].contains(s) }.take(limit)
        }
        return (first + rest).take(limit)
    }

    /** "|US| SPORTS" -> "US", "FR: Cinema" -> "FR", "UK - News" -> "UK"; null without such a tag. */
    fun groupPrefix(name: String): String? {
        var s = name.trim()
        while (s.isNotEmpty() && s[0] in "|[(") s = s.substring(1)
        val tag = s.takeWhile { it.isLetterOrDigit() }
        if (tag.length !in 2..4) return null
        val rest = s.substring(tag.length).trimStart(' ')
        if (rest.isEmpty() || rest[0] !in "|:])-") return null
        return tag.uppercase()
    }
}
