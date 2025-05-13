# Build stage
FROM docker.io/library/golang:1.24-alpine3.21 AS build-env

ARG GOPROXY
ENV GOPROXY=${GOPROXY:-direct}

ARG GITEA_VERSION
ARG TAGS=""
ENV TAGS="bindata timetzdata $TAGS"
ARG CGO_EXTRA_CFLAGS

RUN apk --no-cache add \
    build-base \
    git \
    nodejs \
    npm \
    && rm -rf /var/cache/apk/*

COPY . ${GOPATH}/src/code.gitea.io/gitea
WORKDIR ${GOPATH}/src/code.gitea.io/gitea

RUN if [ -n "${GITEA_VERSION}" ]; then git checkout "${GITEA_VERSION}"; fi \
 && make clean-all build

RUN go build contrib/environment-to-ini/environment-to-ini.go

COPY docker/root /tmp/local

RUN chmod 755 /tmp/local/usr/bin/entrypoint \
              /tmp/local/usr/local/bin/gitea \
              /tmp/local/etc/s6/gitea/* \
              /tmp/local/etc/s6/openssh/* \
              /tmp/local/etc/s6/.s6-svscan/* \
              /go/src/code.gitea.io/gitea/gitea \
              /go/src/code.gitea.io/gitea/environment-to-ini
RUN chmod 644 /go/src/code.gitea.io/gitea/contrib/autocompletion/bash_autocomplete

# Final image
FROM docker.io/library/alpine:3.21
LABEL maintainer="maintainers@gitea.io"

EXPOSE 22 3000

RUN apk --no-cache add \
    bash \
    ca-certificates \
    curl \
    gettext \
    git \
    linux-pam \
    openssh \
    s6 \
    su-exec \
    gnupg \
    && rm -rf /var/cache/apk/*

RUN addgroup \
    -S -g 1000 git && \
    adduser -S -H -D -h /data/git -s /bin/bash -u 1000 -G git git && \
    echo "git:*" | chpasswd -e

ENV USER=git
ENV GITEA_CUSTOM=/data/gitea

# PostgreSQL base configuration — password will be passed at runtime
ENV GITEA__database__DB_TYPE=postgres
ENV GITEA__database__HOST=pg-1905d323-proton-f56e.l.aivencloud.com:11494
ENV GITEA__database__NAME=defaultdb
ENV GITEA__database__USER=avnadmin
ENV GITEA__database__SSL_MODE=require

VOLUME ["/data"]

ENTRYPOINT ["/usr/bin/entrypoint"]
CMD ["/usr/bin/s6-svscan", "/etc/s6"]

COPY --from=build-env /tmp/local /
COPY --from=build-env /go/src/code.gitea.io/gitea/gitea /app/gitea/gitea
COPY --from=build-env /go/src/code.gitea.io/gitea/environment-to-ini /usr/local/bin/environment-to-ini
COPY --from=build-env /go/src/code.gitea.io/gitea/contrib/autocompletion/bash_autocomplete /etc/profile.d/gitea_bash_autocomplete.sh
