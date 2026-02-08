package com.example.ckp_temp

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import android.util.Log

// NOTE: This is a stub. Implement native fastText loading/inference here.
class FastTextStub(context: Context, messenger: io.flutter.plugin.common.BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "ckp/fasttext")
    private val appContext = context.applicationContext

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "loadModel" -> {
                val path = call.argument<String>("path")
                // If a simple rule model exists, load the rules via native bridge
                if (path != null) {
                    try {
                        System.loadLibrary("fasttext_bridge")
                    } catch (e: Throwable) {
                        Log.w("FastTextStub", "Native lib not loaded: ${e.message}")
                    }
                    FastTextBridge.loadRules(path)
                }
                result.success(null)
            }
            "predict" -> {
                val text = call.argument<String>("text") ?: ""
                val k = call.argument<Int>("k") ?: 1
                val preds = FastTextBridge.predict(text, k)
                // preds expected as flattened string label:score; parse to list
                val out = preds.map {
                    mapOf("label" to it.split(":")[0], "score" to it.split(":")[1].toDouble())
                }
                result.success(out)
            }
            else -> result.notImplemented()
        }
    }
}

// JNI bridge helper calling into C++
object FastTextBridge {
    // In-memory rules: label -> set of keywords
    @Volatile
    private var rules: Map<String, Set<String>> = emptyMap()

    // Load rules from a simple tab-separated file: label\tkw1,kw2,kw3
    fun loadRules(path: String) {
        try {
            val f = java.io.File(path)
            if (!f.exists()) {
                android.util.Log.w("FastTextBridge", "Rules file not found: $path")
                rules = emptyMap()
                return
            }
            val map = mutableMapOf<String, MutableSet<String>>()
            f.forEachLine { line ->
                val l = line.trim()
                if (l.isEmpty()) return@forEachLine
                val parts = l.split('\t')
                if (parts.size < 2) return@forEachLine
                val label = parts[0].trim()
                val kws = parts[1].split(',').map { it.trim().lowercase() }.filter { it.isNotEmpty() }
                map[label] = map.getOrDefault(label, mutableSetOf()).apply { addAll(kws) }
            }
            rules = map.mapValues { it.value.toSet() }
            android.util.Log.i("FastTextBridge", "Loaded rules: ${rules.keys}")
        } catch (e: Exception) {
            android.util.Log.w("FastTextBridge", "Failed to load rules: ${e.message}")
            rules = emptyMap()
        }
    }

    // Simple tokenization
    private fun tokenize(text: String): List<String> {
        return text.lowercase().split(Regex("\\W+"))
            .map { it.trim() }
            .filter { it.isNotEmpty() }
    }

    // Predict returns an Array<String> of "label:score" sorted by score desc
    fun predict(text: String, k: Int): Array<String> {
        try {
            val toks = tokenize(text)
            if (rules.isEmpty()) return arrayOf()
            val scores = rules.mapValues { entry ->
                val kws = entry.value
                if (kws.isEmpty()) 0.0 else {
                    val matches = toks.count { kws.contains(it) }
                    matches.toDouble() / kws.size.toDouble()
                }
            }
            val top = scores.entries.sortedByDescending { it.value }.take(k)
            return top.map { "${it.key}:${"%.3f".format(it.value)}" }.toTypedArray()
        } catch (e: Exception) {
            android.util.Log.w("FastTextBridge", "Predict error: ${e.message}")
            return arrayOf()
        }
    }
}
