# syntax=docker/dockerfile:1
FROM gradle:8.12-jdk21 AS build
WORKDIR /workspace
COPY settings.gradle.kts build.gradle.kts ./
# warm the dependency cache in its own layer
RUN gradle dependencies --no-daemon -q > /dev/null 2>&1 || true
COPY src ./src
RUN gradle bootJar --no-daemon -q

FROM eclipse-temurin:21-jre
RUN groupadd --system sentinel && useradd --system --gid sentinel --no-create-home sentinel
WORKDIR /app
COPY --from=build /workspace/build/libs/sentinel.jar app.jar
USER sentinel
ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75 -XX:+UseSerialGC" \
    LOGGING_STRUCTURED_FORMAT_CONSOLE=logstash
EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=3s --start-period=60s --retries=5 \
  CMD curl -fs http://localhost:8080/actuator/health || exit 1
ENTRYPOINT ["java", "-jar", "app.jar"]
