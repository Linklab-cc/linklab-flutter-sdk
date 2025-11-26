package cc.linklab.flutter

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import androidx.annotation.NonNull
import cc.linklab.android.LinkLab
import cc.linklab.android.LinkLabConfig

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
  private var pendingDynamicIntent: Intent? = null   // Holds the first Intent that arrives before the SDK has been fully initialised via the init() method.
  private var isLinkLabInitialised: Boolean = false  // Tracks whether the LinkLab SDK has been initialised with a configuration.
  private val TAG = "LinkLabFlutter"

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    Log.d(TAG, "Plugin attached to Flutter engine")
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "cc.linklab.flutter/linklab")
    channel.setMethodCallHandler(this)
    context = flutterPluginBinding.applicationContext
    linkLab = LinkLab.getInstance(context)
    
    // Setup listener for dynamic links
    linkLab?.addListener(object : LinkLab.LinkLabListener {
      override fun onDynamicLinkRetrieved(rawLink: Uri, data: LinkLab.LinkData) {
        Log.d(TAG, "Dynamic link retrieved: $rawLink")
        
        // Create the base map explicitly typed as MutableMap<String, Any>
        val linkDataMap = mutableMapOf<String, Any>(
          "rawLink" to rawLink.toString(),
          "id" to data.id,
          "createdAt" to data.createdAt,
          "updatedAt" to data.updatedAt,
          "userId" to data.userId,
          "packageName" to data.packageName,
          "bundleId" to data.bundleId,
          "appStoreId" to data.appStoreId,
          "domainType" to data.domainType,
          "domain" to data.domain
        )
        
        // Add parameters if they exist
        if (data.parameters != null) {
          // Create a new HashMap for parameters to ensure correct type
          val paramsMap = HashMap<String, String>(data.parameters)
          linkDataMap["parameters"] = paramsMap // Add the HashMap
          Log.d(TAG, "Including parameters in link data: ${data.parameters}")
        } else {
          Log.d(TAG, "No parameters in link data")
        }

        // Convert to immutable Map<String, Any> before assigning and sending
        val finalLinkData: Map<String, Any> = linkDataMap.toMap()

        pendingDynamicLinkData = finalLinkData
        Log.d(TAG, "Sending dynamic link to Flutter: $finalLinkData")
        channel.invokeMethod("onDynamicLinkReceived", finalLinkData) // Pass the immutable map
      }

      override fun onError(exception: Exception) {
        Log.e(TAG, "LinkLab error: ${exception.message}", exception)
        val errorData = mapOf(
          "message" to (exception.message ?: "Unknown error"),
          "stackTrace" to exception.stackTraceToString()
        )
        channel.invokeMethod("onError", errorData)
      }
    })
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    Log.d(TAG, "Method called: ${call.method}")
    when (call.method) {
      "init" -> {
        Log.d(TAG, "Initializing LinkLab")
        
        // Extract the configuration from call.arguments
        val configMap = call.arguments as? Map<*, *>
        val customDomains = configMap?.get("customDomains") as? List<*>
        val debugLoggingEnabled = configMap?.get("debugLoggingEnabled") as? Boolean ?: false
        val networkTimeout = (configMap?.get("networkTimeout") as? Number)?.toDouble() ?: 30.0
        val networkRetryCount = (configMap?.get("networkRetryCount") as? Number)?.toInt() ?: 3
        
        // Convert custom domains list to String list
        val domains = customDomains?.map { it.toString() } ?: listOf()
        
        // Create and pass the configuration to the LinkLab SDK
        val config = LinkLabConfig(
            customDomains = domains,
            debugLoggingEnabled = debugLoggingEnabled,
            networkTimeout = networkTimeout,
            networkRetryCount = networkRetryCount
        )
        
        Log.d(TAG, "Initializing with custom domains: $domains, debug: $debugLoggingEnabled")
        linkLab?.init(config)

        // Mark the SDK as initialised and process any intent that might have been captured earlier.
        isLinkLabInitialised = true
        pendingDynamicIntent?.let {
          Log.d(TAG, "Processing previously pending intent after initialisation: ${it.data}")
          processIntent(it)
          pendingDynamicIntent = null
        }
        result.success(true)
      }
      "getInitialLink" -> {
        Log.d(TAG, "Getting initial link, pending data: ${pendingDynamicLinkData != null}")
        // Return any pending link that was processed before the Dart side was ready
        result.success(pendingDynamicLinkData)
        pendingDynamicLinkData = null
      }
      "getDynamicLink" -> {
        val shortLink = call.argument<String>("shortLink")
        Log.d(TAG, "Getting dynamic link for short link: $shortLink")
        if (shortLink.isNullOrEmpty()) {
          Log.e(TAG, "Short link is null or empty")
          result.error("INVALID_LINK", "Short link cannot be null or empty", null)
          return
        }
        
        try {
          val uri = Uri.parse(shortLink)
          linkLab?.getDynamicLink(uri)
          Log.d(TAG, "Successfully requested dynamic link resolution")
          result.success(true)
        } catch (e: Exception) {
          Log.e(TAG, "Error processing link: ${e.message}", e)
          result.error("LINK_PROCESSING_ERROR", e.message, e.stackTraceToString())
        }
      }
      "isLinkLabLink" -> {
        val linkUrl = call.argument<String>("link")
        Log.d(TAG, "Checking if URL is LinkLab link: $linkUrl")
        if (linkUrl.isNullOrEmpty()) {
          Log.d(TAG, "Link URL is null or empty, returning false")
          result.success(false)
          return
        }
        
        try {
          val intent = Intent(Intent.ACTION_VIEW, Uri.parse(linkUrl))
          val isLinkLabLink = linkLab?.isLinkLabLink(intent) ?: false
          Log.d(TAG, "Is LinkLab link: $isLinkLabLink")
          result.success(isLinkLabLink)
        } catch (e: Exception) {
          Log.e(TAG, "Error validating link: ${e.message}", e)
          result.error("LINK_VALIDATION_ERROR", e.message, e.stackTraceToString())
        }
      }
      else -> {
        Log.d(TAG, "Method not implemented: ${call.method}")
        result.notImplemented()
      }
    }
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    Log.d(TAG, "Plugin detached from Flutter engine")
    channel.setMethodCallHandler(null)
    activityBinding?.removeOnNewIntentListener(this)
    activityBinding = null
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    Log.d(TAG, "Plugin attached to activity")
    activityBinding = binding
    binding.addOnNewIntentListener(this)
    
    // Process initial intent if it contains a dynamic link
    val intent = binding.activity.intent
    Log.d(TAG, "Processing initial intent: ${intent?.data}")
    processIntent(intent)
  }

  override fun onDetachedFromActivityForConfigChanges() {
    Log.d(TAG, "Plugin detached from activity for config changes")
    activityBinding?.removeOnNewIntentListener(this)
    activityBinding = null
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    Log.d(TAG, "Plugin reattached to activity for config changes")
    activityBinding = binding
    binding.addOnNewIntentListener(this)
  }

  override fun onDetachedFromActivity() {
    Log.d(TAG, "Plugin detached from activity")
    activityBinding?.removeOnNewIntentListener(this)
    activityBinding = null
  }

  override fun onNewIntent(intent: Intent): Boolean {
    Log.d(TAG, "New intent received: ${intent.data}")
    return processIntent(intent)
  }

  private fun processIntent(intent: Intent?): Boolean {
    Log.d(TAG, "Processing intent: ${intent?.data}")
    // If the SDK isn't initialised yet, store the intent and return false. It will be
    // processed automatically once the Flutter side calls `init`.
    if (!isLinkLabInitialised) {
      Log.d(TAG, "LinkLab not initialised yet. Storing intent for later processing.")
      pendingDynamicIntent = intent
      return false
    }

    val result = linkLab?.processDynamicLink(intent) ?: false
    Log.d(TAG, "Intent processing result: $result")
    return result
  }
}