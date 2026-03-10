FROM docker.io/library/maven:3.9.12-eclipse-temurin-17 AS build-hapi
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /tmp/hapi-fhir-jpaserver-starter

ARG OPENTELEMETRY_JAVA_AGENT_VERSION=2.24.0
RUN curl -LSsO https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v${OPENTELEMETRY_JAVA_AGENT_VERSION}/opentelemetry-javaagent.jar

COPY pom.xml .
COPY server.xml .

COPY src/ /tmp/hapi-fhir-jpaserver-starter/src/
RUN mvn clean install -DskipTests -Djdk.lang.Process.launchMechanism=vfork

FROM build-hapi AS build-distroless
RUN mvn package -DskipTests spring-boot:repackage -Pboot
RUN mkdir /app && cp /tmp/hapi-fhir-jpaserver-starter/target/ROOT.war /app/main.war

########### Variante Tomcat (optionnelle)
FROM docker.io/library/tomcat:10-jre21-temurin-noble AS tomcat

USER root
RUN rm -rf /usr/local/tomcat/webapps/ROOT && \
    mkdir -p /usr/local/tomcat/data/hapi/lucenefiles && \
    chown -R 65532:65532 /usr/local/tomcat/data/hapi/lucenefiles && \
    chmod 775 /usr/local/tomcat/data/hapi/lucenefiles

RUN mkdir -p /target && chown -R 65532:65532 /target
USER 65532

COPY --chown=65532:65532 catalina.properties /usr/local/tomcat/conf/catalina.properties
COPY --chown=65532:65532 server.xml /usr/local/tomcat/conf/server.xml
COPY --from=build-hapi --chown=65532:65532 /tmp/hapi-fhir-jpaserver-starter/target/ROOT.war /usr/local/tomcat/webapps/ROOT.war
COPY --from=build-hapi --chown=65532:65532 /tmp/hapi-fhir-jpaserver-starter/opentelemetry-javaagent.jar /app

########### Image finale Alpine - moins de vulnerabilites OS
FROM eclipse-temurin:17-jre-alpine AS default

# Mise a jour des packages Alpine
RUN apk update && apk upgrade && rm -rf /var/cache/apk/*

# Alpine utilise adduser au lieu de useradd
RUN adduser -D -u 65532 appuser

WORKDIR /app

COPY --from=build-distroless --chown=65532:65532 /app /app
COPY --from=build-hapi --chown=65532:65532 /tmp/hapi-fhir-jpaserver-starter/opentelemetry-javaagent.jar /app

USER 65532:65532

ENTRYPOINT ["java", "--class-path", "/app/main.war", "-Dloader.path=main.war!/WEB-INF/classes/,main.war!/WEB-INF/,/app/extra-classes", "org.springframework.boot.loader.PropertiesLauncher"]