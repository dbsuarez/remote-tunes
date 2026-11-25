package com.remotetunes.remote_tunes

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Self-update helpers: which version is installed, which CPU type this phone
 * has (to pick the right APK), and handing a downloaded APK to Android's own
 * installer. Android always asks the user to confirm the install.
 */
class UpdateSupport(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "remotetunes/update")

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() = channel.setMethodCallHandler(null)

    @Suppress("DEPRECATION")
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "info" -> {
                    val pm = activity.packageManager
                    val pi = pm.getPackageInfo(activity.packageName, 0)
                    val code = if (Build.VERSION.SDK_INT >= 28) pi.longVersionCode else pi.versionCode.toLong()
                    result.success(
                        mapOf(
                            "version" to (pi.versionName ?: "0.0.0"),
                            "build" to code,
                            "abi" to (Build.SUPPORTED_ABIS.firstOrNull() ?: "arm64-v8a"),
                        ),
                    )
                }
                "canWriteAllFiles" -> result.success(
                    if (Build.VERSION.SDK_INT >= 30) android.os.Environment.isExternalStorageManager() else true,
                )
                "openAllFilesSettings" -> {
                    if (Build.VERSION.SDK_INT >= 30) {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                            Uri.parse("package:${activity.packageName}"),
                        )
                        activity.startActivity(intent)
                    }
                    result.success(null)
                }
                "canInstall" -> result.success(activity.packageManager.canRequestPackageInstalls())
                "openInstallSettings" -> {
                    val intent = Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:${activity.packageName}"),
                    )
                    activity.startActivity(intent)
                    result.success(null)
                }
                "install" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("bad_args", "No file", null)
                        return
                    }
                    val file = File(path)
                    val uri = FileProvider.getUriForFile(
                        activity,
                        "${activity.packageName}.updates",
                        file,
                    )
                    val intent = Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(uri, "application/vnd.android.package-archive")
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    activity.startActivity(intent)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("failed", e.message, null)
        }
    }
}
