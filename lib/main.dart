import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
// Import for Android features
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Hide system bars for immersive experience
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Honda Showroom',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const ShowroomPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class ShowroomPage extends StatefulWidget {
  const ShowroomPage({super.key});

  @override
  State<ShowroomPage> createState() => _ShowroomPageState();
}

class _ShowroomPageState extends State<ShowroomPage> {
  late final WebViewController _controller;
  final FocusNode _focusNode = FocusNode();
  bool _isLoading = true;
  
  // Constants
  static const String _honda3dUrl = 'https://nissan.artec.co.in/nissan-magnite/#/car/stream/magnite';
  // Desktop User Agent for better TV compatibility
  static const String _userAgent = 
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  @override
  void initState() {
    super.initState();
    _enableWakelock();
    _initWebViewController();
  }

  Future<void> _enableWakelock() async {
    // Keep the screen on indefinitely for the showroom display
    await WakelockPlus.enable();
  }

  void _initWebViewController() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(_userAgent)
      ..setBackgroundColor(const Color(0xFF000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            // Optional: Update loading bar.
            debugPrint('WebView loading: $progress%');
          },
          onPageStarted: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = true;
              });
            }
          },
          onPageFinished: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('WebView error: ${error.description}');
            if (mounted) {
               setState(() {
                 _isLoading = false;
               });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(_honda3dUrl));
      
    // Android-specific configuration
    if (_controller.platform is AndroidWebViewController) {
      final AndroidWebViewController androidController =
          _controller.platform as AndroidWebViewController;
      androidController.setMediaPlaybackRequiresUserGesture(false);
      androidController.setAllowContentAccess(true);
      androidController.setAllowFileAccess(true);
    }
  }

  // This function maps the Remote OK button to the HTML button click
void _handleRemoteClick() {
    debugPrint("Remote OK Pressed - Triggering JS");
    _controller.runJavaScript("""
      (function() {
        var btn = document.getElementById('testBtnKiosk');
        if (btn) {
          // 1. Visually focus
          btn.focus();

          // 2. Create a simulated Mouse/Touch event (More reliable than .click())
          var event = new MouseEvent('click', {
            'view': window,
            'bubbles': true,
            'cancelable': true
          });
          btn.dispatchEvent(event);

          console.log('Kiosk Button Dispatched successfully');
        } else {
          console.error('Button not found');
        }
      })();
    """);
  }

  @override
  void dispose() {
    // Release wakelock when the widget is disposed
    WakelockPlus.disable();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          CallbackShortcuts(
              bindings: {
                // Detect physical "Select/OK" or "Enter" keys from the remote
                const SingleActivator(LogicalKeyboardKey.select): _handleRemoteClick,
                const SingleActivator(LogicalKeyboardKey.enter): _handleRemoteClick,
              },
              child: Focus(
                focusNode: _focusNode,
                autofocus: true,
                child: WebViewWidget(controller: _controller),
              ),
            ),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(
                color: Colors.white,
              ),
            ),
        ],
      ),
    );
  }
}
