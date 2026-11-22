package dev.sentinel.engine

import dev.sentinel.SentinelProperties
import dev.sentinel.persistence.RuleRepository
import dev.sentinel.rules.EventHistory
import dev.sentinel.rules.FraudEvent
import dev.sentinel.rules.Rule
import dev.sentinel.rules.RuleContext
import org.springframework.stereotype.Service

enum class Decision { ALLOW, REVIEW, BLOCK }

data class Scoring(val decision: Decision, val score: Int, val reasons: List<String>)

@Service
class ScoringEngine(
    rules: List<Rule>,
    private val ruleRepository: RuleRepository,
    private val history: EventHistory,
    private val props: SentinelProperties,
) {
    private val rulesById = rules.associateBy { it.id }

    fun score(event: FraudEvent): Scoring {
        var total = 0
        val reasons = mutableListOf<String>()
        for (config in ruleRepository.findAll().filter { it.enabled }) {
            val result = rulesById[config.id]?.evaluate(event, RuleContext(config.params, history))
            if (result == null || !result.triggered) continue
            if (config.shadow) {
                reasons += "[shadow] ${result.reason}"
            } else {
                total += result.score
                reasons += requireNotNull(result.reason)
            }
        }
        return Scoring(decide(total), total, reasons)
    }

    fun decide(score: Int): Decision = when {
        score >= props.scoring.blockThreshold -> Decision.BLOCK
        score >= props.scoring.reviewThreshold -> Decision.REVIEW
        else -> Decision.ALLOW
    }
}
