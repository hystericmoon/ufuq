package app.ufuq.core

import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.runTest
import org.junit.Test
import java.time.Instant
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull

private class SourceBroke : Exception("Antigravity state file missing")

private class FakeModule(
    override val id: String,
    private val source: ActivitySource = ActivitySource.OTHER,
) : UfuqModule {
    override val title: String = id.replaceFirstChar { it.uppercase() }
    override var isEnabled = true
    override var status: ModuleStatus = ModuleStatus.Ok
    var failRefresh = false
    var failActivity = false
    var refreshCount = 0

    override suspend fun refresh() {
        refreshCount++
        if (failRefresh) throw SourceBroke()
    }

    override fun collapsedActivity(now: Instant): LiveActivity? {
        if (failActivity) throw SourceBroke()
        return LiveActivity(id, id, source, title, title)
    }

    override fun accessibilitySummary(): String = title
}

class ModuleRegistryTest {
    private val now = T0

    @Test
    fun `register rejects duplicate ids`() {
        val registry = ModuleRegistry()
        registry.register(FakeModule("prayer"))
        val e = assertFailsWith<DuplicateModuleIdException> { registry.register(FakeModule("prayer")) }
        assertEquals("prayer", e.moduleId)
        assertEquals(1, registry.modules.size)
    }

    @Test
    fun `throwing refresh marks only that module unavailable`() = runTest {
        val registry = ModuleRegistry()
        val prayer = FakeModule("prayer", ActivitySource.PRAYER)
        val antigravity = FakeModule("antigravity", ActivitySource.AI_USAGE).apply { failRefresh = true }
        registry.register(prayer)
        registry.register(antigravity)

        registry.refreshAll()

        assertEquals(ModuleStatus.Ok, registry.status("prayer"))
        assertEquals(ModuleStatus.Unavailable("Antigravity state file missing"), registry.status("antigravity"))
        assertEquals(listOf("prayer"), registry.activities(now).map { it.id })
    }

    @Test
    fun `recovers after successful refresh`() = runTest {
        val registry = ModuleRegistry()
        val m = FakeModule("codex").apply { failRefresh = true }
        registry.register(m)
        registry.refreshAll()
        assertFalse(registry.status("codex")!!.isAvailable)

        m.failRefresh = false
        registry.refreshAll()
        assertEquals(ModuleStatus.Ok, registry.status("codex"))
        assertEquals(listOf("codex"), registry.activities(now).map { it.id })
    }

    @Test
    fun `throwing activity is skipped and marked`() {
        val registry = ModuleRegistry()
        registry.register(FakeModule("bad").apply { failActivity = true })
        registry.register(FakeModule("good"))

        assertEquals(listOf("good"), registry.activities(now).map { it.id })
        assertEquals(ModuleStatus.Unavailable("Antigravity state file missing"), registry.status("bad"))
    }

    @Test
    fun `disabled and self-reported unavailable modules are skipped`() = runTest {
        val registry = ModuleRegistry()
        val off = FakeModule("off").apply { isEnabled = false }
        val down = FakeModule("down").apply { status = ModuleStatus.Unavailable("No ~/.codex") }
        val stale = FakeModule("stale").apply { status = ModuleStatus.Stale(now) }
        registry.register(off)
        registry.register(down)
        registry.register(stale)

        registry.refreshAll()
        assertEquals(0, off.refreshCount)
        assertEquals(listOf("stale"), registry.activities(now).map { it.id }, "stale data still shows")
        assertEquals(ModuleStatus.Unavailable("No ~/.codex"), registry.status("down"))
        assertNull(registry.status("missing"))
    }

    @Test
    fun `default peek stream finishes`() = runTest {
        assertEquals(0, FakeModule("x").peekEvents().toList().size)
    }

    @Test
    fun `module lookup and enabled list`() {
        val registry = ModuleRegistry()
        registry.register(FakeModule("a"))
        registry.register(FakeModule("b").apply { isEnabled = false })
        assertNotNull(registry.module("b"))
        assertEquals(listOf("a"), registry.enabledModules.map { it.id })
    }
}
