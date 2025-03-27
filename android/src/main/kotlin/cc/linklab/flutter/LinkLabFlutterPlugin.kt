package cc.linklab.flutter

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.annotation.NonNull
import cc.linklab.android.LinkLab

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry.NewIntentListener

class LinkLabFlutterPlugin: FlutterPlugin, MethodCallHandler, ActivityAware, NewIntentListener {
  private lateinit var channel: MethodChannel
  private lateinit var context: Context
  private var activityBinding: ActivityPluginBinding? = null
  private var linkLab: LinkLab? = null
  private var pendingDynamicLinkData: Map<String, Any>? = null

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "cc.linklab.flutter/linklab")
    channel.setMethodCallHandler(this)
    context = flutterPluginBinding.applicationContext
    linkLab = LinkLab.getInstance(context)
    
    // Setup listener for dynamic links
    linkLab?.addListener(object : LinkLab.LinkLabListener {
      override fun onDynamicLinkRetrieved(fullLink: Uri, data: LinkLab.LinkData) {
        val linkData = mapOf(
          "fullLink" to fullLink.toString(),
          "id" to data.id,
          "createdAt" to data.createdAt,
          "updatedAt" to data.updatedAt,
          "userId" to data.userId,
          "packageName" to (data.packageName ?: ""),
          "bundleId" to (data.bundleId ?: ""),
          "appStoreId" to (data.appStoreId ?: ""),
          "domainType" to data.domainType,
          "domain" to data.domain
        )
        
        pendingDynamicLinkData = linkData
        channel.invokeMethod("onDynamicLinkReceived", linkData)
      }

      override fun onError(exception: Exception) {
        val errorData = mapOf(
          "message" to (exception.message ?: "Unknown error"),
          "stackTrace" to exception.stackTraceToString()
        )
        channel.invokeMethod("onError", errorData)
      }
    })
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    when (call.method) {
      "init" -> {
        linkLab?.init()
        result.success(true)
      }
      "getInitialLink" -> {
        // Return any pending link that was processed before the Dart side was ready
        result.success(pendingDynamicLinkData)
        pendingDynamicLinkData = null
      }
      "getDynamicLink" -> {
        val shortLink = call.argument<String>("shortLink")
        if (shortLink.isNullOrEmpty()) {
          result.error("INVALID_LINK", "Short link cannot be null or empty", null)
          return
        }
        
        try {
          val uri = Uri.parse(shortLink)
          linkLab?.getDynamicLink(uri)
          result.success(true)
        } catch (e: Exception) {
          result.error("LINK_PROCESSING_ERROR", e.message, e.stackTraceToString())
        }
      }
      "isLinkLabLink" -> {
        val linkUrl = call.argument<String>("link")
        if (linkUrl.isNullOrEmpty()) {
          result.success(false)
          return
        }
        
        try {
          val intent = Intent(Intent.ACTION_VIEW, Uri.parse(linkUrl))
          val isLinkLabLink = linkLab?.isLinkLabLink(intent) ?: false
          result.success(isLinkLabLink)
        } catch (e: Exception) {
          result.error("LINK_VALIDATION_ERROR", e.message, e.stackTraceToString())
        }
      }
      else -> {
        result.notImplemented()
      }
    }
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    activityBinding?.removeOnNewIntentListener(this)
    activityBinding = null
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activityBinding = binding
    binding.addOnNewIntentListener(this)
    
    // Process initial intent if it contains a dynamic link
    val intent = binding.activity.intent
    processIntent(intent)
  }

  override fun onDetachedFromActivityForConfigChanges() {
    activityBinding?.removeOnNewIntentListener(this)
    activityBinding = null
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    activityBinding = binding
    binding.addOnNewIntentListener(this)
  }

  override fun onDetachedFromActivity() {
    activityBinding?.removeOnNewIntentListener(this)
    activityBinding = null
  }

  override fun onNewIntent(intent: Intent): Boolean {
    return processIntent(intent)
  }

  private fun processIntent(intent: Intent?): Boolean {
    return linkLab?.processDynamicLink(intent) ?: false
  }
}