package app.ufuq.android

import android.app.Application
import app.ufuq.android.island.IslandService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch

class UfuqApp : Application() {
    val graph: AppGraph by lazy { AppGraph(this) }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    override fun onCreate() {
        super.onCreate()
        graph.bindOtherApps(scope)
        // Every settings change reaches the prayer module, the Live Update chip and the island.
        scope.launch {
            graph.settings.settings.distinctUntilChanged().collect { s ->
                graph.apply(s)
                graph.liveUpdate.refresh(s)
                IslandService.sync(this@UfuqApp, s.overlayEnabled)
            }
        }
    }
}

val android.content.Context.graph: AppGraph get() = (applicationContext as UfuqApp).graph
