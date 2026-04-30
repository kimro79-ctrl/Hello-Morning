package com.contacts.service

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel

class ContactsServicePlugin: FlutterPlugin {
  private var channel : MethodChannel? = null // ✅ ? 추가

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "github.com/baseflow/contacts_service")
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel?.setMethodCallHandler(null) // ✅ ?. 사용
    channel = null
  }
}
