package dev.sentinel.api

import dev.sentinel.SentinelProperties
import jakarta.servlet.FilterChain
import jakarta.servlet.http.HttpServletRequest
import jakarta.servlet.http.HttpServletResponse
import org.springframework.stereotype.Component
import org.springframework.web.filter.OncePerRequestFilter
import java.security.MessageDigest

/** Requires `X-API-Key` on everything except the health endpoint. */
@Component
class ApiKeyFilter(props: SentinelProperties) : OncePerRequestFilter() {
    private val expected = props.apiKey.toByteArray()

    override fun shouldNotFilter(request: HttpServletRequest): Boolean =
        request.requestURI.startsWith("/actuator/health")

    override fun doFilterInternal(request: HttpServletRequest, response: HttpServletResponse, chain: FilterChain) {
        val provided = request.getHeader("X-API-Key")?.toByteArray()
        if (provided == null || !MessageDigest.isEqual(provided, expected)) {
            response.status = HttpServletResponse.SC_UNAUTHORIZED
            response.contentType = "application/json"
            response.writer.write("""{"error":"invalid or missing X-API-Key"}""")
            return
        }
        chain.doFilter(request, response)
    }
}
