package com.nolean.no_lean

import android.content.Context
import android.content.SharedPreferences
import android.location.Location
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/**
 * App lock configuration pushed from Dart (`buildNativeAppLockConfig`) plus
 * temporary unlock grants. Stored in private SharedPreferences so the
 * service and the boot receiver can run without the Flutter engine.
 * Malformed config reads as disabled: nothing is ever locked by accident.
 */
class AppLockConfig private constructor(
    val enabled: Boolean,
    val packages: Set<String>,
    val labels: Map<String, String>,
    val paymentPackages: Set<String>,
    val neverLockable: Set<String>,
    val schedule: String,
    val windowStart: Int?,
    val windowEnd: Int?,
    val lockInsideDangerZones: Boolean,
    val zones: List<Zone>,
    val hideSensitive: Boolean,
) {
    data class Zone(
        val id: String,
        val name: String,
        val latitude: Double,
        val longitude: Double,
        val radiusMeters: Double,
    )

    val armed: Boolean
        get() = enabled && packages.isNotEmpty() && (schedule != "off" || lockInsideDangerZones)

    /** Mirrors RiskWindow.contains in Dart (end minute inclusive, may wrap). */
    fun scheduleActive(now: Calendar): Boolean {
        val minute = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
        return when (schedule) {
            "always" -> true
            "riskWindow", "custom" -> {
                val start = windowStart ?: return false
                val end = windowEnd ?: return false
                if (end > start) minute in start..end else minute >= start || minute <= end
            }
            else -> false
        }
    }

    fun labelFor(packageName: String): String = labels[packageName] ?: packageName

    companion object {
        const val PREFS = "no_lean_app_lock"
        private const val KEY_CONFIG = "config"
        private const val KEY_GRANTS = "grants"
        const val KEY_PENDING_BLOCKS = "pending_blocks"

        val DISABLED = AppLockConfig(
            false, emptySet(), emptyMap(), emptySet(), emptySet(), "off",
            null, null, false, emptyList(), true,
        )

        fun prefs(context: Context): SharedPreferences =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        fun save(context: Context, json: String): AppLockConfig {
            val config = parse(json)
            prefs(context).edit().putString(KEY_CONFIG, json).apply()
            return config
        }

        fun disable(context: Context) {
            prefs(context).edit().remove(KEY_CONFIG).remove(KEY_GRANTS).apply()
        }

        fun load(context: Context): AppLockConfig =
            prefs(context).getString(KEY_CONFIG, null)?.let { parse(it) } ?: DISABLED

        fun parse(json: String): AppLockConfig = try {
            val root = JSONObject(json)
            fun strings(key: String): Set<String> {
                val array = root.optJSONArray(key) ?: return emptySet()
                return (0 until array.length()).mapNotNull { array.optString(it).takeIf(String::isNotBlank) }.toSet()
            }
            val labels = mutableMapOf<String, String>()
            root.optJSONObject("labels")?.let { obj ->
                obj.keys().forEach { key -> labels[key] = obj.optString(key, key) }
            }
            val zones = mutableListOf<Zone>()
            root.optJSONArray("zones")?.let { array ->
                for (i in 0 until array.length()) {
                    val z = array.optJSONObject(i) ?: continue
                    val radius = z.optDouble("radiusMeters", Double.NaN)
                    val lat = z.optDouble("latitude", Double.NaN)
                    val lng = z.optDouble("longitude", Double.NaN)
                    if (radius.isNaN() || lat.isNaN() || lng.isNaN()) continue
                    zones.add(Zone(z.optString("id"), z.optString("name"), lat, lng, radius))
                }
            }
            fun optInt(key: String): Int? =
                if (root.has(key) && !root.isNull(key)) root.optInt(key, -1).takeIf { it in 0 until 1440 } else null
            AppLockConfig(
                enabled = root.optBoolean("enabled", false),
                packages = strings("packages"),
                labels = labels,
                paymentPackages = strings("paymentPackages"),
                neverLockable = strings("neverLockable"),
                schedule = root.optString("schedule", "off"),
                windowStart = optInt("windowStart"),
                windowEnd = optInt("windowEnd"),
                lockInsideDangerZones = root.optBoolean("lockInsideDangerZones", false),
                zones = zones,
                // Fail private: anything but an explicit false hides details.
                hideSensitive = root.opt("hideSensitive") != false,
            )
        } catch (_: Exception) {
            DISABLED
        }

        // ---- Temporary unlocks ("I need this app"): one app, time-boxed. ----

        fun grant(context: Context, packageName: String, millis: Long) {
            val grants = readGrants(context)
            val now = System.currentTimeMillis()
            grants.keys().asSequence().toList().forEach { if (grants.optLong(it) < now) grants.remove(it) }
            grants.put(packageName, now + millis.coerceIn(0L, 60 * 60 * 1000L))
            prefs(context).edit().putString(KEY_GRANTS, grants.toString()).apply()
        }

        fun isGranted(context: Context, packageName: String, now: Long = System.currentTimeMillis()): Boolean =
            readGrants(context).optLong(packageName, 0L) > now

        private fun readGrants(context: Context): JSONObject = try {
            JSONObject(prefs(context).getString(KEY_GRANTS, "{}") ?: "{}")
        } catch (_: Exception) {
            JSONObject()
        }

        // ---- Block requests handed to Dart (drained by AppLockHost). ----

        fun enqueueBlock(context: Context, request: JSONObject) {
            val pending = try {
                JSONArray(prefs(context).getString(KEY_PENDING_BLOCKS, "[]"))
            } catch (_: Exception) {
                JSONArray()
            }
            pending.put(request)
            val trimmed = JSONArray()
            val from = maxOf(0, pending.length() - 5)
            for (i in from until pending.length()) trimmed.put(pending.get(i))
            prefs(context).edit().putString(KEY_PENDING_BLOCKS, trimmed.toString()).commit()
        }

        fun drainBlocks(context: Context): List<Map<String, Any?>> {
            val prefs = prefs(context)
            val array = try {
                JSONArray(prefs.getString(KEY_PENDING_BLOCKS, "[]"))
            } catch (_: Exception) {
                JSONArray()
            }
            prefs.edit().remove(KEY_PENDING_BLOCKS).commit()
            val now = System.currentTimeMillis()
            val config = load(context)
            return (0 until array.length()).mapNotNull { i ->
                val obj = array.optJSONObject(i) ?: return@mapNotNull null
                // Stale requests (older than 2 minutes) are dropped.
                if (now - obj.optLong("at", 0L) > 2 * 60 * 1000L) return@mapNotNull null
                val packageName = obj.optString("packageName")
                // Re-check device-specific essential apps at handoff time,
                // even if Dart is waiting for a failed/pending policy update.
                // External activity intents only trigger draining; they never
                // supply this private service-validated queue's package data.
                if (AppLockProtected.isProtected(context, packageName, config)) return@mapNotNull null
                mapOf(
                    "packageName" to packageName,
                    "label" to obj.optString("label"),
                    "zoneName" to obj.optString("zoneName").takeIf { it.isNotBlank() },
                    "cause" to obj.optString("cause", "schedule"),
                )
            }
        }

        /** Zone presence with hysteresis, like ZonePresenceTracker in Dart. */
        fun zoneFor(
            zones: List<Zone>,
            location: Location,
            previouslyInside: String?,
            maxAccuracy: Float = 150f,
            exitMargin: Float = 30f,
        ): Zone? {
            val accuracy = if (location.hasAccuracy()) location.accuracy else Float.MAX_VALUE
            val result = FloatArray(1)
            var stay: Zone? = null
            for (zone in zones) {
                Location.distanceBetween(location.latitude, location.longitude, zone.latitude, zone.longitude, result)
                val distance = result[0]
                if (zone.id == previouslyInside &&
                    distance <= zone.radiusMeters + maxOf(accuracy.coerceAtMost(maxAccuracy), exitMargin)
                ) {
                    stay = zone
                }
                if (accuracy <= maxAccuracy && accuracy <= zone.radiusMeters && distance <= zone.radiusMeters) {
                    return zone
                }
            }
            return stay
        }
    }
}
