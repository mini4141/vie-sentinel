package dev.sentinel.rules

import java.math.BigDecimal
import java.time.Instant

enum class EventType { INSTALL, OFFER_COMPLETED, REDEEM }

/** The event as seen by rules; independent of the HTTP DTO. */
data class FraudEvent(
    val idempotencyKey: String,
    val userId: String,
    val deviceId: String,
    val ip: String,
    val type: EventType,
    val amount: BigDecimal?,
    val playSeconds: Int?,
    val occurredAt: Instant,
)

/** Read access to previously stored events. */
interface EventHistory {
    fun countByUser(userId: String, from: Instant, to: Instant): Int

    fun distinctUsersOnDevice(deviceId: String): Set<String>
}

data class RuleContext(val params: Map<String, Any?>, val history: EventHistory) {
    fun int(key: String, default: Int): Int = (params[key] as? Number)?.toInt() ?: default
}

data class RuleResult(val score: Int = 0, val reason: String? = null) {
    val triggered: Boolean get() = score > 0
}

interface Rule {
    val id: String

    fun evaluate(event: FraudEvent, ctx: RuleContext): RuleResult
}
