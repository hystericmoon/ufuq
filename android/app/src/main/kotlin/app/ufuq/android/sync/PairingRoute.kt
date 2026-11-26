package app.ufuq.android.sync

import android.Manifest
import android.content.ClipboardManager
import android.content.Context
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LocalLifecycleOwner
import app.ufuq.android.R
import app.ufuq.android.graph
import app.ufuq.core.sync.PairingException
import app.ufuq.core.sync.PairingPayload
import java.util.concurrent.Executors
import kotlinx.coroutines.launch

/** What pasting or scanning a code does to the screen: the payload to save, or the error to show. */
sealed interface PairingOutcome {
    data class Ok(val payload: PairingPayload) : PairingOutcome
    data class Failed(val error: PairingError) : PairingOutcome

    companion object {
        fun of(text: String): PairingOutcome = try {
            Ok(PairingPayload.parse(text))
        } catch (e: PairingException) {
            Failed(if (e.message?.startsWith("Unsupported") == true) PairingError.UNSUPPORTED else PairingError.INVALID)
        }
    }
}

/**
 * The stateful pairing screen. The CAMERA permission is asked only here, only when the user taps
 * "Allow camera and scan", after the rationale on screen.
 */
@Composable
fun PairingRoute(onClose: () -> Unit) {
    val context = LocalContext.current
    val store = context.graph.pairings
    val scope = rememberCoroutineScope()
    var state by remember {
        mutableStateOf(PairingUiState(cameraGranted = ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED))
    }

    fun submit(text: String) {
        when (val outcome = PairingOutcome.of(text)) {
            is PairingOutcome.Failed -> state = state.copy(error = outcome.error, scanning = false)
            is PairingOutcome.Ok -> scope.launch {
                store.save(outcome.payload)
                state = state.copy(error = null, scanning = false, pairedName = outcome.payload.name ?: outcome.payload.host)
            }
        }
    }

    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        state = state.copy(cameraGranted = granted, cameraDenied = !granted, scanning = granted)
    }

    PairingScreen(
        state = state,
        actions = PairingActions(
            onBack = onClose,
            onScan = {
                if (state.cameraGranted) state = state.copy(scanning = true, error = null) else permission.launch(Manifest.permission.CAMERA)
            },
            onStopScan = { state = state.copy(scanning = false) },
            onCodeChange = { state = state.copy(code = it, error = null) },
            onPasteFromClipboard = {
                val text = (context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager)
                    ?.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.coerceToText(context)?.toString().orEmpty()
                if (text.isNotBlank()) state = state.copy(code = text, error = null)
            },
            onSubmit = { submit(state.code) },
            onDone = onClose,
        ),
        camera = { modifier -> CameraScanner(modifier) { submit(it) } },
    )
}

/** Live CameraX preview whose frames go to ZXing. Reports each distinct text once per frame it is seen in. */
@Composable
private fun CameraScanner(modifier: Modifier, onText: (String) -> Unit) {
    val context = LocalContext.current
    val owner = LocalLifecycleOwner.current
    val executor = remember { Executors.newSingleThreadExecutor() }
    val previewView = remember { PreviewView(context).apply { implementationMode = PreviewView.ImplementationMode.COMPATIBLE } }
    val description = stringResource(R.string.pair_camera_preview_description)
    var delivered by remember { mutableStateOf(false) }

    DisposableEffect(owner) {
        val future = ProcessCameraProvider.getInstance(context)
        var provider: ProcessCameraProvider? = null
        future.addListener({
            val p = runCatching { future.get() }.getOrNull() ?: return@addListener
            provider = p
            val preview = Preview.Builder().build().also { it.surfaceProvider = previewView.surfaceProvider }
            val analysis = ImageAnalysis.Builder()
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .build()
                .also { a ->
                    a.setAnalyzer(executor, QrAnalyzer { text ->
                        if (!delivered) {
                            delivered = true
                            previewView.post { onText(text) }
                        }
                    })
                }
            runCatching {
                p.unbindAll()
                p.bindToLifecycle(owner, CameraSelector.DEFAULT_BACK_CAMERA, preview, analysis)
            }
        }, ContextCompat.getMainExecutor(context))
        onDispose {
            provider?.unbindAll()
            executor.shutdown()
        }
    }
    AndroidView(factory = { previewView }, modifier = modifier.semantics { contentDescription = description })
}
