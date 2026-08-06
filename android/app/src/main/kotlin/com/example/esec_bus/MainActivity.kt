package com.example.esec_bus

import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "busbuddy/battery"
        ).setMethodCallHandler { call, result ->
            if (call.method != "getBatteryInfo") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val batteryStatus = registerReceiver(
                null,
                IntentFilter(Intent.ACTION_BATTERY_CHANGED)
            )

            if (batteryStatus == null) {
                result.success(null)
                return@setMethodCallHandler
            }

            val level = batteryStatus.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
            val scale = batteryStatus.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
            val status = batteryStatus.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
            val batteryPercent = if (level >= 0 && scale > 0) {
                (level * 100) / scale
            } else {
                -1
            }
            val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                status == BatteryManager.BATTERY_STATUS_FULL

            if (batteryPercent < 0) {
                result.success(null)
            } else {
                result.success(
                    mapOf(
                        "level" to batteryPercent,
                        "isCharging" to isCharging
                    )
                )
            }
        }
    }
}
