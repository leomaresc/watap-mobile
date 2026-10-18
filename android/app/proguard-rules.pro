# Reglas de ProGuard/R8 para WATAP Mobile.
#
# Flutter y los plugins utilizados no necesitan reglas especiales en la
# mayoría de los casos; las incluidas aquí evitan que R8 elimine clases a las
# que se accede por reflexión desde los plugins nativos.

# Flutter embedding
-keep class io.flutter.** { *; }
-dontwarn io.flutter.embedding.**

# flutter_secure_storage usa la API de seguridad de Android.
-keep class androidx.security.crypto.** { *; }

# Conserva las anotaciones que R8 necesita para los modelos de AndroidX.
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod

# Evita avisos de dependencias opcionales no presentes.
-dontwarn org.bouncycastle.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**
