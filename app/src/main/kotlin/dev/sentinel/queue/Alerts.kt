package dev.sentinel.queue

import com.fasterxml.jackson.databind.ObjectMapper
import dev.sentinel.engine.Decision
import dev.sentinel.persistence.AlertRepository
import io.awspring.cloud.sqs.annotation.SqsListener
import io.awspring.cloud.sqs.operations.SqsTemplate
import io.micrometer.core.instrument.Counter
import io.micrometer.core.instrument.MeterRegistry
import org.slf4j.LoggerFactory
import org.springframework.beans.factory.annotation.Value
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty
import org.springframework.stereotype.Component
import java.util.UUID

data class AlertMessage(val eventId: UUID, val decision: Decision)

fun interface AlertPublisher {
    fun publish(message: AlertMessage)
}

/** Used when the queue is disabled (tests, no SQS available). */
@Component
@ConditionalOnProperty("sentinel.queue.enabled", havingValue = "false")
class NoOpAlertPublisher : AlertPublisher {
    override fun publish(message: AlertMessage) = Unit
}

@Component
@ConditionalOnProperty("sentinel.queue.enabled", havingValue = "true", matchIfMissing = true)
class SqsAlertPublisher(
    private val template: SqsTemplate,
    private val mapper: ObjectMapper,
    @Value("\${sentinel.queue.name}") private val queue: String,
) : AlertPublisher {
    override fun publish(message: AlertMessage) {
        template.send { it.queue(queue).payload(mapper.writeValueAsString(message)) }
    }
}

/** Consumes REVIEW/BLOCK alerts from SQS (same process), stores them and counts them. */
@Component
@ConditionalOnProperty("sentinel.queue.enabled", havingValue = "true", matchIfMissing = true)
class AlertListener(
    private val alerts: AlertRepository,
    private val mapper: ObjectMapper,
    registry: MeterRegistry,
) {
    private val log = LoggerFactory.getLogger(javaClass)
    private val counter: Counter = Counter.builder("sentinel.alerts").description("Alerts consumed from SQS").register(registry)

    @SqsListener("\${sentinel.queue.name}")
    fun onMessage(body: String) {
        val msg = mapper.readValue(body, AlertMessage::class.java)
        if (alerts.insert(msg.eventId, msg.decision.name)) {
            counter.increment()
            log.info("alert stored eventId={} decision={}", msg.eventId, msg.decision)
        }
    }
}
