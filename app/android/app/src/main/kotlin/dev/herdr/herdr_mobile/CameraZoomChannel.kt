package dev.herdr.herdr_mobile

import android.content.Context
import androidx.camera.core.CameraSelector
import androidx.camera.lifecycle.ProcessCameraProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

internal class CameraZoomChannel(context: Context, messenger: BinaryMessenger) {
    init {
        MethodChannel(messenger, "dev.herdr.herdr_mobile/camera_zoom")
            .setMethodCallHandler { call, result ->
                if (call.method != "getRange") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    val provider = ProcessCameraProvider.getInstance(context)
                    provider.addListener({
                        try {
                            // Match mobile_scanner's back camera with CameraLensType.any.
                            val zoom = provider.get()
                                .getCameraInfo(CameraSelector.DEFAULT_BACK_CAMERA)
                                .zoomState.value
                            if (zoom == null) {
                                result.error("camera_unavailable", "The camera zoom range is unavailable.", null)
                            } else {
                                result.success(mapOf(
                                    "minZoom" to zoom.minZoomRatio.toDouble(),
                                    "maxZoom" to zoom.maxZoomRatio.toDouble(),
                                    "wideZoom" to 1.0,
                                    "switchOverFactors" to emptyList<Double>(),
                                ))
                            }
                        } catch (_: Exception) {
                            result.error("camera_unavailable", "Camera information is unavailable.", null)
                        }
                    }, context.mainExecutor)
                } catch (_: Exception) {
                    result.error("camera_unavailable", "Camera information is unavailable.", null)
                }
            }
    }
}
