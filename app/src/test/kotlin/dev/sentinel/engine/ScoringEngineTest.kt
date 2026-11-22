package dev.sentinel.engine

import dev.sentinel.SentinelProperties
import dev.sentinel.persistence.RuleRepository
import dev.sentinel.rules.EventHistory
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import org.mockito.Mockito.mock

class ScoringEngineTest {
    private val engine = ScoringEngine(
        emptyList(),
        mock(RuleRepository::class.java),
        mock(EventHistory::class.java),
        SentinelProperties(apiKey = "k"),
    )

    @Test
    fun `thresholds map score to decision`() {
        assertEquals(Decision.ALLOW, engine.decide(39))
        assertEquals(Decision.REVIEW, engine.decide(40))
        assertEquals(Decision.REVIEW, engine.decide(79))
        assertEquals(Decision.BLOCK, engine.decide(80))
    }

    @Test
    fun `no rules means zero score and allow`() {
        val result = engine.score(
            dev.sentinel.rules.FraudEvent(
                "k", "u", "d", "ip", dev.sentinel.rules.EventType.INSTALL, null, null, java.time.Instant.now(),
            ),
        )
        assertEquals(Decision.ALLOW, result.decision)
    }
}
