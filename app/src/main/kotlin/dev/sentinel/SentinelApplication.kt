package dev.sentinel

import org.springframework.boot.autoconfigure.SpringBootApplication
import org.springframework.boot.context.properties.ConfigurationPropertiesScan
import org.springframework.boot.runApplication

@SpringBootApplication
@ConfigurationPropertiesScan
class SentinelApplication

@Suppress("SpreadOperator")
fun main(args: Array<String>) {
    runApplication<SentinelApplication>(*args)
}
