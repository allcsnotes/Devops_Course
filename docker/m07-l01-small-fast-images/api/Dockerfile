# syntax=docker/dockerfile:1
# v3: cache mounts for ~/.m2 + a layered jar; base images are build args
ARG BUILD_IMAGE=maven:3.9.16-eclipse-temurin-25
ARG RUNTIME_IMAGE=eclipse-temurin:25.0.4.1_1-jre

FROM ${BUILD_IMAGE} AS build
WORKDIR /src
COPY pom.xml .
COPY gateway/pom.xml gateway/
RUN --mount=type=cache,id=small-m2,target=/root/.m2 \
    mvn -B -f gateway/pom.xml dependency:go-offline
COPY gateway/src gateway/src
RUN --mount=type=cache,id=small-m2,target=/root/.m2 \
    mvn -B -DskipTests -f gateway/pom.xml package
RUN java -Djarmode=tools -jar gateway/target/gateway-0.0.1-SNAPSHOT.jar \
    extract --layers --destination /layers --application-filename app.jar

FROM ${RUNTIME_IMAGE}
WORKDIR /app
COPY --from=build /layers/dependencies/ ./
COPY --from=build /layers/spring-boot-loader/ ./
COPY --from=build /layers/snapshot-dependencies/ ./
COPY --from=build /layers/application/ ./
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
