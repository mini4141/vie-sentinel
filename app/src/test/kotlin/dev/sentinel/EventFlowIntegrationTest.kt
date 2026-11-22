package dev.sentinel

import dev.sentinel.api.EventResponse
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.test.web.client.TestRestTemplate
import org.springframework.boot.testcontainers.service.connection.ServiceConnection
import org.springframework.http.HttpEntity
import org.springframework.http.HttpHeaders
import org.springframework.http.HttpStatus
import org.springframework.jdbc.core.simple.JdbcClient
import org.testcontainers.containers.PostgreSQLContainer
import org.testcontainers.junit.jupiter.Container
import org.testcontainers.junit.jupiter.Testcontainers

@Testcontainers(disabledWithoutDocker = true)
@SpringBootTest(
    webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
    properties = ["sentinel.queue.enabled=false", "spring.cloud.aws.sqs.enabled=false", "sentinel.api-key=test-key"],
)
class EventFlowIntegrationTest(
    @Autowired private val rest: TestRestTemplate,
    @Autowired private val jdbc: JdbcClient,
) {
    companion object {
        @Container
        @ServiceConnection
        @JvmStatic
        val postgres = PostgreSQLContainer("postgres:16")
    }

    private fun post(body: String) = rest.postForEntity(
        "/events",
        HttpEntity(
            body,
            HttpHeaders().apply {
                set("X-API-Key", "test-key")
                set("Content-Type", "application/json")
            },
        ),
        EventResponse::class.java,
    )

    @Test
    fun `fast completion is stored as REVIEW and replay is idempotent`() {
        val body = """{"idempotencyKey":"it-1","userId":"u","deviceId":"d","ip":"1.1.1.1",
            "type":"OFFER_COMPLETED","playSeconds":2,"occurredAt":"2025-01-01T00:00:00Z"}"""

        val first = post(body)
        assertEquals(HttpStatus.OK, first.statusCode)
        assertEquals("REVIEW", first.body!!.decision.name)

        val replay = post(body)
        assertEquals(first.body!!.eventId, replay.body!!.eventId)
        assertEquals(1, jdbc.sql("SELECT count(*) FROM events WHERE idempotency_key = 'it-1'").query(Int::class.java).single())
        assertEquals(1, jdbc.sql("SELECT count(*) FROM cases").query(Int::class.java).single())
    }

    @Test
    fun `missing api key is rejected`() {
        assertEquals(HttpStatus.UNAUTHORIZED, rest.getForEntity("/rules", String::class.java).statusCode)
    }
}
