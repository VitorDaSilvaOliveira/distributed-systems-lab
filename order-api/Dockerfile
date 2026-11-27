# syntax=docker/dockerfile:1
# "AFTER" version: multi-stage build + Spring Boot layers + distroless runtime (no shell, non-root).
# Base images are pinned by digest (tags are mutable); Dependabot keeps the digests current.

# 1) Build: resolve dependencies in their own cached layer, then compile.
#    The Maven Wrapper pins the exact Maven version (and its checksum) used locally and in CI.
FROM eclipse-temurin:25-jdk@sha256:ce2ef9d2d67a68de5e196d4de9d743327c44a10b57fe02ec39f572c652cacfd3 AS build
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
FROM eclipse-temurin:25-jre@sha256:4ed132f6832e9804b123e89a849a7b4502756ae64a4ee08ebab939d9d5d0a9fa AS extract
WORKDIR /extract
COPY --from=build /src/target/order-api.jar app.jar
RUN java -Djarmode=tools -jar app.jar extract --layers --launcher --destination layers

# 3) Runtime: just the JRE, no shell, no package manager, non-root user.
FROM gcr.io/distroless/java25-debian13:nonroot@sha256:4618e7a1a1f5177222985347e1ffd503076f6be5837b89c8fd02800bd8551bde
WORKDIR /app
COPY --from=extract /extract/layers/dependencies/ ./
COPY --from=extract /extract/layers/spring-boot-loader/ ./
COPY --from=extract /extract/layers/snapshot-dependencies/ ./
COPY --from=extract /extract/layers/application/ ./
EXPOSE 8080
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75", "org.springframework.boot.loader.launch.JarLauncher"]
