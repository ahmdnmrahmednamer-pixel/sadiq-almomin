package org.almomin.app

import android.app.NotificationManager
import android.os.Bundle
import android.os.Build
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "almomin/volume_tasbih"
    private var volumeChannel: MethodChannel? = null
    private var interceptVolumeUp: Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        PrayerRenewalCoordinator.job?.interruptForForeground()
        super.onCreate(savedInstanceState)
    }

    override fun onDestroy() {
        PrayerRenewalCoordinator.job?.interruptForForeground()
        PrayerRenewalCoordinator.detach()
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        PrayerRenewalCoordinator.attach(flutterEngine, applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "almomin/adhan_permissions")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canUseFullScreenIntent" -> {
                        val allowed = if (Build.VERSION.SDK_INT >= 34) {
                            getSystemService(NotificationManager::class.java).canUseFullScreenIntent()
                        } else {
                            true
                        }
                        result.success(allowed)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "almomin/active_prayer_alert")
            .setMethodCallHandler { call, result ->
                val manager = getSystemService(NotificationManager::class.java)
                val id = call.argument<Number>("id")?.toInt()
                if (id == null || !(id in 100..399 || id in listOf(995, 998, 999))) {
                    result.error("invalid_identity", "Notification ID required", null)
                    return@setMethodCallHandler
                }
                try {
                    // These app notifications have no tag. Never touch an alarm
                    // PendingIntent or the notification plugin's future cache.
                    val active = manager.activeNotifications.firstOrNull { it.id == id && it.tag == null }
                    when (call.method) {
                        "capture" -> result.success(active?.let {
                            mapOf("id" to it.id, "key" to it.key, "postTime" to it.postTime)
                        })
                        "stopCaptured" -> {
                            val key = call.argument<String>("key")
                            val postTime = call.argument<Number>("postTime")?.toLong()
                            if (key == null || postTime == null) {
                                result.error("invalid_identity", "Captured instance required", null)
                            } else if (active == null) {
                                result.success("gone")
                            } else if (active.key != key || active.postTime != postTime) {
                                result.success("replaced")
                            } else {
                                manager.cancel(active.tag, active.id)
                                result.success("stopped")
                            }
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("active_alert_unavailable", "Could not access active notification", null)
                }
            }
        volumeChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        volumeChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "setVolumeInterception" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    interceptVolumeUp = enabled
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (interceptVolumeUp && keyCode == KeyEvent.KEYCODE_VOLUME_UP) {
            if (event == null || event.repeatCount == 0) {
                volumeChannel?.invokeMethod("onVolumeUpPressed", null)
            }
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent?): Boolean {
        if (interceptVolumeUp && keyCode == KeyEvent.KEYCODE_VOLUME_UP) {
            return true
        }
        return super.onKeyUp(keyCode, event)
    }
}
