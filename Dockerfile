# syntax=docker/dockerfile:1.4

ARG PYTHON_VERSION=3.9
ARG PACKAGE=pgbouncer
ARG TARGET_DIR=pgbouncer
ARG VERSION=1.19.1

FROM public.ecr.aws/bitcompat/python:${PYTHON_VERSION} as python
FROM public.ecr.aws/bitcompat/ini-file:latest as ini-file
FROM public.ecr.aws/bitcompat/nss-wrapper:latest as nss-wrapper
FROM public.ecr.aws/bitcompat/wait-for-port:latest as wait-for-port
FROM public.ecr.aws/bitcompat/postgresql:14 as postgresql

FROM docker.io/bitnami/minideb:bullseye AS builder

ARG PACKAGE
ARG TARGET_DIR
# renovate: datasource=github-releases depName=pgbouncer/pgbouncer versioning=loose extractVersion=^pgbouncer_(?<version>.+)$
ARG VERSION
ARG TARGETARCH

ARG PATH="/opt/bitnami/python/bin:$PATH"
ARG LD_LIBRARY_PATH=/opt/bitnami/python/lib/
RUN install_packages git curl ca-certificates autoconf automake build-essential g++ libtool pkg-config
RUN install_packages libevent-dev libssl-dev pandoc

COPY --from=python /opt/bitnami/python /opt/bitnami/python
COPY --link --from=ini-file /opt/bitnami/common /opt/bitnami/common
COPY --link --from=nss-wrapper /opt/bitnami/common /opt/bitnami/common
COPY --link --from=wait-for-port /opt/bitnami/common /opt/bitnami/common
COPY --link --from=postgresql /opt/bitnami/postgresql/bin/pg_dump* /opt/bitnami/postgresql/bin/
COPY --link --from=postgresql /opt/bitnami/postgresql/bin/pg_restore /opt/bitnami/postgresql/bin/
COPY --link --from=postgresql /opt/bitnami/postgresql/bin/psql /opt/bitnami/postgresql/bin/
COPY --link --from=postgresql /opt/bitnami/postgresql/lib/libpq.so* /opt/bitnami/postgresql/lib/

COPY --link prebuildfs /

RUN <<EOT /bin/bash
    set -ex

    export REF=pgbouncer_$(echo "${VERSION}" | tr . _)
    rm -rf ${PACKAGE} || true
    mkdir -p ${PACKAGE}
    git clone -b "\${REF}" https://github.com/pgbouncer/pgbouncer ${PACKAGE}

    pushd ${PACKAGE}
    git submodule update --init --recursive
    mkdir -p /opt/bitnami/${TARGET_DIR}/licenses
    cp -f COPYRIGHT /opt/bitnami/${TARGET_DIR}/licenses/${PACKAGE}-${VERSION}.txt

    ./autogen.sh
    ./configure --prefix=/opt/bitnami/${TARGET_DIR}
    make -j$(nproc)
    make install
    popd

    rm -rf ${PACKAGE}
EOT

ARG DIRS_TO_TRIM="/opt/bitnami/pgbouncer/share/man \
/opt/bitnami/pgbouncer/share/doc \
/opt/bitnami/python \
"

RUN <<EOT bash
    for DIR in $DIRS_TO_TRIM; do
      find \$DIR/ -delete -print
    done
EOT

RUN rm -rf /opt/bitnami/python
RUN find /opt/bitnami/pgbouncer -executable -type f | xargs strip --strip-unneeded || true

FROM docker.io/bitnami/minideb:bullseye as stage-0

ARG TARGETARCH
ARG VERSION
ARG PACKAGE
ENV HOME="/" \
    OS_ARCH="${TARGETARCH}" \
    OS_FLAVOUR="debian-11" \
    OS_NAME="linux" \
    APP_VERSION="${VERSION}" \
    BITNAMI_APP_NAME="${PACKAGE}" \
    LD_LIBRARY_PATH=/opt/bitnami/postgresql/lib/ \
    PATH="/opt/bitnami/${PACKAGE}/bin:/opt/bitnami/common/bin:$PATH"

LABEL org.opencontainers.image.ref.name="${VERSION}-debian-11-r1" \
      org.opencontainers.image.title="${PACKAGE}" \
      org.opencontainers.image.version="${VERSION}"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Install required system packages and dependencies
COPY --link rootfs /
COPY --link --from=builder /opt/bitnami/ /opt/bitnami/
RUN <<EOT /bin/bash
  install_packages ca-certificates gzip procps tar libevent-2.1 locales libreadline8
  mkdir -p /bitnami/pgbouncer/conf
  mkdir -p /docker-entrypoint-initdb.d
  mkdir -p /opt/bitnami/pgbouncer/conf
  mkdir -p /opt/bitnami/pgbouncer/logs
  mkdir -p /opt/bitnami/pgbouncer/tmp

  chown -R 1001 /bitnami/pgbouncer/conf
  chown -R 1001 /docker-entrypoint-initdb.d
  chown -R 1001 /opt/bitnami/pgbouncer/conf
  chown -R 1001 /opt/bitnami/pgbouncer/logs
  chown -R 1001 /opt/bitnami/pgbouncer/tmp
EOT

EXPOSE 6432

WORKDIR /opt/bitnami/pgbouncer
USER 1001
ENTRYPOINT [ "/opt/bitnami/scripts/pgbouncer/entrypoint.sh" ]
CMD [ "/opt/bitnami/scripts/pgbouncer/run.sh" ]
