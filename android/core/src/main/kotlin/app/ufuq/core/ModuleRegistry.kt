package app.ufuq.core

import java.time.Instant
import kotlin.coroutines.cancellation.CancellationException

class DuplicateModuleIdException(val moduleId: String) : IllegalArgumentException("Duplicate module id: $moduleId")

/**
 * Loads modules, catches their errors and reports their status.
 *
 * A module that throws is marked unavailable with the error text until its next successful
 * refresh; the other modules keep working. Use from one thread (the main thread in the app).
 */
class ModuleRegistry {
    private val _modules = mutableListOf<UfuqModule>()
    private val failures = mutableMapOf<String, String>()

    val modules: List<UfuqModule> get() = _modules.toList()

    /** @throws DuplicateModuleIdException when a module with the same id is already registered. */
    fun register(module: UfuqModule) {
        if (_modules.any { it.id == module.id }) throw DuplicateModuleIdException(module.id)
        _modules += module
    }

    fun module(id: String): UfuqModule? = _modules.firstOrNull { it.id == id }

    val enabledModules: List<UfuqModule> get() = _modules.filter { it.isEnabled }

    /** The module's own status, overridden by [ModuleStatus.Unavailable] after a caught error. */
    fun status(id: String): ModuleStatus? {
        val module = module(id) ?: return null
        failures[id]?.let { return ModuleStatus.Unavailable(it) }
        return module.status
    }

    /** Refreshes every enabled module. A throwing module is marked unavailable; the rest continue. */
    suspend fun refreshAll() {
        for (module in enabledModules) {
            try {
                module.refresh()
                failures.remove(module.id)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                failures[module.id] = describe(e)
            }
        }
    }

    /**
     * Collapsed activities from enabled, available modules. Throwing modules are skipped and
     * marked unavailable.
     */
    fun activities(now: Instant): List<LiveActivity> {
        val result = mutableListOf<LiveActivity>()
        for (module in enabledModules) {
            if (module.id in failures || !module.status.isAvailable) continue
            try {
                module.collapsedActivity(now)?.let(result::add)
            } catch (e: Exception) {
                failures[module.id] = describe(e)
            }
        }
        return result
    }

    private fun describe(e: Exception): String = e.message ?: e.toString()
}
