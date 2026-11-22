package dev.sentinel.rules

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.time.Instant

class RulesTest {
    private val now = Instant.parse("2025-01-01T00:00:00Z")

    private fun event(type: EventType = EventType.INSTALL, playSeconds: Int? = null) =
        FraudEvent("k", "u1", "d1", "1.1.1.1", type, null, playSeconds, now)

    private fun history(events: Int = 0, users: Set<String> = emptySet()) = object : EventHistory {
        override fun countByUser(userId: String, from: Instant, to: Instant) = events

        override fun distinctUsersOnDevice(deviceId: String) = users
    }

    @Test
    fun `velocity triggers above max events`() {
        val result = VelocityRule().evaluate(event(), RuleContext(mapOf("maxEvents" to 5), history(events = 5)))
        assertEquals(50, result.score)
    }

    @Test
    fun `velocity does not trigger at the limit`() {
        val result = VelocityRule().evaluate(event(), RuleContext(mapOf("maxEvents" to 5), history(events = 4)))
        assertFalse(result.triggered)
    }

    @Test
    fun `device sharing triggers when more than max users share a device`() {
        val ctx = RuleContext(mapOf("maxUsers" to 3), history(users = setOf("a", "b", "c")))
        assertEquals(40, DeviceSharingRule().evaluate(event(), ctx).score)
    }

    @Test
    fun `device sharing does not trigger for the same user`() {
        val ctx = RuleContext(mapOf("maxUsers" to 3), history(users = setOf("u1", "b", "c")))
        assertFalse(DeviceSharingRule().evaluate(event(), ctx).triggered)
    }

    @Test
    fun `fast completion triggers on short play time`() {
        val ctx = RuleContext(mapOf("minSeconds" to 10), history())
        assertEquals(60, FastCompletionRule().evaluate(event(EventType.OFFER_COMPLETED, 3), ctx).score)
    }

    @Test
    fun `fast completion ignores other types and long plays`() {
        val ctx = RuleContext(mapOf("minSeconds" to 10), history())
        assertFalse(FastCompletionRule().evaluate(event(EventType.INSTALL, 3), ctx).triggered)
        assertTrue(!FastCompletionRule().evaluate(event(EventType.OFFER_COMPLETED, 30), ctx).triggered)
    }
}
