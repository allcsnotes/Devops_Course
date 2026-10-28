# syntax=docker/dockerfile:1
# allcsvideos Java services, one Dockerfile for all: --build-arg SERVICE=catalog-service
# (from Spring Boot M20-L02 / M07-L01: cached ~/.m2, layered jar, AOT cache; base images pinned)
ARG BUILD_IMAGE=maven:3.9.16-eclipse-temurin-25
ARG RUNTIME_IMAGE=gcr.io/distroless/java25-debian13:nonroot@sha256:a26596c2d590343eda0ab66e67f089fd612ef3a3b972acf9e57c39f99f7a88c6

# 1) build: resolve dependencies (cached), package, split the jar into layers
FROM ${BUILD_IMAGE} AS build
ARG SERVICE
WORKDIR /src
COPY pom.xml .
COPY ${SERVICE}/pom.xml ${SERVICE}/
RUN --mount=type=cache,id=do-m07b01-m2,target=/root/.m2 \
    mvn -B -q -f ${SERVICE}/pom.xml dependency:go-offline
COPY ${SERVICE}/src ${SERVICE}/src
RUN --mount=type=cache,id=do-m07b01-m2,target=/root/.m2 \
    mvn -B -q -DskipTests -f ${SERVICE}/pom.xml package
RUN java -Djarmode=tools -jar ${SERVICE}/target/${SERVICE}-0.0.1-SNAPSHOT.jar \
    extract --layers --destination /layers --application-filename app.jar
COPY probe/Probe.java /probe/
RUN javac -d /probe /probe/Probe.java

# 2) runtime: distroless Java (no shell, no package manager), user nonroot (65532)
FROM ${RUNTIME_IMAGE} AS runtime
WORKDIR /app
COPY --from=build /layers/dependencies/ ./
COPY --from=build /layers/spring-boot-loader/ ./
COPY --from=build /layers/snapshot-dependencies/ ./
COPY --from=build /layers/application/ ./
COPY --from=build /probe/Probe.class probe/
USER nonroot
# training run: start the context once, record the AOT cache, exit (faster start-up)
RUN ["java", "-XX:AOTCacheOutput=app.aot", \
     "-Dspring.context.exit=onRefresh", \
     "-Dspring.datasource.url=jdbc:postgresql:training", \
     "-Dspring.flyway.enabled=false", \
     "-Dspring.kafka.admin.auto-create=false", "-jar", "app.jar"]
ARG VERSION=dev
ENV APP_VERSION=${VERSION}
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=5s --start-period=60s --retries=3 \
  CMD ["java", "-XX:TieredStopAtLevel=1", "-XX:+UseSerialGC", "-Xmx16m", "-cp", "/app/probe", \
       "Probe", "http://127.0.0.1:8080/actuator/health"]
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=60", "-XX:AOTCache=app.aot", "-jar", "app.jar"]
