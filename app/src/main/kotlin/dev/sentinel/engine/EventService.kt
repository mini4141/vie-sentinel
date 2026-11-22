package dev.sentinel.engine

import dev.sentinel.persistence.CaseRepository
import dev.sentinel.persistence.EventRepository
import dev.sentinel.persistence.StoredEvent
import dev.sentinel.queue.AlertMessage
import dev.sentinel.queue.AlertPublisher
import dev.sentinel.rules.FraudEvent
import org.slf4j.LoggerFactory
import org.springframework.stereotype.Service
import org.springframework.transaction.support.TransactionTemplate
import java.util.UUID

/** Orchestrates scoring, idempotent persistence, case creation and alert publishing. */
@Service
class EventService(
    private val engine: ScoringEngine,
    private val events: EventRepository,
    private val cases: CaseRepository,
    private val publisher: AlertPublisher,
    private val tx: TransactionTemplate,
) {
    private val log = LoggerFactory.getLogger(javaClass)

    fun process(event: FraudEvent): StoredEvent {
        events.findByKey(event.idempotencyKey)?.let { return it }

        val scoring = engine.score(event)
        val id = UUID.randomUUID()
        val inserted = tx.execute {
            val ok = events.insert(id, event, scoring.decision, scoring.score, scoring.reasons)
            if (ok && scoring.decision == Decision.REVIEW) cases.create(id)
            ok
        } == true

        if (!inserted) {
            // lost a race with a concurrent request using the same key
            return requireNotNull(events.findByKey(event.idempotencyKey))
        }
        if (scoring.decision != Decision.ALLOW) publish(AlertMessage(id, scoring.decision))
        return StoredEvent(id, scoring.decision, scoring.score, scoring.reasons)
    }

    private fun publish(message: AlertMessage) {
        try {
            publisher.publish(message)
        } catch (
            @Suppress("TooGenericExceptionCaught") e: Exception,
        ) {
            // the decision is already stored; alerting is best effort
            log.warn("failed to publish alert eventId={}", message.eventId, e)
        }
    }
}
