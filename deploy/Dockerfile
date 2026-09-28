# Runtime image of the backend. The jar is built on the Mac (deploy.sh) and copied next to this file:
# the small server does not need Maven or a JDK, and builds stay fast and reproducible.
FROM eclipse-temurin:25-jre

RUN useradd --system --no-create-home --shell /usr/sbin/nologin app \
 # Image storage; the Docker volume mounted here inherits this ownership on first use.
 && mkdir -p /data/blobs && chown app /data/blobs
WORKDIR /app
COPY app.jar app.jar
USER app

EXPOSE 8080
# MaxRAMPercentage: the JVM shares a 2 GB VM with PostgreSQL and Caddy.
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=40", "-jar", "app.jar"]
