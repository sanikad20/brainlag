package com.example.flutter_catalog

import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Calendar

class MainActivity : FlutterActivity() {

    private val CHANNEL = "brainlag/usage_access"
    private val PREFS   = "brainlag_prefs"
    private val KEY_INSTALL_DATE = "install_date_ms"

    // ── App categories ────────────────────────────────────────────────────────
    private val socialApps = setOf(
        "com.instagram.android", "com.facebook.katana", "com.twitter.android",
        "com.zhiliaoapp.musically", "com.snapchat.android", "com.reddit.frontpage",
        "com.whatsapp", "org.telegram.messenger", "com.discord",
        "com.facebook.orca", "com.linkedin.android", "com.pinterest",
        "com.tumblr", "com.sharechat.app", "com.moj.app",
        "com.roposo.android", "com.josh.short.video.status.app",
    )
    private val workApps = setOf(
        "com.google.android.gm", "com.microsoft.office.outlook",
        "com.Slack", "us.zoom.videomeetings", "com.microsoft.teams",
        "com.notion.id", "com.google.android.apps.docs",
        "com.google.android.apps.sheets", "com.google.android.calendar",
        "com.github.android", "com.microsoft.office.word",
        "com.microsoft.office.excel", "com.atlassian.android.jira.core",
        "com.figma.mirror", "com.trello",
        "com.google.android.apps.tasks", "com.todoist.android.Todoist",
        "com.evernote", "com.clickup.tasks",
    )
    private val entertainmentApps = setOf(
        "com.google.android.youtube", "com.netflix.mediaclient",
        "com.amazon.avod.thirdpartyclient", "com.hotstar.android",
        "com.disney.disneyplus", "com.spotify.music",
        "com.google.android.apps.youtube.music",
        "in.startv.hotstar", "com.mx.player",
        "com.jio.media.jiocinema", "tv.twitch.android.app",
    )
    private val wellnessApps = setOf(
        "com.headspace.android", "com.calm.android", "com.strava",
        "com.fitbit.FitbitMobile", "com.samsung.android.shealth",
        "com.google.android.apps.fitness", "com.nike.plusgps",
        "com.adidas.runtastic",
    )
    private val excludePackages = setOf(
        "com.android.systemui", "com.android.launcher", "com.android.launcher3",
        "com.miui.home", "com.sec.android.app.launcher",
        "com.oneplus.launcher", "com.google.android.apps.nexuslauncher",
        "com.huawei.android.launcher", "com.oppo.launcher", "com.vivo.launcher",
        "com.android.settings", "com.google.android.inputmethod.latin",
        "com.samsung.android.inputmethod", "android", "com.android.phone",
        "com.google.android.gms", "com.google.android.gsf",
        "com.android.vending", "com.google.android.packageinstaller",
        "com.android.systemui", "com.android.keyguard",
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Save install date on first launch
        saveInstallDateIfFirst()

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {

                "checkUsageAccessPermission" ->
                    result.success(hasUsagePermission())

                "openUsageAccessSettings" -> {
                    startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                    result.success(true)
                }

                // Returns install date as milliseconds since epoch
                "getInstallDate" ->
                    result.success(getInstallDate())

                // Single day usage
                "getDayUsage" -> {
                    val daysAgo = call.argument<Int>("daysAgo") ?: 0
                    if (!hasUsagePermission()) {
                        result.error("NO_PERMISSION", "Usage access not granted", null)
                        return@setMethodCallHandler
                    }
                    result.success(getDayUsageData(daysAgo))
                }

                // Historical usage from install date (up to maxDays)
                "getHistoricalUsage" -> {
                    val maxDays = call.argument<Int>("days") ?: 14
                    if (!hasUsagePermission()) {
                        result.error("NO_PERMISSION", "Usage access not granted", null)
                        return@setMethodCallHandler
                    }

                    // Only fetch days since app was installed
                    val installMs   = getInstallDate()
                    val nowMs       = System.currentTimeMillis()
                    val msPerDay    = 24L * 60 * 60 * 1000
                    val daysSinceInstall = ((nowMs - installMs) / msPerDay).toInt() + 1
                    val daysToFetch = minOf(maxDays, daysSinceInstall)

                    val history = (0 until daysToFetch).map { getDayUsageData(it) }
                    result.success(history)
                }

                // Today's real-time screen time (live, not end-of-day)
                "getTodayScreenTime" -> {
                    if (!hasUsagePermission()) {
                        result.error("NO_PERMISSION", "Usage access not granted", null)
                        return@setMethodCallHandler
                    }
                    result.success(getTodayScreenTimeHours())
                }

                else -> result.notImplemented()
            }
        }
    }

    // ── Save install date once ────────────────────────────────────────────────
    private fun saveInstallDateIfFirst() {
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!prefs.contains(KEY_INSTALL_DATE)) {
            prefs.edit()
                .putLong(KEY_INSTALL_DATE, System.currentTimeMillis())
                .apply()
        }
    }

    private fun getInstallDate(): Long {
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return prefs.getLong(KEY_INSTALL_DATE, System.currentTimeMillis())
    }

    // ── Permission ────────────────────────────────────────────────────────────
    private fun hasUsagePermission(): Boolean {
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val now = System.currentTimeMillis()
        val stats = usm.queryUsageStats(
            UsageStatsManager.INTERVAL_DAILY,
            now - 1000L * 60 * 60 * 24,
            now
        )
        return stats != null && stats.isNotEmpty()
    }

    // ── Today's live screen time ───────────────────────────────────────────────
    private fun getTodayScreenTimeHours(): Double {
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val cal = Calendar.getInstance()
        cal.set(Calendar.HOUR_OF_DAY, 0)
        cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        val startOfDay = cal.timeInMillis
        val now        = System.currentTimeMillis()

        val stats = usm.queryUsageStats(
            UsageStatsManager.INTERVAL_DAILY, startOfDay, now)

        var totalMs = 0L
        stats?.forEach { stat ->
            val pkg = stat.packageName
            if (stat.totalTimeInForeground > 0 && pkg !in excludePackages) {
                totalMs += stat.totalTimeInForeground
            }
        }
        return totalMs / 3_600_000.0
    }

    // ── Core: one day's usage data ────────────────────────────────────────────
    private fun getDayUsageData(daysAgo: Int): Map<String, Any> {
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager

        val cal = Calendar.getInstance()
        cal.add(Calendar.DAY_OF_YEAR, -daysAgo)
        cal.set(Calendar.HOUR_OF_DAY, 0)
        cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        val startTime = cal.timeInMillis

        val endTime = if (daysAgo == 0) {
            System.currentTimeMillis()
        } else {
            val c2 = cal.clone() as Calendar
            c2.add(Calendar.DAY_OF_YEAR, 1)
            c2.timeInMillis
        }

        // Foreground time per app
        val stats = usm.queryUsageStats(
            UsageStatsManager.INTERVAL_DAILY, startTime, endTime)

        var totalMs     = 0L
        var socialMs    = 0L
        var workMs      = 0L
        var entertainMs = 0L
        var wellnessMs  = 0L
        val uniqueApps  = mutableSetOf<String>()

        stats?.forEach { stat ->
            val pkg = stat.packageName
            val ms  = stat.totalTimeInForeground
            if (ms <= 0 || pkg in excludePackages) return@forEach

            totalMs += ms
            uniqueApps.add(pkg)

            when (pkg) {
                in socialApps        -> socialMs    += ms
                in workApps          -> workMs       += ms
                in entertainmentApps -> entertainMs  += ms
                in wellnessApps      -> wellnessMs   += ms
            }
        }

        // App switches from UsageEvents
        var appSwitches       = 0
        var lastForegroundPkg = ""
        try {
            val events = usm.queryEvents(startTime, endTime)
            val event  = UsageEvents.Event()
            while (events.hasNextEvent()) {
                events.getNextEvent(event)
                if (event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND) {
                    val pkg = event.packageName
                    if (pkg !in excludePackages && pkg != lastForegroundPkg) {
                        appSwitches++
                        lastForegroundPkg = pkg
                    }
                }
            }
        } catch (e: Exception) {
            appSwitches = uniqueApps.size * 3
        }

        val totalHours      = totalMs / 3_600_000.0
        val safe            = if (totalMs > 0) totalMs.toDouble() else 1.0
        val hoursInDay      = if (totalHours > 0) totalHours else 1.0
        val switchesPerHour = appSwitches.toDouble() / hoursInDay

        return mapOf(
            "daysAgo"            to daysAgo,
            "screenTimeHours"    to totalHours,
            "appSwitchesPerHour" to switchesPerHour,
            "uniqueAppsPerDay"   to uniqueApps.size,
            "socialAppRatio"     to (socialMs    / safe),
            "workAppRatio"       to (workMs       / safe),
            "entertainmentRatio" to (entertainMs  / safe),
            "wellnessRatio"      to (wellnessMs   / safe),
        )
    }
}