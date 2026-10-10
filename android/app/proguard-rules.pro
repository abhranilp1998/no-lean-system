# R8 keep rules for release builds (Flutter enables R8 for release APKs).

# flutter_local_notifications stores scheduled notifications (risk-window
# alerts, craving recheck) as JSON via Gson and restores them after reboot or
# app update. Without these rules R8 strips the generic type info and the
# restore fails ("Missing type parameter"). Rules from the plugin README and
# google/gson's android-proguard-example.
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod,InnerClasses
-dontwarn sun.misc.**
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}
-keep class com.dexterous.flutterlocalnotifications.models.** { *; }

# native_geofence persists geofence callbacks and re-registers them after
# reboot; keep its models for the same reason.
-keep class com.chunkytofustudios.native_geofence.** { *; }
