package dev.sentinel.rules

import org.springframework.stereotype.Component
import java.time.Duration

@Component
class VelocityRule : Rule {
    override val id = "velocity"

    override fun evaluate(event: FraudEvent, ctx: RuleContext): RuleResult {
        val max = ctx.int("maxEvents", 5)
        val window = ctx.int("windowSeconds", 60)
        val from = event.occurredAt.minus(Duration.ofSeconds(window.toLong()))
        // stored events in the window plus the current one
        val count = ctx.history.countByUser(event.userId, from, event.occurredAt) + 1
        return if (count > max) RuleResult(50, "velocity: $count events in ${window}s (max $max)") else RuleResult()
    }
}

@Component
class DeviceSharingRule : Rule {
    override val id = "device_sharing"

    override fun evaluate(event: FraudEvent, ctx: RuleContext): RuleResult {
        val max = ctx.int("maxUsers", 3)
        val users = ctx.history.distinctUsersOnDevice(event.deviceId) + event.userId
        return if (users.size > max) {
            RuleResult(40, "device_sharing: ${users.size} users on device (max $max)")
        } else {
            RuleResult()
        }
    }
}

@Component
class FastCompletionRule : Rule {
    override val id = "fast_completion"

    override fun evaluate(event: FraudEvent, ctx: RuleContext): RuleResult {
        val min = ctx.int("minSeconds", 10)
        val played = event.playSeconds
        return if (event.type == EventType.OFFER_COMPLETED && played != null && played < min) {
            RuleResult(60, "fast_completion: ${played}s played (min $min)")
        } else {
            RuleResult()
        }
    }
}
