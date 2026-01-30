import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
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
      title: 'Nissan Showroom',
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
  Timer? _heartbeatTimer;
  
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
    _startHeartbeat();
  }

  void _startHeartbeat() {
    // Every 300 seconds (5 minutes), trigger a fake interaction
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 300), (timer) {
      _sendHeartbeat();
    });
  }

  Future<void> _sendHeartbeat() async {
    debugPrint('Sending anti-inactivity heartbeat...');
    try {
      // Simulate D-pad Right then Left to trigger activity without changing state/focus
      await _controller.runJavaScript('''
        (function() {
          function dispatchKey(code, key) {
            const event = new KeyboardEvent('keydown', {
              key: key,
              code: key,
              keyCode: code,
              which: code,
              bubbles: true,
              cancelable: true
            });
            document.body.dispatchEvent(event);
            
            // Also dispatch keyup
            const upEvent = new KeyboardEvent('keyup', {
              key: key,
              code: key,
              keyCode: code,
              which: code,
              bubbles: true,
              cancelable: true
            });
            document.body.dispatchEvent(upEvent);
          }

          // D-pad Right (39)
          dispatchKey(39, 'ArrowRight');
          
          // Small delay then D-pad Left (37)
          setTimeout(() => {
            dispatchKey(37, 'ArrowLeft');
          }, 50);
        })();
      ''');
    } catch (e) {
      debugPrint('Failed to send heartbeat: $e');
    }
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
              // Early injection to prevent initial layout shifts
              _controller.runJavaScript('''
                (function() {
                  // Set viewport immediately to prevent shifts
                  let viewport = document.querySelector('meta[name="viewport"]');
                  if (!viewport) {
                    viewport = document.createElement('meta');
                    viewport.name = 'viewport';
                    if (document.head) {
                      document.head.appendChild(viewport);
                    } else {
                      document.addEventListener('DOMContentLoaded', function() {
                        document.head.appendChild(viewport);
                      });
                    }
                  }
                  viewport.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover';
                  
                  // Prevent body shifts
                  if (document.body) {
                    document.body.style.margin = '0';
                    document.body.style.padding = '0';
                    document.body.style.overflow = 'hidden';
                    document.body.style.position = 'fixed';
                    document.body.style.width = '100%';
                    document.body.style.height = '100%';
                  }
                  
                  // Prevent html shifts
                  document.documentElement.style.margin = '0';
                  document.documentElement.style.padding = '0';
                  document.documentElement.style.overflow = 'hidden';
                  document.documentElement.style.width = '100%';
                  document.documentElement.style.height = '100%';
                })();
              ''');
            }
          },
          onPageFinished: (String url) async {
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
              // Inject JavaScript to enable fullscreen and fix rendering issues
              await _injectFullscreenSupport();
            }
          },
          // Handle SSL certificate errors on Android TV
          // This is critical for Android TV devices with older WebView versions
          onSslAuthError: (SslAuthError sslError) async {
            String url = '';
            
            // Get URL from platform-specific properties
            if (sslError.platform is AndroidSslAuthError) {
              final androidError = sslError.platform as AndroidSslAuthError;
              url = androidError.url;
            }
            
            debugPrint('SSL Auth Error detected for: $url');
            
            // Check if it's a trusted domain
            // For Android TV, we'll proceed with all SSL errors since the network security config
            // should handle validation, but older WebViews may still reject valid certificates
            final isTrustedDomain = url.isEmpty || 
                url.contains('nissan.artec.co.in') ||
                url.contains('nissan-cms-uat.artec.co.in') ||
                url.contains('artec.co.in');
            
            if (isTrustedDomain) {
              debugPrint('Proceeding with SSL connection for trusted domain: $url');
              // Proceed with the SSL connection despite the error
              // This is safe for trusted domains in a controlled environment
              await sslError.proceed();
            } else {
              debugPrint('Cancelling SSL connection for untrusted domain: $url');
              // Cancel for untrusted domains
              await sslError.cancel();
            }
          },
          onWebResourceError: (WebResourceError error) {
            // Enhanced error handling for Android TV SSL issues
            final errorCode = error.errorCode;
            final description = error.description.toLowerCase();
            final failingUrl = error.url;
            
            // Check if it's an SSL error for our trusted domains
            final isSSLForTrustedDomain = (errorCode == -202 || // ERR_CERT_AUTHORITY_INVALID
                    description.contains('ssl') ||
                    description.contains('certificate') ||
                    description.contains('handshake')) &&
                (failingUrl?.contains('nissan.artec.co.in') == true ||
                    failingUrl?.contains('nissan-cms-uat.artec.co.in') == true);
            
            if (isSSLForTrustedDomain) {
              debugPrint('SSL error detected for trusted domain: $failingUrl');
              debugPrint('Error code: $errorCode (ERR_CERT_AUTHORITY_INVALID)');
              debugPrint('This is expected on Android TV with older WebView versions.');
              debugPrint('The JavaScript retry mechanism will attempt to recover.');
              
              // Don't treat SSL errors as fatal - let the page continue loading
              // The JavaScript retry logic will handle API call failures
            } else {
              // Log other errors
              final isNonCritical = description.contains('net::err_failed') ||
                  description.contains('timeout') ||
                  description.contains('network') ||
                  errorCode == -1 || // Unknown error
                  errorCode == -2 || // Host lookup failed
                  errorCode == -6;   // Connection timeout
              
              if (!isNonCritical) {
                debugPrint('WebView error: ${error.description}');
                debugPrint('Error code: ${error.errorCode}');
                debugPrint('Error type: ${error.errorType}');
                debugPrint('Failing URL: $failingUrl');
              }
            }
            
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
      
      // Enable media playback without user gesture
      androidController.setMediaPlaybackRequiresUserGesture(false);
      
      // Enable content and file access
      androidController.setAllowContentAccess(true);
      androidController.setAllowFileAccess(true);
      
      // Enable mixed content (HTTP/HTTPS) for better compatibility
      androidController.setMixedContentMode(MixedContentMode.alwaysAllow);
    }
  }

  // Inject JavaScript to enable fullscreen programmatically and fix QR code rendering
  Future<void> _injectFullscreenSupport() async {
    try {
      // Inject multiple times to ensure it works after page loads
      await Future.delayed(const Duration(milliseconds: 500));
      
      await _controller.runJavaScript('''
        (function() {
          // Create a user gesture simulator for fullscreen API
          function simulateUserGesture(callback) {
            // Create a temporary button and click it programmatically
            const btn = document.createElement('button');
            btn.style.display = 'none';
            document.body.appendChild(btn);
            btn.focus();
            btn.click();
            document.body.removeChild(btn);
            
            // Use requestAnimationFrame to ensure gesture is registered
            requestAnimationFrame(() => {
              if (callback) callback();
            });
          }
          
          // Override requestFullscreen to work without user gesture
          const elements = [document.documentElement, document.body];
          elements.forEach(function(element) {
            if (element && element.requestFullscreen) {
              const originalRequestFullscreen = element.requestFullscreen.bind(element);
              element.requestFullscreen = function() {
                return new Promise((resolve, reject) => {
                  simulateUserGesture(() => {
                    try {
                      originalRequestFullscreen().then(resolve).catch(reject);
                    } catch(e) {
                      // Try alternative fullscreen methods
                      try {
                        if (element.webkitRequestFullscreen) {
                          element.webkitRequestFullscreen();
                          resolve();
                        } else if (element.mozRequestFullScreen) {
                          element.mozRequestFullScreen();
                          resolve();
                        } else if (element.msRequestFullscreen) {
                          element.msRequestFullscreen();
                          resolve();
                        } else {
                          reject(e);
                        }
                      } catch(err) {
                        reject(err);
                      }
                    }
                  });
                });
              };
            }
          });
          
          // Override for any element's requestFullscreen
          const originalElementRequestFullscreen = Element.prototype.requestFullscreen;
          if (originalElementRequestFullscreen) {
            Element.prototype.requestFullscreen = function() {
              return new Promise((resolve, reject) => {
                simulateUserGesture(() => {
                  try {
                    originalElementRequestFullscreen.call(this).then(resolve).catch(reject);
                  } catch(e) {
                    // Try webkit/moz/ms alternatives
                    try {
                      if (this.webkitRequestFullscreen) {
                        this.webkitRequestFullscreen();
                        resolve();
                      } else if (this.mozRequestFullScreen) {
                        this.mozRequestFullScreen();
                        resolve();
                      } else if (this.msRequestFullscreen) {
                        this.msRequestFullscreen();
                        resolve();
                      } else {
                        reject(e);
                      }
                    } catch(err) {
                      reject(err);
                    }
                  }
                });
              });
            };
          }
          
          // Enable fullscreen for video elements
          const videos = document.querySelectorAll('video');
          videos.forEach(video => {
            video.setAttribute('playsinline', 'false');
            video.setAttribute('webkit-playsinline', 'false');
            video.setAttribute('x5-playsinline', 'false');
          });
          
          // Fix canvas rendering for QR codes - only fix actual visibility issues
          const canvases = document.querySelectorAll('canvas');
          canvases.forEach(canvas => {
            // Only apply GPU acceleration if needed, don't override existing styles
            const computedStyle = window.getComputedStyle(canvas);
            if (computedStyle.display === 'none') {
              canvas.style.display = '';
            }
            if (computedStyle.visibility === 'hidden') {
              canvas.style.visibility = '';
            }
            if (computedStyle.opacity === '0') {
              canvas.style.opacity = '';
            }
            // Only add GPU acceleration if not already present
            if (!canvas.style.transform) {
              canvas.style.transform = 'translateZ(0)';
            }
          });
          
          // Fix QR code visibility - only fix actual visibility issues without changing design
          function fixQRCodeVisibility() {
            // Look for common QR code selectors
            const qrSelectors = [
              'canvas[data-qr]',
              'canvas.qr-code',
              'div.qr-code canvas',
              'div[class*="qr"] canvas',
              'div[class*="QR"] canvas',
              'img[src*="qr"]',
              'img[alt*="qr" i]',
              'div[class*="qrcode"]',
              'div[class*="QRCode"]'
            ];
            
            qrSelectors.forEach(selector => {
              try {
                const elements = document.querySelectorAll(selector);
                elements.forEach(el => {
                  if (el instanceof HTMLElement) {
                    const computedStyle = window.getComputedStyle(el);
                    // Only fix if actually hidden - don't change visible elements
                    if (computedStyle.display === 'none') {
                      el.style.display = '';
                    }
                    if (computedStyle.visibility === 'hidden') {
                      el.style.visibility = '';
                    }
                    if (computedStyle.opacity === '0') {
                      el.style.opacity = '';
                    }
                    // Remove hidden attribute if present
                    if (el.hasAttribute('hidden')) {
                      el.removeAttribute('hidden');
                    }
                    // Remove hidden class if present
                    if (el.classList.contains('hidden')) {
                      el.classList.remove('hidden');
                    }
                    // Don't override existing styles - only fix visibility
                  }
                });
              } catch(e) {
                // Ignore selector errors
              }
            });
            
            // Check canvas elements - only fix if actually hidden
            document.querySelectorAll('canvas').forEach(canvas => {
              const computedStyle = window.getComputedStyle(canvas);
              const rect = canvas.getBoundingClientRect();
              // Only fix if canvas has dimensions but is hidden
              if (rect.width > 0 && rect.height > 0) {
                if (computedStyle.display === 'none') {
                  canvas.style.display = '';
                }
                if (computedStyle.visibility === 'hidden') {
                  canvas.style.visibility = '';
                }
                if (computedStyle.opacity === '0') {
                  canvas.style.opacity = '';
                }
              }
            });
          }
          
          // Retry failed API calls with proper error handling
          const originalFetch = window.fetch;
          window.fetch = function(...args) {
            return originalFetch.apply(this, args).catch(error => {
              const url = args[0]?.toString() || '';
              // If it's the joining token API and failed, retry after delay
              if (url.includes('getJoiningToken') && url.includes('nissan-cms')) {
                console.warn('API call failed, retrying:', url);
                return new Promise((resolve, reject) => {
                  setTimeout(() => {
                    originalFetch.apply(this, args)
                      .then(resolve)
                      .catch(reject);
                  }, 2000);
                });
              }
              throw error;
            });
          };
          
          // Intercept XMLHttpRequest errors and retry
          const originalXHROpen = XMLHttpRequest.prototype.open;
          const originalXHRSend = XMLHttpRequest.prototype.send;
          
          XMLHttpRequest.prototype.open = function(method, url, ...rest) {
            this._url = url;
            return originalXHROpen.apply(this, [method, url, ...rest]);
          };
          
          XMLHttpRequest.prototype.send = function(...args) {
            const xhr = this;
            const url = xhr._url || '';
            
            // Add error handler for retry logic
            xhr.addEventListener('error', function() {
              if (url.includes('getJoiningToken') && url.includes('nissan-cms')) {
                console.warn('XHR failed, will retry:', url);
                setTimeout(() => {
                  const retryXhr = new XMLHttpRequest();
                  retryXhr.open(xhr._method || 'GET', url);
                  retryXhr.onload = xhr.onload;
                  retryXhr.onerror = xhr.onerror;
                  retryXhr.send(...args);
                }, 2000);
              }
            });
            
            return originalXHRSend.apply(this, args);
          };
          
          // Inject CSS to prevent layout shifts globally
          function injectLayoutFixCSS() {
            const styleId = 'webview-layout-fix';
            if (document.getElementById(styleId)) return;
            
            const style = document.createElement('style');
            style.id = styleId;
            style.textContent = `
              /* Prevent layout shifts globally */
              * {
                box-sizing: border-box !important;
              }
              
              html, body {
                margin: 0 !important;
                padding: 0 !important;
                width: 100% !important;
                height: 100% !important;
                overflow: hidden !important;
                position: fixed !important;
                top: 0 !important;
                left: 0 !important;
                right: 0 !important;
                bottom: 0 !important;
              }
              
              /* Fix iframe layout shifts */
              iframe {
                box-sizing: border-box !important;
                display: block !important;
                overflow: hidden !important;
                position: relative !important;
                margin: 0 !important;
                padding: 0 !important;
                border: none !important;
                contain: layout style paint !important;
                max-width: 100% !important;
                max-height: 100% !important;
              }
              
              /* Fix iframe containers */
              [class*="iframe"], [id*="iframe"], [class*="frame"], [id*="frame"] {
                overflow: hidden !important;
                position: relative !important;
                box-sizing: border-box !important;
              }
              
              /* Prevent content jumping */
              img, video, canvas {
                max-width: 100% !important;
                height: auto !important;
                display: block !important;
              }
            `;
            document.head.appendChild(style);
          }
          
          // Inject CSS first
          injectLayoutFixCSS();
          
          // Fix iframe layout shifting - critical for Android TV WebView
          function fixIframeLayout() {
            // Ensure viewport meta tag exists with proper settings
            let viewport = document.querySelector('meta[name="viewport"]');
            if (!viewport) {
              viewport = document.createElement('meta');
              viewport.name = 'viewport';
              document.head.appendChild(viewport);
            }
            viewport.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover';
            
            // Fix all iframes to prevent layout shifts
            const iframes = document.querySelectorAll('iframe');
            iframes.forEach(iframe => {
              // Prevent layout shifts by setting explicit dimensions
              if (!iframe.hasAttribute('data-layout-fixed')) {
                iframe.setAttribute('data-layout-fixed', 'true');
                
                // Ensure iframe has proper sizing
                if (!iframe.style.width && !iframe.hasAttribute('width')) {
                  iframe.style.width = '100%';
                }
                if (!iframe.style.height && !iframe.hasAttribute('height')) {
                  iframe.style.height = '100%';
                }
                
                // Prevent layout shifts
                iframe.style.boxSizing = 'border-box';
                iframe.style.display = 'block';
                iframe.style.overflow = 'hidden';
                iframe.style.position = 'relative';
                iframe.style.margin = '0';
                iframe.style.padding = '0';
                iframe.style.border = 'none';
                
                // Add CSS containment for better performance
                iframe.style.contain = 'layout style paint';
                
                // Handle iframe load to prevent shifts
                iframe.addEventListener('load', function() {
                  // Force reflow to stabilize layout
                  iframe.offsetHeight;
                  
                  // Ensure parent container doesn't shift
                  const parent = iframe.parentElement;
                  if (parent) {
                    parent.style.overflow = 'hidden';
                    parent.style.position = 'relative';
                    parent.style.width = '100%';
                    parent.style.height = '100%';
                  }
                }, { once: true });
              }
            });
            
            // Fix iframe containers to prevent shifting
            const iframeContainers = document.querySelectorAll('[class*="iframe"], [id*="iframe"], [class*="frame"], [id*="frame"]');
            iframeContainers.forEach(container => {
              if (container.querySelector('iframe')) {
                container.style.overflow = 'hidden';
                container.style.position = 'relative';
                container.style.width = '100%';
                container.style.height = '100%';
                container.style.boxSizing = 'border-box';
              }
            });
          }
          
          // Fix root HTML and body to prevent shifts
          document.documentElement.style.margin = '0';
          document.documentElement.style.padding = '0';
          document.documentElement.style.width = '100%';
          document.documentElement.style.height = '100%';
          document.documentElement.style.overflow = 'hidden';
          
          document.body.style.margin = '0';
          document.body.style.padding = '0';
          document.body.style.width = '100%';
          document.body.style.height = '100%';
          document.body.style.overflow = 'hidden';
          document.body.style.position = 'fixed';
          document.body.style.top = '0';
          document.body.style.left = '0';
          document.body.style.right = '0';
          document.body.style.bottom = '0';
          
          // Improve rendering performance
          document.body.style.willChange = 'auto';
          document.body.style.transform = 'translateZ(0)';
          
          // Initial iframe fix
          fixIframeLayout();
          
          // Watch for dynamically added iframes
          const iframeObserver = new MutationObserver(() => {
            fixIframeLayout();
          });
          
          iframeObserver.observe(document.body, {
            childList: true,
            subtree: true,
            attributes: true,
            attributeFilter: ['style', 'class', 'width', 'height']
          });
          
          // Also check periodically for new iframes
          setInterval(fixIframeLayout, 2000);
          
          // Suppress fullscreen permission errors
          const originalConsoleError = console.error;
          console.error = function(...args) {
            const message = args.join(' ');
            if (!message.includes('requestFullscreen') && 
                !message.includes('Permissions check failed') &&
                !message.includes('user gesture')) {
              originalConsoleError.apply(console, args);
            }
          };
          
          // Initial QR code fix
          fixQRCodeVisibility();
          
          // Watch for dynamically added QR codes - but only fix if actually hidden
          const observer = new MutationObserver((mutations) => {
            let shouldFix = false;
            mutations.forEach(mutation => {
              if (mutation.type === 'attributes') {
                const target = mutation.target;
                if (target instanceof HTMLElement) {
                  const computedStyle = window.getComputedStyle(target);
                  // Only fix if element became hidden
                  if (computedStyle.display === 'none' || 
                      computedStyle.visibility === 'hidden' || 
                      computedStyle.opacity === '0' ||
                      target.hasAttribute('hidden') ||
                      target.classList.contains('hidden')) {
                    shouldFix = true;
                  }
                }
              } else if (mutation.type === 'childList') {
                // Check if new nodes are QR code related
                mutation.addedNodes.forEach(node => {
                  if (node instanceof HTMLElement) {
                    const isQRRelated = node.tagName === 'CANVAS' || 
                                      node.tagName === 'IMG' ||
                                      node.className && (node.className.includes('qr') || node.className.includes('QR')) ||
                                      node.querySelector && (node.querySelector('canvas') || node.querySelector('img[src*="qr" i]'));
                    if (isQRRelated) {
                      shouldFix = true;
                    }
                  }
                });
              }
            });
            // Only fix if something actually became hidden
            if (shouldFix) {
              fixQRCodeVisibility();
            }
          });
          
          observer.observe(document.body, {
            childList: true,
            subtree: true,
            attributes: true,
            attributeFilter: ['style', 'class', 'hidden']
          });
          
          // Only check periodically if needed - reduced frequency and only fix hidden elements
          let lastCheck = Date.now();
          setInterval(() => {
            // Only check every 5 seconds and only if elements might be hidden
            const now = Date.now();
            if (now - lastCheck >= 5000) {
              lastCheck = now;
              // Quick check if any QR elements are hidden
              const hasHiddenQR = document.querySelector('canvas[style*="display: none"], canvas[style*="visibility: hidden"], canvas[hidden], .hidden canvas');
              if (hasHiddenQR) {
                fixQRCodeVisibility();
              }
            }
          }, 5000);
          
          console.log('Fullscreen support and QR code fixes injected');
        })();
      ''');
      
      // Re-inject after a delay to catch dynamically loaded content
      await Future.delayed(const Duration(seconds: 2));
      await _controller.runJavaScript('''
        (function() {
          // Re-apply to any new elements
          const videos = document.querySelectorAll('video');
          videos.forEach(video => {
            if (!video.hasAttribute('data-fullscreen-fixed')) {
              video.setAttribute('playsinline', 'false');
              video.setAttribute('webkit-playsinline', 'false');
              video.setAttribute('data-fullscreen-fixed', 'true');
            }
          });
          
          // Re-fix QR codes - only if actually hidden
          document.querySelectorAll('canvas').forEach(canvas => {
            const computedStyle = window.getComputedStyle(canvas);
            if (computedStyle.display === 'none') {
              canvas.style.display = '';
            }
            if (computedStyle.visibility === 'hidden') {
              canvas.style.visibility = '';
            }
            if (computedStyle.opacity === '0') {
              canvas.style.opacity = '';
            }
            if (canvas.hasAttribute('hidden')) {
              canvas.removeAttribute('hidden');
            }
            if (canvas.classList.contains('hidden')) {
              canvas.classList.remove('hidden');
            }
          });
          
          // Re-fix iframes to prevent layout shifts
          document.querySelectorAll('iframe').forEach(iframe => {
            if (!iframe.hasAttribute('data-layout-fixed')) {
              iframe.setAttribute('data-layout-fixed', 'true');
              iframe.style.boxSizing = 'border-box';
              iframe.style.display = 'block';
              iframe.style.overflow = 'hidden';
              iframe.style.position = 'relative';
              iframe.style.margin = '0';
              iframe.style.padding = '0';
              iframe.style.border = 'none';
              iframe.style.contain = 'layout style paint';
              if (!iframe.style.width) iframe.style.width = '100%';
              if (!iframe.style.height) iframe.style.height = '100%';
            }
          });
        })();
      ''');
      
      // One more injection after 5 seconds for late-loading content
      await Future.delayed(const Duration(seconds: 3));
      await _controller.runJavaScript('''
        (function() {
          // Final QR code visibility check - only fix if actually hidden
          document.querySelectorAll('canvas, img[src*="qr" i], div[class*="qr" i]').forEach(el => {
            if (el instanceof HTMLElement) {
              const computedStyle = window.getComputedStyle(el);
              // Only fix if actually hidden - preserve original design
              if (computedStyle.display === 'none') {
                el.style.display = '';
              }
              if (computedStyle.visibility === 'hidden') {
                el.style.visibility = '';
              }
              if (computedStyle.opacity === '0') {
                el.style.opacity = '';
              }
              if (el.hasAttribute('hidden')) {
                el.removeAttribute('hidden');
              }
              if (el.classList.contains('hidden')) {
                el.classList.remove('hidden');
              }
            }
          });
          
          // Final iframe layout fix
          document.querySelectorAll('iframe').forEach(iframe => {
            iframe.style.boxSizing = 'border-box';
            iframe.style.margin = '0';
            iframe.style.padding = '0';
            iframe.style.border = 'none';
            iframe.style.overflow = 'hidden';
            iframe.style.contain = 'layout style paint';
            const parent = iframe.parentElement;
            if (parent) {
              parent.style.overflow = 'hidden';
              parent.style.position = 'relative';
            }
          });
          
          // Ensure viewport is still correct
          let viewport = document.querySelector('meta[name="viewport"]');
          if (viewport) {
            viewport.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover';
          }
        })();
      ''');
    } catch (e) {
      debugPrint('Error injecting fullscreen support: $e');
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
    _heartbeatTimer?.cancel();
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
