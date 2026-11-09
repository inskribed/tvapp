package com.inskribed.tvapp.data

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.core.content.FileProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.io.File
import java.io.IOException

private const val LATEST_RELEASE_URL = "https://api.github.com/repos/inskribed/tvapp/releases/latest"
private const val APK_NAME = "tvapp.apk"

data class UpdateInfo(
    /** Matches versionCode: CI uses the build number for both the tag (v0.1.N) and versionCode (N). */
    val versionCode: Int,
    val versionName: String,
    val apkUrl: String,
    val notes: String,
)

/** Checks GitHub for a newer build, downloads it, and hands it to Android's installer. */
class Updater(private val context: Context, private val http: OkHttpClient) {

    suspend fun latest(): UpdateInfo? = withContext(Dispatchers.IO) {
        val req = Request.Builder()
            .url(LATEST_RELEASE_URL)
            .header("Accept", "application/vnd.github+json")
            .header("User-Agent", USER_AGENT)
            .build()
        val body = http.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) throw IOException("GitHub returned HTTP ${resp.code}")
            resp.body?.string() ?: throw IOException("Empty response from GitHub")
        }
        val o = JSONObject(body)
        val tag = o.optString("tag_name")
        val code = tag.substringAfterLast('.').toIntOrNull() ?: return@withContext null
        val assets = o.optJSONArray("assets") ?: return@withContext null
        var url: String? = null
        for (i in 0 until assets.length()) {
            val a = assets.optJSONObject(i) ?: continue
            if (a.optString("name") == APK_NAME) url = a.optString("browser_download_url")
        }
        if (url.isNullOrBlank()) return@withContext null
        UpdateInfo(
            versionCode = code,
            versionName = tag.removePrefix("v"),
            apkUrl = url,
            notes = o.optString("body").trim(),
        )
    }

    suspend fun download(info: UpdateInfo, onProgress: (Float) -> Unit): File = withContext(Dispatchers.IO) {
        val dir = File(context.cacheDir, "updates").apply { mkdirs() }
        val out = File(dir, APK_NAME)
        val part = File(dir, "$APK_NAME.part")
        val req = Request.Builder().url(info.apkUrl).header("User-Agent", USER_AGENT).build()
        http.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) throw IOException("Download failed (HTTP ${resp.code})")
            val body = resp.body ?: throw IOException("Empty download")
            val total = body.contentLength()
            var done = 0L
            var lastPct = -1
            body.byteStream().use { input ->
                part.outputStream().use { output ->
                    val buf = ByteArray(64 * 1024)
                    while (true) {
                        ensureActive()
                        val n = input.read(buf)
                        if (n < 0) break
                        output.write(buf, 0, n)
                        done += n
                        if (total > 0) {
                            val pct = (done * 100 / total).toInt()
                            if (pct != lastPct) {
                                lastPct = pct
                                onProgress(pct / 100f)
                            }
                        }
                    }
                }
            }
        }
        out.delete()
        if (!part.renameTo(out)) throw IOException("Couldn't save the update")
        out
    }

    /** Android asks once per app before it may install updates ("unknown sources"). */
    fun canInstall(): Boolean = context.packageManager.canRequestPackageInstalls()

    /** Opens the system screen where Remo can be allowed to install apps. False if the TV has no such screen. */
    fun openInstallPermission(): Boolean = try {
        context.startActivity(
            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${context.packageName}"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        true
    } catch (_: Exception) {
        false
    }

    fun install(file: File) {
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", file)
        context.startActivity(
            Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }
}
