package com.matthewwong525.relay_app

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import com.google.android.gms.location.ActivityRecognition
import com.google.android.gms.location.ActivityTransition
import com.google.android.gms.location.ActivityTransitionRequest
import com.google.android.gms.location.ActivityTransitionResult
import com.google.android.gms.location.DetectedActivity
import org.json.JSONObject
import java.io.File

// Motion for a trip's mode, also with the app closed: one JSON line for each change of the kind of moving, never steps.
// lib/sync/motion.dart reads and empties relay-motion.jsonl at each round.
class ActivityReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (!ActivityTransitionResult.hasResult(intent)) return
        val result = ActivityTransitionResult.extractResult(intent) ?: return
        // The event time is time since boot: this turns it into wall time.
        val bootedAt = System.currentTimeMillis() - SystemClock.elapsedRealtime()
        val lines = StringBuilder()
        for (event in result.transitionEvents) {
            val kind = kinds[event.activityType] ?: continue
            lines.append(JSONObject()
                .put("at", bootedAt + event.elapsedRealTimeNanos / 1_000_000)
                .put("kind", kind)
                .put("sure", true)
                .put("enter", event.transitionType == ActivityTransition.ACTIVITY_TRANSITION_ENTER)
                .toString()).append('\n')
        }
        if (lines.isNotEmpty()) synchronized(ActivityReceiver::class.java) { file(context).appendText(lines.toString()) }
    }

    companion object {
        private val kinds = mapOf(
            DetectedActivity.STILL to "stationary",
            DetectedActivity.WALKING to "walking",
            DetectedActivity.RUNNING to "running",
            DetectedActivity.ON_BICYCLE to "cycling",
            DetectedActivity.IN_VEHICLE to "driving",
        )

        // The Flutter support folder: path_provider's getApplicationSupportDirectory is filesDir on Android.
        fun file(context: Context) = File(context.filesDir, "relay-motion.jsonl")

        private fun intent(context: Context): PendingIntent = PendingIntent.getBroadcast(
            context, 0, Intent(context, ActivityReceiver::class.java),
            // Mutable: Play services adds the result to the intent.
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
        )

        // Starts or stops the changes. Fails without Play services or without the permission: the mode then comes from
        // speed.
        fun watch(context: Context, on: Boolean, done: (Boolean) -> Unit) {
            try {
                val client = ActivityRecognition.getClient(context)
                val task = if (on) {
                    val transitions = kinds.keys.flatMap { type ->
                        listOf(ActivityTransition.ACTIVITY_TRANSITION_ENTER, ActivityTransition.ACTIVITY_TRANSITION_EXIT).map {
                            ActivityTransition.Builder().setActivityType(type).setActivityTransition(it).build()
                        }
                    }
                    client.requestActivityTransitionUpdates(ActivityTransitionRequest(transitions), intent(context))
                } else {
                    client.removeActivityTransitionUpdates(intent(context))
                }
                task.addOnSuccessListener { done(true) }.addOnFailureListener { done(false) }
            } catch (e: SecurityException) {
                done(false)
            } catch (e: RuntimeException) {
                done(false)
            }
        }
    }
}
