package cc.linklab.flutter

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
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
import java.lang.ref.WeakReference

/**
 * Flutter bridge for the Linklab Android SDK.
 *
 * Method channel `cc.linklab.flutter/linklab`:
 * - Dart -> native: `init`, `ready`, `getInitialLink`, `resolve`, `isLinkLabLink`, `checkPasteboard`
 * - native -> Dart: `onLink(map)` (only after `ready`), `onError({message, code, stackTrace})`
 *
 * Routing: intents whose data URI is a Linklab link go to the SDK (resolved server-side). Any
 * other data URI (other https hosts, custom schemes) is dropped, unless `forwardNonLinklabLinks`
 * is on, in which case it is delivered to Dart unchanged with `resolutionStatus == "passthrough"`.
 * Intents received before Dart sends `init` are queued and routed once the config is known.
 *
 * All state is confined to the main thread: method-channel calls, activity callbacks and the
 * SDK listener are all invoked there.
 */
class LinkLabFlutterPlugin : FlutterPlugin, MethodCallHandler, ActivityAware, NewIntentListener {

    private var channel: MethodChannel? = null
    private lateinit var applicationContext: Context
    private var linkLab: LinkLab? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private var activityBinding: ActivityPluginBinding? = null
    /** Activity whose launch intent has already been processed (once per Activity instance). */
    private var processedLaunchActivity: WeakReference<Activity>? = null

    private var config: LinkLabConfig = LinkLabConfig()
    private var forwardNonLinklabLinks = false
    private var sdkInitialised = false
    private var dartReady = false

    /** Intents received before Dart called `init`. */
    private val pendingIntents = ArrayList<Intent>()
    /** Links received before Dart called `ready`. */
    private val queuedLinks = ArrayList<Map<String, Any?>>()
    /** First (non-resolve) link delivered in this process. */
    private var firstLink: Map<String, Any?>? = null
    /** URIs handed to the SDK whose result has not been delivered yet. */
    private val inFlight = HashSet<String>()
    /** `getInitialLink` callers waiting for an in-flight resolution. */
    private val initialLinkWaiters = ArrayList<PendingResult>()
    /** `resolve` callers waiting for their link. */
    private val resolveWaiters = ArrayList<ResolveWaiter>()
    /** URIs requested through `resolve`; their results bypass the stream. */
    private val requestedUris = HashSet<String>()

    private open class PendingResult(val result: Result) {
        var done = false
        fun success(value: Any?) {
            if (done) return
            done = true
            result.success(value)
        }
        fun error(code: String, message: String) {
            if (done) return
            done = true
            result.error(code, message, null)
        }
    }

    private class ResolveWaiter(val uri: String, result: Result) : PendingResult(result)

    private val sdkListener = object : LinkLab.LinkLabListener {
        override fun onDynamicLinkRetrieved(fullLink: Uri, data: LinkLab.LinkData) {
            onLinkDelivered(data)
        }

        override fun onError(exception: Exception) {
            channel?.invokeMethod(
                "onError",
                mapOf(
                    "message" to (exception.message ?: exception.javaClass.simpleName),
                    "code" to exception.javaClass.simpleName,
                    "stackTrace" to exception.stackTraceToString(),
                ),
            )
        }
    }

