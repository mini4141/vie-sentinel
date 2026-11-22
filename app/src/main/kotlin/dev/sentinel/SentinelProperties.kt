package dev.sentinel

import org.springframework.boot.context.properties.ConfigurationProperties

@ConfigurationProperties("sentinel")
data class SentinelProperties(
    val apiKey: String,
    val scoring: Scoring = Scoring(),
    val queue: Queue = Queue(),
) {
    data class Scoring(val blockThreshold: Int = 80, val reviewThreshold: Int = 40)

    data class Queue(val enabled: Boolean = true, val name: String = "sentinel-alerts")
}
