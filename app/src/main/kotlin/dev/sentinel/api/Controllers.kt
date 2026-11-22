package dev.sentinel.api

import dev.sentinel.engine.Decision
import dev.sentinel.engine.EventService
import dev.sentinel.persistence.CaseRepository
import dev.sentinel.persistence.CaseRow
import dev.sentinel.persistence.RuleRepository
import dev.sentinel.persistence.RuleRow
import dev.sentinel.rules.EventType
import dev.sentinel.rules.FraudEvent
import jakarta.validation.Valid
import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.NotNull
import org.springframework.http.HttpStatus
import org.springframework.transaction.support.TransactionTemplate
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.PutMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestHeader
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.RestController
import org.springframework.web.server.ResponseStatusException
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID

data class EventRequest(
    @field:NotBlank val idempotencyKey: String,
    @field:NotBlank val userId: String,
    @field:NotBlank val deviceId: String,
    @field:NotBlank val ip: String,
    @field:NotNull val type: EventType,
    val amount: BigDecimal? = null,
    val playSeconds: Int? = null,
    @field:NotNull val occurredAt: Instant,
)

data class EventResponse(val eventId: UUID, val decision: Decision, val score: Int, val reasons: List<String>)

enum class ResolveStatus { APPROVED, REJECTED }

data class ResolveRequest(@field:NotNull val status: ResolveStatus)

data class RuleUpdate(
    @field:NotNull val enabled: Boolean,
    @field:NotNull val shadow: Boolean,
    val params: Map<String, Any?> = emptyMap(),
)

data class RuleResponse(
    val id: String,
    val enabled: Boolean,
    val shadow: Boolean,
    val params: Map<String, Any?>,
    val updatedAt: Instant,
    val auditId: Long? = null,
)

private fun RuleRow.toResponse(auditId: Long? = null) = RuleResponse(id, enabled, shadow, params, updatedAt, auditId)

@RestController
class EventController(private val service: EventService) {
    @PostMapping("/events")
    fun create(@Valid @RequestBody req: EventRequest): EventResponse {
        val stored = service.process(
            FraudEvent(
                req.idempotencyKey, req.userId, req.deviceId, req.ip, req.type,
                req.amount, req.playSeconds, req.occurredAt,
            ),
        )
        return EventResponse(stored.id, stored.decision, stored.score, stored.reasons)
    }
}

@RestController
class CaseController(private val cases: CaseRepository) {
    @GetMapping("/cases")
    fun list(@RequestParam(defaultValue = "OPEN") status: String): List<CaseRow> = cases.list(status)

    @PostMapping("/cases/{id}/resolve")
    fun resolve(@PathVariable id: UUID, @Valid @RequestBody req: ResolveRequest): CaseRow =
        cases.resolve(id, req.status.name) ?: throw ResponseStatusException(HttpStatus.NOT_FOUND, "case not found")
}

@RestController
class RuleController(private val rules: RuleRepository, private val tx: TransactionTemplate) {
    @GetMapping("/rules")
    fun list(): List<RuleResponse> = rules.findAll().map { it.toResponse() }

    @PutMapping("/rules/{id}")
    fun update(
        @PathVariable id: String,
        @Valid @RequestBody req: RuleUpdate,
        @RequestHeader("X-Actor", required = false) actor: String?,
    ): RuleResponse =
        tx.execute {
            val row = rules.update(id, req.enabled, req.shadow, req.params)
                ?: throw ResponseStatusException(HttpStatus.NOT_FOUND, "rule not found")
            val change = mapOf("enabled" to req.enabled, "shadow" to req.shadow, "params" to req.params)
            row.toResponse(rules.audit(id, actor?.takeIf { it.isNotBlank() } ?: "api-key", change))
        } ?: error("transaction returned null")
}
