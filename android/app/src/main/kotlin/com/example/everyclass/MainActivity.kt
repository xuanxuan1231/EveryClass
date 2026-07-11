package com.example.everyclass

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private val notifChannel = "everyclass/live_notification"
    private val ioChannel = "everyclass/io"
    private val reqPickJson = 42

    private var pendingPick: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, notifChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        ensureNotificationPermission()
                        @Suppress("UNCHECKED_CAST")
                        val lessons = call.argument<List<Map<String, Any?>>>("lessons")
                        val enhanced = call.argument<Boolean>("enhancedCountdown") ?: false
                        val intent = Intent(this, ScheduleForegroundService::class.java).apply {
                            action = ScheduleForegroundService.ACTION_START
                            putExtra(ScheduleForegroundService.EXTRA_LESSONS, lessonsToJson(lessons))
                            putExtra(ScheduleForegroundService.EXTRA_ENHANCED, enhanced)
                        }
                        ContextCompat.startForegroundService(this, intent)
                        result.success(null)
                    }
                    "stop" -> {
                        val intent = Intent(this, ScheduleForegroundService::class.java).apply {
                            action = ScheduleForegroundService.ACTION_STOP
                        }
                        startService(intent)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ioChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickJson" -> {
                        if (pendingPick != null) {
                            result.error("busy", "已有一个选择中的文件", null)
                            return@setMethodCallHandler
                        }
                        pendingPick = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            // 部分文件管理器不把 .json 标为 application/json，用 */* 更稳。
                            type = "*/*"
                        }
                        startActivityForResult(intent, reqPickJson)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != reqPickJson) return
        val result = pendingPick
        pendingPick = null
        val uri = data?.data
        if (resultCode == RESULT_OK && uri != null) {
            try {
                val text = contentResolver.openInputStream(uri)
                    ?.bufferedReader()
                    ?.use { it.readText() }
                result?.success(text)
            } catch (e: Exception) {
                result?.error("read_failed", e.message, null)
            }
        } else {
            result?.success(null) // 用户取消
        }
    }

    private fun ensureNotificationPermission() {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                1001,
            )
        }
    }

    private fun lessonsToJson(lessons: List<Map<String, Any?>>?): String {
        val arr = JSONArray()
        lessons?.forEach { m ->
            arr.put(
                JSONObject().apply {
                    put("subject", m["subject"] ?: "")
                    put("room", m["room"] ?: "")
                    put("teacher", m["teacher"] ?: "")
                    put("period", (m["period"] as? Number)?.toInt() ?: 0)
                    put("startMs", (m["startMs"] as? Number)?.toLong() ?: 0L)
                    put("endMs", (m["endMs"] as? Number)?.toLong() ?: 0L)
                },
            )
        }
        return arr.toString()
    }
}
