# syntax=docker/dockerfile:1
# "AFTER" version: multi-stage build + Spring Boot layers + distroless runtime (no shell, non-root).
# Base images are pinned by digest (tags are mutable).

# 1) Build on the official Maven image: Maven is already installed and verified through the image
#    digest, so the build installs no packages and does not download Maven itself.
FROM maven:3.10.2-eclipse-temurin-25@sha256:fdb6138e3d3600784c9e5f540d34d89c5c7c6074f80f611abd2c6025d9b81ef7 AS build
WORKDIR /src

# The image's Maven must be the version the Maven Wrapper uses locally and in CI.
COPY .mvn/wrapper/maven-wrapper.properties ./
RUN expected="$(sed -n 's#^distributionUrl=.*/apache-maven-\(.*\)-bin\.zip$#\1#p' maven-wrapper.properties)" \
    && actual="$(mvn -v | sed -n 's/^Apache Maven \([^ ]*\).*/\1/p')" \
    && if [ "$expected" != "$actual" ]; then \
         echo "Maven $actual in the image but $expected in the wrapper: update both together" >&2; \
         exit 1; \
       fi

# Resolve exactly what `package` needs (dependencies and plugins) by building the project once
# without sources. This layer is reused until pom.xml changes.
COPY pom.xml ./
RUN mvn -B -q -ntp package -DskipTests -Djacoco.skip=true -Dspring-boot.repackage.skip=true

# Compile the application and split the jar into layers: dependencies rarely change,
# application code changes often.
COPY src/ src/
RUN mvn -B -q -ntp package -DskipTests -Djacoco.skip=true \
    && java -Djarmode=tools -jar target/order-api.jar extract --layers --launcher --destination /layers

# 2) Runtime: just the JRE, no shell, no package manager, non-root user.
FROM gcr.io/distroless/java25-debian13:nonroot@sha256:4618e7a1a1f5177222985347e1ffd503076f6be5837b89c8fd02800bd8551bde
WORKDIR /app
COPY --from=build /layers/dependencies/ ./
COPY --from=build /layers/spring-boot-loader/ ./
COPY --from=build /layers/snapshot-dependencies/ ./
COPY --from=build /layers/application/ ./
EXPOSE 8080
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75", "org.springframework.boot.loader.launch.JarLauncher"]
