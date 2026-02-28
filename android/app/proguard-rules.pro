# Keep Flutter WebView plugin classes
-keep class io.flutter.plugins.webviewflutter.** { *; }
-keep class io.flutter.plugins.webviewflutter_android.** { *; }
-keep class io.flutter.plugins.webviewflutter_web.** { *; }

# Keep any custom WebView/WebViewClient/WebChromeClient subclasses
-keep class * extends android.webkit.WebViewClient { *; }
-keep class * extends android.webkit.WebChromeClient { *; }

# Keep WebView related classes
-keep class android.webkit.** { *; }

# Suppress warnings for WebView plugins
-dontwarn io.flutter.plugins.webviewflutter.**
-dontwarn io.flutter.plugins.webviewflutter_android.**
-dontwarn io.flutter.plugins.webviewflutter_web.**
