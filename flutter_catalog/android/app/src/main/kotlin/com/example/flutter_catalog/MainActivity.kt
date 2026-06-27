package com.example.flutter_catalog

import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
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
    // NOTE: Voice Recorder, NetMirror, browser etc. are intentionally NOT here —
    // Samsung Digital Wellbeing counts them and so should we.
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
        "com.android.vending",
        "com.google.android.packageinstaller",
        "com.android.keyguard",
        "com.google.android.setupwizard",
        "com.android.permissioncontroller",
        "com.android.camera",
        "com.miui.gallery",
        "com.google.android.apps.photos",
        "com.google.android.googlequicksearchbox"
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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

                "getDayUsage" -> {
                    if (!hasUsagePermission()) {
                        result.error("NO_PERMISSION", "Grant usage access", null)
                        return@setMethodCallHandler
                    }
                    val daysAgo = call.argument<Int>("daysAgo") ?: 0
                    result.success(getDayUsage(daysAgo))
                }

                "getHistoricalUsage" -> {
                    if (!hasUsagePermission()) {
                        result.error("NO_PERMISSION", "Grant usage access", null)
                        return@setMethodCallHandler
                    }
                    val days    = call.argument<Int>("days") ?: 7
                    val history = (0 until days).map { getDayUsage(it) }
                    result.success(history)
                }

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

    // ── Reusable: event-based foreground time calculator ─────────────────────
    //
    // Three fixes vs the previous version:
    //
    // FIX 1 — "Already-open app at window start":
    //   If an app was brought to foreground BEFORE startMs and never sent a
    //   BACKGROUND event within the window, the previous code missed its time
    //   entirely for this window. We now detect this using queryUsageStats:
    //   if an app has lastTimeUsed < startMs but no FOREGROUND event in the
    //   window, we seed it as foreground from startMs.
    //
    // FIX 2 — SCREEN_NON_INTERACTIVE as session boundary:
    //   Samsung Digital Wellbeing pauses an app's foreground time when the
    //   screen turns off. We now listen for SCREEN_NON_INTERACTIVE and treat
    //   it as an implicit BACKGROUND for the current app, then resume on
    //   SCREEN_INTERACTIVE. This matches Samsung's counting behaviour and
    //   fixes gaps caused by long phone-down sessions.
    //
    // FIX 3 — Hybrid fallback for old days (>7 days):
    //   Samsung's UsageEvents store is typically pruned after ~7 days.
    //   For windows older than 7 days, queryEvents() returns very sparse
    //   data. We detect this (< 5 foreground events) and fall back to
    //   totalTimeInForeground with a 0.65 correction factor to approximate
    //   the event-based result. 0.65 is empirically chosen to cancel out
    //   the Samsung double-counting inflation (~1.5–1.6x overcounting).
    //
    private fun calculateScreenTimeFromEvents(startMs: Long, endMs: Long): Long {
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager

        // ── FIX 3: Sparse-data guard ──────────────────────────────────────────
        // If window is older than 7 days, events are likely pruned — fall back
        val windowAgeMs   = System.currentTimeMillis() - startMs
        val sevenDaysMs   = 7L * 24 * 60 * 60 * 1000
        val isTooOld      = windowAgeMs > sevenDaysMs

        if (isTooOld) {
            // Use corrected totalTimeInForeground as fallback
            val stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, startMs, endMs)
            var rawMs = 0L
            stats?.forEach { stat ->
                val pkg = stat.packageName
                val ms  = stat.totalTimeInForeground
                if (ms > 0 && pkg !in excludePackages) rawMs += ms
            }
            // 0.65 correction: Samsung totalTimeInForeground overcounts by ~1.5x
            val correctedMs = (rawMs * 0.65).toLong()
            println("Day (old>7d fallback): startMs=$startMs rawMs=${rawMs/3600000.0} correctedMs=${correctedMs/3600000.0}")
            return correctedMs
        }

        // ── FIX 1: Detect already-open app at window start ────────────────────
        // queryUsageStats gives us lastTimeUsed. If an app's lastTimeUsed is
        // within a short window before startMs, it was likely still open at
        // startMs. We'll handle it by seeding it into our state machine below.
        val statsForSeed = usm.queryUsageStats(
            UsageStatsManager.INTERVAL_DAILY,
            startMs - 60_000L,   // look back 1 min before window
            startMs + 1_000L     // just past the window start
        )
        var seededPkg: String? = null
        var seededStart = startMs
        // Find an app that was "last used" right before our window — likely open
        statsForSeed?.forEach { stat ->
            val pkg = stat.packageName
            if (pkg !in excludePackages &&
                stat.lastTimeUsed in (startMs - 60_000L) until startMs) {
                // This app was active just before our window — assume it carries over
                seededPkg   = pkg
                seededStart = startMs
            }
        }

        var totalMs        = 0L
        var currentPkg     = seededPkg          // FIX 1: pre-seed
        var foregroundStart = seededStart        // FIX 1: start from window open
        var screenOn       = true                // assume screen starts on

        val events = usm.queryEvents(startMs, endMs)
        val event  = UsageEvents.Event()
        var fgEventCount = 0

        while (events.hasNextEvent()) {
            events.getNextEvent(event)

            when (event.eventType) {

                // ── FIX 2: Screen off = pause current app's timer ─────────────
                UsageEvents.Event.SCREEN_NON_INTERACTIVE -> {
                    if (screenOn && currentPkg != null && foregroundStart > 0) {
                        totalMs += event.timeStamp - foregroundStart
                        // Don't clear currentPkg — we'll resume on SCREEN_INTERACTIVE
                        foregroundStart = 0L
                    }
                    screenOn = false
                }

                // ── FIX 2: Screen on = resume current app's timer ─────────────
                UsageEvents.Event.SCREEN_INTERACTIVE -> {
                    if (!screenOn && currentPkg != null) {
                        // Screen came back on with same app still "current"
                        foregroundStart = event.timeStamp
                    }
                    screenOn = true
                }

                UsageEvents.Event.MOVE_TO_FOREGROUND -> {
                    fgEventCount++
                    // Close previous session (handles missed BACKGROUND or screen-off gaps)
                    if (currentPkg != null && foregroundStart > 0 && screenOn) {
                        totalMs += event.timeStamp - foregroundStart
                    }
                    if (event.packageName !in excludePackages) {
                        currentPkg      = event.packageName
                        foregroundStart = if (screenOn) event.timeStamp else 0L
                    } else {
                        currentPkg      = null
                        foregroundStart = 0L
                    }
                }

                UsageEvents.Event.MOVE_TO_BACKGROUND -> {
                    if (event.packageName == currentPkg && foregroundStart > 0) {
                        totalMs        += event.timeStamp - foregroundStart
                        currentPkg      = null
                        foregroundStart = 0L
                    }
                }
            }
        }

        // ── FIX 3 (inline): sparse event check — too few events = stale data ──
        // If this is within 7 days but we got almost no events, fall back
        if (fgEventCount < 5) {
            println("Warning: only $fgEventCount FG events for window $startMs-$endMs, using corrected fallback")
            val stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, startMs, endMs)
            var rawMs = 0L
            stats?.forEach { stat ->
                val pkg = stat.packageName
                val ms  = stat.totalTimeInForeground
                if (ms > 0 && pkg !in excludePackages) rawMs += ms
            }
            return (rawMs * 0.65).toLong()
        }

        // Handle app still in foreground at end of window
        if (currentPkg != null && foregroundStart > 0 && screenOn) {
            totalMs += endMs - foregroundStart
        }

        return totalMs
    }

    // ── Live today screen time ────────────────────────────────────────────────
    private fun getTodayLiveScreenTime(): Double {
        val cal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val startOfDay = cal.timeInMillis
        val now        = System.currentTimeMillis()
        val totalMs    = calculateScreenTimeFromEvents(startOfDay, now)
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
            System.currentTimeMillis()
        } else {
            startCal.apply { add(Calendar.DAY_OF_YEAR, 1) }.timeInMillis
        }

        // ── Screen time: event-based (matches Digital Wellbeing) ──────────────
        val totalMs = calculateScreenTimeFromEvents(startMs, endMs)

        // ── Category breakdown + unique apps: still from queryUsageStats() ─────
        // totalTimeInForeground used ONLY for relative category weighting,
        // never added into the overall totalMs total.
        val stats = usm.queryUsageStats(
            UsageStatsManager.INTERVAL_DAILY, startMs, endMs)

        var socialMs    = 0L
        var workMs      = 0L
        var entertainMs = 0L
        var wellnessMs  = 0L
        val uniqueApps  = mutableSetOf<String>()

        stats?.forEach { stat ->
            val pkg = stat.packageName
            val ms  = stat.totalTimeInForeground
            if (ms <= 0 || pkg in excludePackages) return@forEach
            uniqueApps.add(pkg)
            when (pkg) {
                in socialApps        -> socialMs    += ms
                in workApps          -> workMs       += ms
                in entertainmentApps -> entertainMs  += ms
                in wellnessApps      -> wellnessMs   += ms
            }
        }

        // ── App switches via UsageEvents ───────────────────────────────────────
        var appSwitches = 0
        var lastPkg     = ""
        try {
            val events = usm.queryEvents(startMs, endMs)
            val event  = UsageEvents.Event()
            while (events.hasNextEvent()) {
                events.getNextEvent(event)
                if (event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND) {
                    val pkg = event.packageName
                    if (pkg !in excludePackages && pkg != lastPkg) {
                        appSwitches++
                        lastPkg = pkg
                    }
                }
            }
        } catch (e: Exception) {
            appSwitches = uniqueApps.size * 3
        }

        // ── Compute ratios ─────────────────────────────────────────────────────
        val screenHours     = Math.round(totalMs / 3_600_000.0 * 10.0) / 10.0
        val safe            = if (totalMs > 0) totalMs.toDouble() else 1.0
        val hoursForRate    = if (screenHours > 0) screenHours else 1.0
        val switchesPerHour = Math.round(appSwitches.toDouble() / hoursForRate).toInt()

        val dateCal = Calendar.getInstance().apply {
            add(Calendar.DAY_OF_YEAR, -daysAgo)
        }
        val dateLabel = "${dateCal.get(Calendar.DAY_OF_MONTH)}/" +
                        "${dateCal.get(Calendar.MONTH) + 1}"

        // ── Debug logging ──────────────────────────────────────────────────────
        println("Day=$daysAgo ScreenHours=$screenHours Switches=$appSwitches Apps=${uniqueApps.size}")

        return mapOf(
            "daysAgo"            to daysAgo,
            "dateLabel"          to dateLabel,
            "screenTimeHours"    to screenHours,
            "appSwitchesPerHour" to switchesPerHour,
            "totalAppSwitches"   to appSwitches,
            "uniqueAppsPerDay"   to uniqueApps.size,
            "socialAppRatio"     to Math.round(socialMs    / safe * 1000.0) / 1000.0,
            "workAppRatio"       to Math.round(workMs       / safe * 1000.0) / 1000.0,
            "entertainmentRatio" to Math.round(entertainMs  / safe * 1000.0) / 1000.0,
            "wellnessRatio"      to Math.round(wellnessMs   / safe * 1000.0) / 1000.0,
        )
    }
}