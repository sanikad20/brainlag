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

    private val CHANNEL          = "brainlag/usage_access"
    private val PREFS            = "brainlag_prefs"
    private val KEY_INSTALL_DATE = "install_date_ms"

    // ── Social apps ───────────────────────────────────────────────────────────
    private val socialApps = setOf(
        "com.instagram.android", "com.facebook.katana", "com.twitter.android",
        "com.zhiliaoapp.musically", "com.snapchat.android", "com.reddit.frontpage",
        "com.whatsapp", "org.telegram.messenger", "com.discord",
        "com.facebook.orca", "com.linkedin.android", "com.pinterest",
        "com.sharechat.app", "com.moj.app", "com.josh.short.video.status.app",
    )

    // ── Work/productivity apps ────────────────────────────────────────────────
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

    // ── Entertainment apps ────────────────────────────────────────────────────
    private val entertainmentApps = setOf(
        "com.google.android.youtube", "com.netflix.mediaclient",
        "com.amazon.avod.thirdpartyclient", "com.hotstar.android",
        "com.disney.disneyplus", "com.spotify.music",
        "com.google.android.apps.youtube.music",
        "in.startv.hotstar", "com.mx.player",
        "com.jio.media.jiocinema", "tv.twitch.android.app",
    )

    // ── Wellness apps ─────────────────────────────────────────────────────────
    private val wellnessApps = setOf(
        "com.headspace.android", "com.calm.android", "com.strava",
        "com.fitbit.FitbitMobile", "com.samsung.android.shealth",
        "com.google.android.apps.fitness", "com.nike.plusgps",
    )

    // ── System packages to exclude from screen time ───────────────────────────
    private val excludePackages = setOf(
        "com.android.systemui",
        "com.android.launcher", "com.android.launcher2", "com.android.launcher3",
        "com.miui.home", "com.sec.android.app.launcher",
        "com.oneplus.launcher", "com.google.android.apps.nexuslauncher",
        "com.huawei.android.launcher", "com.oppo.launcher",
        "com.vivo.launcher", "com.realme.launcher",
        "com.android.settings",
        "com.google.android.inputmethod.latin",
        "com.samsung.android.inputmethod",
        "com.google.android.gms",
        "com.google.android.gsf",
        "android",
        "com.android.phone",
        "com.android.vending",           // Play Store
        "com.google.android.packageinstaller",
        "com.android.keyguard",
        "com.google.android.setupwizard",
        "com.android.permissioncontroller",
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Record install date on first launch
        recordInstallDate()

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

                "getInstallDate" ->
                    result.success(getInstallDate())

                // Single day — daysAgo: 0 = today, 1 = yesterday
                "getDayUsage" -> {
                    if (!hasUsagePermission()) {
                        result.error("NO_PERMISSION", "Grant usage access", null)
                        return@setMethodCallHandler
                    }
                    val daysAgo = call.argument<Int>("daysAgo") ?: 0
                    result.success(getDayUsage(daysAgo))
                }

                // Last N days from Digital Wellbeing (ignores install date)
                "getHistoricalUsage" -> {
                    if (!hasUsagePermission()) {
                        result.error("NO_PERMISSION", "Grant usage access", null)
                        return@setMethodCallHandler
                    }
                    val days    = call.argument<Int>("days") ?: 7
                    val history = (0 until days).map { getDayUsage(it) }
                    result.success(history)
                }

                // Live screen time for today (real-time)
                "getTodayScreenTime" -> {
                    if (!hasUsagePermission()) {
                        result.error("NO_PERMISSION", "Grant usage access", null)
                        return@setMethodCallHandler
                    }
                    result.success(getTodayLiveScreenTime())
                }

                else -> result.notImplemented()
            }
        }
    }

    // ── Record install date ───────────────────────────────────────────────────
    private fun recordInstallDate() {
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!prefs.contains(KEY_INSTALL_DATE)) {
            prefs.edit().putLong(KEY_INSTALL_DATE, System.currentTimeMillis()).apply()
        }
    }

    private fun getInstallDate(): Long {
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return prefs.getLong(KEY_INSTALL_DATE, System.currentTimeMillis())
    }

    // ── Permission check ──────────────────────────────────────────────────────
    private fun hasUsagePermission(): Boolean {
        val usm  = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val now  = System.currentTimeMillis()
        val list = usm.queryUsageStats(
            UsageStatsManager.INTERVAL_DAILY, now - 86_400_000L, now)
        return list != null && list.isNotEmpty()
    }

    // ── Live today screen time ────────────────────────────────────────────────