    // ------------------------------------------------------------------------------------------
    // FlutterPlugin
    // ------------------------------------------------------------------------------------------

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME).also {
            it.setMethodCallHandler(this)
        }
        linkLab = LinkLab.getInstance(applicationContext).also { it.addListener(sdkListener) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        linkLab?.removeListener(sdkListener)
        linkLab = null
        channel?.setMethodCallHandler(null)
        channel = null
        mainHandler.removeCallbacksAndMessages(null)
        initialLinkWaiters.forEach { it.success(firstLink) }
        initialLinkWaiters.clear()
        resolveWaiters.forEach { it.error("DETACHED", "Plugin detached from engine") }
        resolveWaiters.clear()
        dartReady = false
    }

    // ------------------------------------------------------------------------------------------
    // MethodCallHandler
    // ------------------------------------------------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "init" -> handleInit(call, result)
            "ready" -> {
                dartReady = true
                val queued = ArrayList(queuedLinks)
                queuedLinks.clear()
                queued.forEach { channel?.invokeMethod("onLink", it) }
                result.success(null)
            }
            "getInitialLink" -> handleGetInitialLink(result)
            "resolve" -> handleResolve(call, result)
            "isLinkLabLink" -> {
                val link = call.argument<String>("link")
                val uri = link?.takeIf { it.isNotBlank() }?.let { safeParse(it) }
                result.success(uri != null && linkLab?.isLinkLabLink(uri) == true)
            }
            "checkPasteboard" -> result.success(null) // iOS only
            else -> result.notImplemented()
        }
    }

    private fun handleInit(call: MethodCall, result: Result) {
        val args = call.arguments as? Map<*, *>
        val domains = (args?.get("customDomains") as? List<*>)?.map { it.toString() } ?: emptyList()
        config = LinkLabConfig(
            customDomains = domains,
            debugLoggingEnabled = args?.get("debugLoggingEnabled") as? Boolean ?: false,
            networkTimeout = (args?.get("networkTimeout") as? Number)?.toDouble() ?: 10.0,
            networkRetryCount = (args?.get("networkRetryCount") as? Number)?.toInt() ?: 3,
            baseUrl = (args?.get("baseUrl") as? String)?.takeIf { it.isNotBlank() }
                ?: LinkLabConfig.DEFAULT_BASE_URL,
            installReferrerEnabled = args?.get("installReferrerEnabled") as? Boolean ?: true,
        )
        forwardNonLinklabLinks = args?.get("forwardNonLinklabLinks") as? Boolean ?: false
        val sdk = linkLab ?: LinkLab.getInstance(applicationContext).also {
            it.addListener(sdkListener)
            linkLab = it
        }
        try {
            sdk.init(config)
        } catch (e: Exception) {
            result.error("INIT_FAILED", e.message ?: "Failed to initialise Linklab", null)
            return
        }
        sdkInitialised = true
        val intents = ArrayList(pendingIntents)
        pendingIntents.clear()
        intents.forEach { processIntent(it) }
        result.success(true)
    }

    private fun handleGetInitialLink(result: Result) {
        val first = firstLink
        if (first != null || inFlight.isEmpty()) {
            result.success(first)
            return
        }
        val waiter = PendingResult(result)
        initialLinkWaiters.add(waiter)
        mainHandler.postDelayed({
            if (initialLinkWaiters.remove(waiter)) waiter.success(firstLink)
        }, INITIAL_LINK_TIMEOUT_MS)
    }

    private fun handleResolve(call: MethodCall, result: Result) {
        val shortLink = call.argument<String>("shortLink")?.trim()
        if (shortLink.isNullOrEmpty()) {
            result.error("INVALID_ARGUMENT", "shortLink must not be empty", null)
            return
        }
        val uri = safeParse(shortLink)
        val sdk = linkLab
        if (uri == null || sdk == null || !sdk.isLinkLabLink(uri)) {
            result.success(null)
            return
        }
        val key = uri.toString()
        val waiter = ResolveWaiter(key, result)
        resolveWaiters.add(waiter)
        requestedUris.add(key)
        inFlight.add(key)
        val accepted = try {
            sdk.getDynamicLink(uri)
        } catch (e: Exception) {
            false
        }
        if (!accepted) {
            resolveWaiters.remove(waiter)
            requestedUris.remove(key)
            inFlight.remove(key)
            waiter.success(null)
            return
        }
        val timeoutMs =
            ((config.networkTimeout * 1000).toLong() * (config.networkRetryCount.coerceAtLeast(0) + 1)) + 2000L
        mainHandler.postDelayed({
            if (resolveWaiters.remove(waiter)) {
                requestedUris.remove(key)
                inFlight.remove(key)
                waiter.error("TIMEOUT", "Timed out resolving $key")
            }
        }, timeoutMs)
    }

    // ------------------------------------------------------------------------------------------
    // Delivery
    // ------------------------------------------------------------------------------------------

    private fun onLinkDelivered(data: LinkLab.LinkData) {
        val map = toMap(data)
        data.shortLink?.let { inFlight.remove(it) }

        val waiter = resolveWaiters.firstOrNull { it.uri == data.shortLink || it.uri == data.fullLink }
        if (waiter != null) {
            resolveWaiters.remove(waiter)
            requestedUris.remove(waiter.uri)
            waiter.success(map)
            return
        }
        if (data.shortLink != null && requestedUris.remove(data.shortLink)) {
            // Requested via resolve() but the caller already timed out: keep it off the stream.
            return
        }
        deliver(map)
    }

    /** Sends a link to Dart (or queues it until `ready`) and records it as the initial link. */
    private fun deliver(map: Map<String, Any?>) {
        if (firstLink == null) firstLink = map
        if (initialLinkWaiters.isNotEmpty()) {
            val waiters = ArrayList(initialLinkWaiters)
            initialLinkWaiters.clear()
            waiters.forEach { it.success(firstLink) }
        }

        if (dartReady) {
            channel?.invokeMethod("onLink", map)
        } else {
            queuedLinks.add(map)
        }
    }

    /** A non-Linklab URI, delivered as received. */
    private fun passthroughMap(uri: Uri): Map<String, Any?> {
        val parameters = HashMap<String, String>()
        if (uri.isHierarchical) {
            for (name in uri.queryParameterNames) {
                uri.getQueryParameter(name)?.let { parameters[name] = it }
            }
        }
        return mapOf(
            "id" to null,
            "fullLink" to uri.toString(),
            "shortLink" to uri.toString(),
            "domain" to uri.host?.lowercase(),
            "domainType" to "unrecognized",
            "parameters" to parameters,
            "resolutionStatus" to "passthrough",
            "errorMessage" to null,
            "isDeferred" to false,
            "matchType" to "direct",
        )
    }

    private fun toMap(data: LinkLab.LinkData): Map<String, Any?> = mapOf(
        "id" to data.id,
        "fullLink" to data.fullLink,
        "shortLink" to data.shortLink,
        "createdAt" to data.createdAt,
        "updatedAt" to data.updatedAt,
        "packageName" to data.packageName,
        "bundleId" to data.bundleId,
        "appStoreId" to data.appStoreId,
        "domain" to data.domain,
        "domainType" to data.domainType,
        "parameters" to HashMap<String, String>(data.parameters),
        "resolutionStatus" to data.resolutionStatus,
        "errorMessage" to data.errorMessage,
        "isDeferred" to data.isDeferred,
        "matchType" to data.matchType,
    )

    // ------------------------------------------------------------------------------------------
    // ActivityAware / intents
    // ------------------------------------------------------------------------------------------

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addOnNewIntentListener(this)
        val activity = binding.activity
        if (processedLaunchActivity?.get() !== activity) {
            processedLaunchActivity = WeakReference(activity)
            processIntent(activity.intent)
        }
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeOnNewIntentListener(this)
        activityBinding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        // Same launch intent, already processed: only re-register for new intents.
        activityBinding = binding
        binding.addOnNewIntentListener(this)
        processedLaunchActivity = WeakReference(binding.activity)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeOnNewIntentListener(this)
        activityBinding = null
    }

    override fun onNewIntent(intent: Intent): Boolean {
        activityBinding?.activity?.intent = intent
        return processIntent(intent)
    }

    /**
     * Routes [intent]: Linklab links go to the SDK, other URIs are forwarded to Dart when
     * `forwardNonLinklabLinks` is on. Queued until Dart has called `init`. Returns `true` only
     * when the SDK accepted the intent.
     */
    private fun processIntent(intent: Intent?): Boolean {
        val uri = intent?.data ?: return false
        val sdk = linkLab ?: return false
        if (!sdkInitialised) {
            pendingIntents.add(intent)
            return sdk.isLinkLabLink(uri)
        }
        if (!sdk.isLinkLabLink(uri)) {
            if (forwardNonLinklabLinks) deliver(passthroughMap(uri))
            return false
        }
        val key = uri.toString()
        inFlight.add(key)
        val accepted = try {
            sdk.processDynamicLink(intent)
        } catch (e: Exception) {
            if (config.debugLoggingEnabled) Log.e(TAG, "processDynamicLink failed", e)
            false
        }
        if (!accepted) inFlight.remove(key)
        return accepted
    }

    private fun safeParse(value: String): Uri? = try {
        Uri.parse(value)
    } catch (e: Exception) {
        null
    }

    private companion object {
        const val TAG = "LinkLabFlutter"
        const val CHANNEL_NAME = "cc.linklab.flutter/linklab"
        const val INITIAL_LINK_TIMEOUT_MS = 5000L
    }
}
