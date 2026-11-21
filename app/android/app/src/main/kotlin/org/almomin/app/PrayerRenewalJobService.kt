package org.almomin.app

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/** Main-looper-only ownership. There is never a UI and headless scheduling
 * engine concurrently. Android may defer jobs; this is not an exact timer. */
internal object PrayerRenewalCoordinator {
    const val CHANNEL = "almomin/prayer_renewal"
    const val JOB_ID = 17840
    var foreground: MethodChannel? = null
        private set
    var job: PrayerRenewalJobService? = null

    fun attach(engine: FlutterEngine, context: Context) {
        // Finish/destroy the old isolate before allowing UI Dart to start.
        job?.interruptForForeground()
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        foreground = channel
        channel.setMethodCallHandler { call, result ->
            if (call.method == "register") result.success(register(context))
            else result.notImplemented()
        }
    }

    fun detach() {
        foreground?.setMethodCallHandler(null)
        foreground = null
    }

    fun register(context: Context): Boolean {
        val scheduler = context.getSystemService(JobScheduler::class.java)
        // Do not reset the periodic window at every app launch.
        if (scheduler.getPendingJob(JOB_ID) != null) return true
        val request = JobInfo.Builder(JOB_ID,
            ComponentName(context, PrayerRenewalJobService::class.java))
            .setPersisted(true)
            .setPeriodic(6 * 60 * 60 * 1000L)
            .build()
        return scheduler.schedule(request) == JobScheduler.RESULT_SUCCESS
    }
}

class PrayerRenewalJobService : JobService() {
    private val handler = Handler(Looper.getMainLooper())
    private var engine: FlutterEngine? = null
    private var params: JobParameters? = null
    private var generation = 0
    private val timeout = Runnable { finish(false) }

    override fun onStartJob(parameters: JobParameters): Boolean {
        if (params != null) return false
        params = parameters
        generation++
        val ticket = generation
        PrayerRenewalCoordinator.job = this
        handler.postDelayed(timeout, 90_000L)
        // Return immediately to JobScheduler, including before engine loading.
        handler.post {
            if (params == null || generation != ticket) return@post
            try {
                val foreground = PrayerRenewalCoordinator.foreground
                if (foreground != null) {
                    foreground.invokeMethod("renew", null, object : MethodChannel.Result {
                        override fun success(result: Any?) { if (generation == ticket) finish(result == true) }
                        override fun error(code: String, message: String?, details: Any?) { if (generation == ticket) finish(false) }
                        override fun notImplemented() { if (generation == ticket) finish(false) }
                    })
                } else {
                    val loader = FlutterInjector.instance().flutterLoader()
                    loader.startInitialization(applicationContext)
                    loader.ensureInitializationComplete(applicationContext, null)
                    val background = FlutterEngine(applicationContext)
                    engine = background
                    MethodChannel(background.dartExecutor.binaryMessenger,
                        PrayerRenewalCoordinator.CHANNEL).setMethodCallHandler { call, result ->
                        if (call.method == "finish" && generation == ticket) {
                            result.success(null)
                            // Do not destroy the messenger during its reply.
                            handler.post { if (generation == ticket) finish(call.arguments == true) }
                        } else result.notImplemented()
                    }
                    background.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(
                        loader.findAppBundlePath(),
                        "package:almomin/core/notifications/prayer_renewal.dart",
                        "prayerRenewalMain"))
                }
            } catch (_: Exception) { if (generation == ticket) finish(false) }
        }
        return true
    }

    private fun cleanup(): JobParameters? {
        val previous = params
        params = null
        generation++
        handler.removeCallbacks(timeout)
        engine?.destroy()
        engine = null
        if (PrayerRenewalCoordinator.job === this) PrayerRenewalCoordinator.job = null
        return previous
    }

    private fun finish(applied: Boolean) {
        val previous = cleanup() ?: return
        // Periodic jobs remain scheduled; a failure requests Android backoff.
        jobFinished(previous, !applied)
    }

    internal fun interruptForForeground() { finish(false) }

    override fun onStopJob(parameters: JobParameters): Boolean {
        cleanup()
        return true
    }

    override fun onDestroy() {
        cleanup()
        super.onDestroy()
    }
}
