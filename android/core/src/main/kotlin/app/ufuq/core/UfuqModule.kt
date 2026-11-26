package app.ufuq.core

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import java.time.Instant

/**
 * A notch module (Prayer, AI usage, Agent status, ...), UI-free. The Android app adds its Compose
 * layer on top; keeping views out of here lets `./gradlew :core:test` run anywhere.
 *
 * Methods that touch a data source throw instead of crashing. [ModuleRegistry] catches the
 * exception and reports the module as [ModuleStatus.Unavailable].
 */
interface UfuqModule {
    val id: String
    val title: String
    var isEnabled: Boolean
    val status: ModuleStatus

    /** Reloads data from the source. */
    suspend fun refresh() {}

    /** What to show in the collapsed notch, or null for nothing. May throw. */
    fun collapsedActivity(now: Instant): LiveActivity?

    /** Peek alerts as they happen. */
    fun peekEvents(): Flow<PeekEvent> = emptyFlow()

    /** One-sentence spoken summary for accessibility services. */
    fun accessibilitySummary(): String
}
