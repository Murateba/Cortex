package com.vertex.cortex

import android.annotation.SuppressLint
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.os.Environment
import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val storageChannel = "com.vertex.cortex/storage"
    private val llamaChannel = "com.vertex.cortex/llama"
    private val memoryChannel = "com.vertex.cortex/memory"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // RAM KANALI
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            memoryChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDeviceMemory" -> {
                    val memoryInfo = getDeviceMemory()
                    result.success(memoryInfo)
                }
                "getUsedMemory" -> {
                    val usedMemory = getUsedMemory()
                    result.success(usedMemory)
                }
                else -> result.notImplemented()
            }
        }

        // Depolama kanalı
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            storageChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getFreeStorage" -> {
                    val freeStorage = getFreeStorage()
                    result.success(freeStorage)
                }

                "getTotalStorage" -> {
                    val totalStorage = getTotalStorage()
                    result.success(totalStorage)
                }

                else -> result.notImplemented()
            }
        }

        // Llama kanalı
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            llamaChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "loadModel" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        val llamaServiceIntent = Intent(this, LlamaService::class.java)
                        llamaServiceIntent.putExtra("action", "loadModel")
                        llamaServiceIntent.putExtra("modelPath", path)

                        // Servisi başlat
                        startService(llamaServiceIntent)

                        // Servise MethodChannel iletin
                        val llamaService = LlamaService()
                        llamaService.setMethodChannel(
                            MethodChannel(
                                flutterEngine.dartExecutor.binaryMessenger,
                                llamaChannel
                            )
                        )

                        result.success("Model yükleme başlatıldı: $path")
                    } else {
                        result.error("HATA", "Geçersiz model yolu", null)
                    }
                }

                "sendMessage" -> {
                    val message = call.argument<String>("message")
                    if (message != null) {
                        val llamaServiceIntent = Intent(this, LlamaService::class.java)
                        llamaServiceIntent.putExtra("action", "sendMessage")
                        llamaServiceIntent.putExtra("message", message)

                        // Servisi başlat
                        startService(llamaServiceIntent)

                        // Servise MethodChannel iletin
                        val llamaService = LlamaService()
                        llamaService.setMethodChannel(
                            MethodChannel(
                                flutterEngine.dartExecutor.binaryMessenger,
                                llamaChannel
                            )
                        )

                        result.success("Mesaj gönderme başlatıldı: $message")
                    } else {
                        result.error("HATA", "Geçersiz mesaj", null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    // Mevcut olan RAM miktarını döner (MB cinsinden)
    private fun getDeviceMemory(): Long {
        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memoryInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memoryInfo)
        return memoryInfo.totalMem / (1024 * 1024)  // MB cinsinden döner
    }

    private fun getUsedMemory(): Long {
        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memoryInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memoryInfo)
        val usedMemBytes = memoryInfo.totalMem - memoryInfo.availMem
        return usedMemBytes / (1024 * 1024) // MB cinsinden döner
    }

    // Boş depolama alanını MB olarak döner
    private fun getFreeStorage(): Long {
        val stat = StatFs(Environment.getExternalStorageDirectory().path)
        return stat.blockSizeLong * stat.availableBlocksLong / (1024 * 1024)  // MB cinsinden döner
    }

    // Toplam depolama alanını MB olarak döner
    private fun getTotalStorage(): Long {
        val stat = StatFs(Environment.getExternalStorageDirectory().path)
        return stat.blockSizeLong * stat.blockCountLong / (1024 * 1024)  // MB cinsinden döner
    }
}
