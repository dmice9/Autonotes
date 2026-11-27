FROM eclipse-temurin:24-jdk-noble@sha256:dacac8e9a0df0d2bd24e702b4431132875c249930b70555ebd7ca285b5bee684 AS builder

WORKDIR /app

COPY build.gradle* settings.gradle* ./
COPY gradlew ./
COPY gradle ./gradle

RUN chmod +x ./gradlew
ENV GRADLE_OPTS="-Dorg.gradle.internal.http.connectionTimeout=60000 -Dorg.gradle.internal.http.socketTimeout=60000"

RUN for i in 1 2 3; do ./gradlew dependencies --no-daemon && break || sleep 5; done || true

COPY src ./src
COPY config ./config

RUN for i in 1 2 3; do ./gradlew copyOtelAgent bootJar --no-daemon && break || sleep 5; done

FROM eclipse-temurin:24-jre-noble@sha256:b416d02335e702b0403ff280de9475a3348e29382285969c9d4e17862ce632e7

WORKDIR /app

COPY --from=builder /app/build/libs/*.jar app.jar
COPY --from=builder /app/build/otel-agent/opentelemetry-javaagent.jar otel-agent.jar

EXPOSE 8080

ENTRYPOINT ["java", "-javaagent:/app/otel-agent.jar", "-jar", "app.jar"]
