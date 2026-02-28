package com.artec.nissan_showroom_tv

import android.net.http.SslError
import android.webkit.SslErrorHandler
import android.webkit.WebView
import android.webkit.WebViewClient
import android.util.Log

/**
 * Custom WebViewClient that handles SSL certificate errors on Android TV
 * This is necessary because Android TV WebViews often have older certificate stores
 * and may reject valid certificates that work fine in desktop browsers
 */
class SSLWebViewClient : WebViewClient() {
    
    companion object {
        private const val TAG = "SSLWebViewClient"
        // Domains that we trust even if SSL validation fails
        // Only use this for domains you control or trust
        private val TRUSTED_DOMAINS = listOf(
            "nissan.artec.co.in",
            "nissan-cms-uat.artec.co.in",
            "artec.co.in"
        )
    }
    
    override fun onReceivedSslError(
        view: WebView?,
        handler: SslErrorHandler?,
        error: SslError?
    ) {
        val url = error?.url ?: ""
        val host = try {
            java.net.URL(url).host
        } catch (e: Exception) {
            ""
        }
        
        // Check if the domain is in our trusted list
        val isTrustedDomain = TRUSTED_DOMAINS.any { trustedDomain ->
            host.contains(trustedDomain, ignoreCase = true)
        }
        
        if (isTrustedDomain) {
            Log.w(TAG, "SSL error for trusted domain $host: ${error?.toString()}")
            Log.w(TAG, "Proceeding with SSL connection despite error")
            // Proceed with the SSL connection
            handler?.proceed()
        } else {
            Log.e(TAG, "SSL error for untrusted domain $host: ${error?.toString()}")
            // For untrusted domains, use default behavior (cancel)
            handler?.cancel()
        }
    }
    
    override fun onReceivedError(
        view: WebView?,
        errorCode: Int,
        description: String?,
        failingUrl: String?
    ) {
        // Log errors but don't block navigation
        Log.w(TAG, "WebView error: $errorCode - $description for URL: $failingUrl")
        super.onReceivedError(view, errorCode, description, failingUrl)
    }
    
    override fun onPageFinished(view: WebView?, url: String?) {
        super.onPageFinished(view, url)
        Log.d(TAG, "Page finished loading: $url")
    }
}
