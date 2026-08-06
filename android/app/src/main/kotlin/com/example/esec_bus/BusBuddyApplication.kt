package com.example.esec_bus

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build

class BusBuddyApplication : Application() {
    override fun onCreate() {
        super.onCreate()

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val notificationManager = getSystemService(NotificationManager::class.java)
        val channels = listOf(
            NotificationChannel(
                "FOREGROUND_DEFAULT",
                "Live bus tracking",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows while a driver is sharing the bus location."
                setSound(null, null)
                enableVibration(false)
            },
            NotificationChannel(
                "bus_tracking",
                "Live bus tracking (legacy)",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Compatibility channel for existing installations."
                setSound(null, null)
                enableVibration(false)
            }
        )

        notificationManager.createNotificationChannels(channels)
    }
}