// ── Live today screen time ────────────────────────────────────────────────
// Uses UsageEvents to closely match Digital Wellbeing
    private fun getTodayLiveScreenTime(): Double {

        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager

        val cal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }

        val startOfDay = cal.timeInMillis
        val now = System.currentTimeMillis()

        var totalMs = 0L
        var currentPkg: String? = null
        var foregroundStart = 0L

        val events = usm.queryEvents(startOfDay, now)
        val event = UsageEvents.Event()

        while (events.hasNextEvent()) {
            events.getNextEvent(event)

            when (event.eventType) {

                UsageEvents.Event.MOVE_TO_FOREGROUND -> {

                // Close previous app session if any
                    if (currentPkg != null && foregroundStart > 0) {
                        totalMs += event.timeStamp - foregroundStart
                    }

                    if (event.packageName !in excludePackages) {
                        currentPkg = event.packageName
                        foregroundStart = event.timeStamp
                    } else {
                        currentPkg = null
                        foregroundStart = 0L
                    }
                }

                UsageEvents.Event.MOVE_TO_BACKGROUND -> {

                    if (event.packageName == currentPkg &&
                        foregroundStart > 0
                    ) {

                        totalMs += event.timeStamp - foregroundStart

                        currentPkg = null
                        foregroundStart = 0L
                    }
                }
            }
        }

    // Handle app currently in foreground
        if (currentPkg != null && foregroundStart > 0) {
            totalMs += now - foregroundStart
        }

        return Math.round(totalMs / 3_600_000.0 * 10.0) / 10.0
    }

    // ── Core: one calendar day's data ─────────────────────────────────────────
    private fun getDayUsage(daysAgo: Int): Map<String, Any> {
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager

        // ── Time range: midnight → midnight of that day ───────────────────────
        val startCal = Calendar.getInstance().apply {
            add(Calendar.DAY_OF_YEAR, -daysAgo)
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val startMs = startCal.timeInMillis
        val endMs   = if (daysAgo == 0) {
            System.currentTimeMillis()          // today: up to now
        } else {
            startCal.apply {
                add(Calendar.DAY_OF_YEAR, 1)
            }.timeInMillis                      // past day: full 24h
        }

        // ── Foreground time per app ────────────────────────────────────────────
        val stats = usm.queryUsageStats(
            UsageStatsManager.INTERVAL_DAILY, startMs, endMs)

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

        // ── App switches via UsageEvents ───────────────────────────────────────
        // Count MOVE_TO_FOREGROUND events — each unique package switch = 1 switch
        var appSwitches       = 0
        var lastPkg           = ""

        try {
            val events = usm.queryEvents(startMs, endMs)
            val event  = UsageEvents.Event()

            while (events.hasNextEvent()) {
                events.getNextEvent(event)
                if (event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND) {
                    val pkg = event.packageName
                    // Only count if different app and not a system package
                    if (pkg !in excludePackages && pkg != lastPkg) {
                        appSwitches++
                        lastPkg = pkg
                    }
                }
            }
        } catch (e: Exception) {
            // Fallback: estimate from unique apps
            appSwitches = uniqueApps.size * 3
        }

        // ── Compute ratios ─────────────────────────────────────────────────────
        val screenHours     = Math.round(totalMs / 3_600_000.0 * 10.0) / 10.0
        val safe            = if (totalMs > 0) totalMs.toDouble() else 1.0
        val hoursForRate    = if (screenHours > 0) screenHours else 1.0

        // App switches per hour — rounded to whole number
        val switchesPerHour = Math.round(appSwitches.toDouble() / hoursForRate).toInt()

        // Date label for this day
        val dateCal = Calendar.getInstance().apply {
            add(Calendar.DAY_OF_YEAR, -daysAgo)
        }
        val dateLabel = "${dateCal.get(Calendar.DAY_OF_MONTH)}/" +
                        "${dateCal.get(Calendar.MONTH) + 1}"

        return mapOf(
            "daysAgo"            to daysAgo,
            "dateLabel"          to dateLabel,
            "screenTimeHours"    to screenHours,
            "appSwitchesPerHour" to switchesPerHour,   // whole number
            "totalAppSwitches"   to appSwitches,        // raw count
            "uniqueAppsPerDay"   to uniqueApps.size,
            "socialAppRatio"     to Math.round(socialMs    / safe * 1000.0) / 1000.0,
            "workAppRatio"       to Math.round(workMs       / safe * 1000.0) / 1000.0,
            "entertainmentRatio" to Math.round(entertainMs  / safe * 1000.0) / 1000.0,
            "wellnessRatio"      to Math.round(wellnessMs   / safe * 1000.0) / 1000.0,
        )
    }
}