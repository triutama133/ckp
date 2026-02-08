package com.example.ckp_temp

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.util.Log
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		// Initialize the FastText platform stub. Native implementation still required.
		FastTextStub(this.applicationContext, flutterEngine.dartExecutor.binaryMessenger)
	}
}
