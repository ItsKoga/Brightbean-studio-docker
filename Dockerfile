# All-in-one Brightbean Studio image for Docker / Unraid.
#
# BASE_IMAGE is upstream's own image, built from its Dockerfile (see Makefile
# and .github/workflows/build.yml). This layer only adds PostgreSQL, supervisor
# and the container entrypoint on top.
ARG BASE_IMAGE=brightbean-studio-base:local
FROM ${BASE_IMAGE}

ARG UPSTREAM_SHA=unknown
ARG PG_MAJOR=16

# PostgreSQL from PGDG so the major version matches upstream's compose
# (postgres:16) regardless of the Debian release under python:3.12-slim.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl gnupg supervisor gosu; \
    . /etc/os-release; \
    install -d /usr/share/postgresql-common/pgdg; \
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
        | gpg --dearmor -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.gpg; \
    echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.gpg] https://apt.postgresql.org/pub/repos/apt ${VERSION_CODENAME}-pgdg main" \
        > /etc/apt/sources.list.d/pgdg.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends postgresql-${PG_MAJOR}; \
    rm -rf /var/lib/apt/lists/*; \
    gosu nobody true

ENV PG_MAJOR=${PG_MAJOR} \
    PATH=/usr/lib/postgresql/${PG_MAJOR}/bin:${PATH} \
    DJANGO_SETTINGS_MODULE=config.settings.container \
    PORT=8000 \
    PUID=99 \
    PGID=100

COPY rootfs/app-overlay/ /app/
COPY rootfs/etc/ /etc/
COPY rootfs/usr/ /usr/
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/bb-run

LABEL org.opencontainers.image.title="Brightbean Studio (all-in-one)" \
      org.opencontainers.image.description="Self-hostable social media management platform, packaged for Docker and Unraid" \
      org.opencontainers.image.licenses="AGPL-3.0" \
      org.opencontainers.image.revision="${UPSTREAM_SHA}" \
      io.brightbean.upstream.revision="${UPSTREAM_SHA}"

VOLUME ["/config", "/app/media"]
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD curl -fsS "http://127.0.0.1:${PORT}/health/" || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
