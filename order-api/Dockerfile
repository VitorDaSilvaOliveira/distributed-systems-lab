# syntax=docker/dockerfile:1
# "AFTER" version: multi-stage build + Spring Boot layers + distroless runtime (no shell, non-root).

# 1) Build: resolve dependencies in their own cached layer, then compile.
#    The Maven Wrapper pins the exact Maven version (and its checksum) used locally and in CI.
FROM eclipse-temurin:21-jdk AS build
# Without unzip, mvnw silently downloads the .tar.gz instead of the .zip and the pinned
# distributionSha256Sum (computed for the .zip) no longer matches.
RUN apt-get update \
    && apt-get install -y --no-install-recommends unzip \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY .mvn/ .mvn/
COPY mvnw pom.xml ./
RUN --mount=type=cache,target=/root/.m2 ./mvnw -B -q dependency:go-offline
COPY src/ src/
RUN --mount=type=cache,target=/root/.m2 ./mvnw -B -q package -DskipTests

# 2) Split the jar into layers: dependencies rarely change, application code changes often.
FROM eclipse-temurin:21-jre AS extract
WORKDIR /extract
COPY --from=build /src/target/order-api.jar app.jar
RUN java -Djarmode=tools -jar app.jar extract --layers --launcher --destination layers

# 3) Runtime: just the JRE, no shell, no package manager, non-root user.
FROM gcr.io/distroless/java21-debian12:nonroot
WORKDIR /app
COPY --from=extract /extract/layers/dependencies/ ./
COPY --from=extract /extract/layers/spring-boot-loader/ ./
COPY --from=extract /extract/layers/snapshot-dependencies/ ./
COPY --from=extract /extract/layers/application/ ./
EXPOSE 8080
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75", "org.springframework.boot.loader.launch.JarLauncher"]
