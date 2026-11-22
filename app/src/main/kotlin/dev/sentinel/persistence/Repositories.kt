package dev.sentinel.persistence

import com.fasterxml.jackson.core.type.TypeReference
import com.fasterxml.jackson.databind.ObjectMapper
import dev.sentinel.engine.Decision
import dev.sentinel.rules.EventHistory
import dev.sentinel.rules.FraudEvent
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.stereotype.Repository
import java.sql.ResultSet
import java.sql.Timestamp
import java.time.Instant
import java.util.UUID

data class StoredEvent(
    val id: UUID,
    val decision: Decision,
    val score: Int,
    val reasons: List<String>,
)

data class CaseRow(val id: UUID, val eventId: UUID, val status: String, val createdAt: Instant, val resolvedAt: Instant?)

data class RuleRow(val id: String, val enabled: Boolean, val shadow: Boolean, val params: Map<String, Any?>, val updatedAt: Instant)

@Repository
class EventRepository(private val jdbc: JdbcClient, private val mapper: ObjectMapper) : EventHistory {
    fun findByKey(key: String): StoredEvent? =
        jdbc.sql("SELECT id, decision, score, reasons FROM events WHERE idempotency_key = :key")
            .param("key", key)
            .query { rs, _ ->
                StoredEvent(
                    rs.getObject("id", UUID::class.java),
                    Decision.valueOf(rs.getString("decision")),
                    rs.getInt("score"),
                    mapper.readValue(rs.getString("reasons"), object : TypeReference<List<String>>() {}),
                )
            }
            .optional()
            .orElse(null)

    /** Returns false when another request already stored the same idempotency key. */
    fun insert(id: UUID, event: FraudEvent, decision: Decision, score: Int, reasons: List<String>): Boolean =
        jdbc.sql(
            """
            INSERT INTO events (id, idempotency_key, user_id, device_id, ip, type, amount, play_seconds,
                                occurred_at, decision, score, reasons)
            VALUES (:id, :key, :userId, :deviceId, :ip, :type, :amount, :playSeconds,
                    :occurredAt, :decision, :score, CAST(:reasons AS jsonb))
            ON CONFLICT (idempotency_key) DO NOTHING
            """.trimIndent(),
        )
            .param("id", id)
            .param("key", event.idempotencyKey)
            .param("userId", event.userId)
            .param("deviceId", event.deviceId)
            .param("ip", event.ip)
            .param("type", event.type.name)
            .param("amount", event.amount)
            .param("playSeconds", event.playSeconds)
            .param("occurredAt", Timestamp.from(event.occurredAt))
            .param("decision", decision.name)
            .param("score", score)
            .param("reasons", mapper.writeValueAsString(reasons))
            .update() == 1

    override fun countByUser(userId: String, from: Instant, to: Instant): Int =
        jdbc.sql("SELECT count(*) FROM events WHERE user_id = :u AND occurred_at > :from AND occurred_at <= :to")
            .param("u", userId)
            .param("from", Timestamp.from(from))
            .param("to", Timestamp.from(to))
            .query(Int::class.java)
            .single()

    override fun distinctUsersOnDevice(deviceId: String): Set<String> =
        jdbc.sql("SELECT DISTINCT user_id FROM events WHERE device_id = :d")
            .param("d", deviceId)
            .query(String::class.java)
            .set()
}

@Repository
class CaseRepository(private val jdbc: JdbcClient) {
    fun create(eventId: UUID) {
        jdbc.sql("INSERT INTO cases (id, event_id, status) VALUES (:id, :eventId, 'OPEN')")
            .param("id", UUID.randomUUID())
            .param("eventId", eventId)
            .update()
    }

    fun list(status: String): List<CaseRow> =
        jdbc.sql("SELECT * FROM cases WHERE status = :s ORDER BY created_at DESC LIMIT 100")
            .param("s", status)
            .query { rs, _ -> map(rs) }
            .list()

    fun resolve(id: UUID, status: String): CaseRow? =
        jdbc.sql("UPDATE cases SET status = :s, resolved_at = now() WHERE id = :id RETURNING *")
            .param("s", status)
            .param("id", id)
            .query { rs, _ -> map(rs) }
            .optional()
            .orElse(null)

    private fun map(rs: ResultSet) = CaseRow(
        rs.getObject("id", UUID::class.java),
        rs.getObject("event_id", UUID::class.java),
        rs.getString("status"),
        rs.getTimestamp("created_at").toInstant(),
        rs.getTimestamp("resolved_at")?.toInstant(),
    )
}

@Repository
class RuleRepository(private val jdbc: JdbcClient, private val mapper: ObjectMapper) {
    fun findAll(): List<RuleRow> =
        jdbc.sql("SELECT * FROM rules ORDER BY id").query { rs, _ -> map(rs) }.list()

    fun update(id: String, enabled: Boolean, shadow: Boolean, params: Map<String, Any?>): RuleRow? =
        jdbc.sql(
            "UPDATE rules SET enabled = :e, shadow = :s, params = CAST(:p AS jsonb), updated_at = now() WHERE id = :id RETURNING *",
        )
            .param("e", enabled)
            .param("s", shadow)
            .param("p", mapper.writeValueAsString(params))
            .param("id", id)
            .query { rs, _ -> map(rs) }
            .optional()
            .orElse(null)

    fun audit(ruleId: String, changedBy: String, change: Map<String, Any?>): Long =
        jdbc.sql("INSERT INTO rule_audit (rule_id, changed_by, change) VALUES (:r, :by, CAST(:c AS jsonb)) RETURNING id")
            .param("r", ruleId)
            .param("by", changedBy)
            .param("c", mapper.writeValueAsString(change))
            .query(Long::class.java)
            .single()

    private fun map(rs: ResultSet) = RuleRow(
        rs.getString("id"),
        rs.getBoolean("enabled"),
        rs.getBoolean("shadow"),
        mapper.readValue(rs.getString("params"), object : TypeReference<Map<String, Any?>>() {}),
        rs.getTimestamp("updated_at").toInstant(),
    )
}

@Repository
class AlertRepository(private val jdbc: JdbcClient) {
    /** Idempotent: returns false if an alert for this event already exists. */
    fun insert(eventId: UUID, decision: String): Boolean =
        jdbc.sql("INSERT INTO alerts (event_id, decision) VALUES (:e, :d) ON CONFLICT (event_id) DO NOTHING")
            .param("e", eventId)
            .param("d", decision)
            .update() == 1
}
