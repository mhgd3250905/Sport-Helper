# Backport the shared_preferences_android 2.5.2 consumer JNI rules without
# changing the existing storage backend or upgrading DataStore.
# https://github.com/flutter/packages/blob/shared_preferences_android-v2.5.2/packages/shared_preferences/shared_preferences_android/android/consumer-rules.pro
# package:jni looks these Kotlin types/members up by fixed names. Pigeon keeps
# its generated registrars, but their method descriptors break if R8 renames
# Continuation (and Kotlin result/coroutine helpers).
-keep class kotlin.Unit { *; }
-keep class kotlin.Result { *; }
-keep class kotlin.Result$Failure { *; }
-keep class kotlin.coroutines.Continuation { *; }
-keep class kotlin.coroutines.intrinsics.CoroutineSingletons { *; }
-keep class kotlin.coroutines.intrinsics.IntrinsicsKt { *; }
