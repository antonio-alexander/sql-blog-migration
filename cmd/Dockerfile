#---------------------------------------------------------------------------------------------------
# sql-blog-migration [Dockerfile]
# 
# Reference: https://stackoverflow.com/questions/63178036/how-to-find-commit-hash-from-within-a-running-docker-image
# commit: git rev-parse HEAD
# 
# https://stackoverflow.com/questions/6245570/how-to-get-the-current-branch-name-in-git
# branch: git rev-parse --abbrev-ref HEAD
# 
# Sample docker build commands:
#  docker build -f ./cmd/Dockerfile . -t ghcr.io/antonio-alexander/sql-blog-migration:amd64_latest
#
#---------------------------------------------------------------------------------------------------

ARG GO_ARCH=amd64
ARG GO_ARM=7
ARG PLATFORM=linux/amd64
ARG GOOSE_VERSION=v3.10.0
ARG MYSQL_DATABASE=sql_blog_migration
ARG MYSQL_ROOT_PASSWORD=sql_blog_migration
ARG MYSQL_USER=sql_blog_migration
ARG MYSQL_PASSWORD=sql_blog_migration
ARG EMPLOYEES_SQL=004_employees.sql

FROM --platform=${PLATFORM} golang:alpine AS builder

ARG GO_ARCH
ARG GO_ARM
ARG GOOSE_VERSION

ENV GOPROXY=https://proxy.golang.org,direct

RUN env GOARCH=${GO_ARCH} GOARM=${GO_ARM} GOOS=linux go install github.com/pressly/goose/v3/cmd/goose@${GOOSE_VERSION} \
    && mv /go/bin/linux_arm/goose /go/bin/goose 2>/dev/null || : \
    && which goose

FROM --platform=${PLATFORM} yobasystems/alpine-mariadb:10

ARG MYSQL_ROOT_PASSWORD
ARG MYSQL_USER
ARG MYSQL_PASSWORD
ARG MYSQL_DATABASE
ARG EMPLOYEES_SQL

ENV MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
ENV MYSQL_DATABASE=${MYSQL_DATABASE}
ENV MYSQL_USER=${MYSQL_USER}
ENV MYSQL_PASSWORD=${MYSQL_PASSWORD}
ENV AUTOMATIC_MIGRATION=false
ENV EMPLOYEES_SQL=${EMPLOYEES_SQL}

COPY --from=builder /go/bin/goose /bin/goose

WORKDIR /sql_blog_migration

COPY ./cmd/run.sh /scripts/run.sh 
COPY ./cmd/sql /sql_blog_migration

RUN chmod +x /scripts/run.sh \
    && sed -i 's/\r$//' /scripts/run.sh \
    && sed -i 's/\r$//' /sql_blog_migration/001_employees.sql \
    && sed -i 's/\r$//' /sql_blog_migration/002_employees.sql \
    && sed -i 's/\r$//' /sql_blog_migration/003_employees.sql \
    && sed -i 's/\r$//' /sql_blog_migration/004_employees.sql \
    && sed -i 's/\r$//' /sql_blog_migration/migration/20230407165454_add_middle_name_column.sql \
    && sed -i 's/\r$//' /sql_blog_migration/migration/20230407185110_add_new_index.sql \
    && sed -i 's/\r$//' /sql_blog_migration/migration/20250611170303_first_middle_last_name_constraints.sql

HEALTHCHECK --start-period=10s --interval=5s --timeout=5s --retries=5 CMD mysqladmin ping -h localhost -u root -p$MYSQL_ROOT_PASSWORD || exit 1

ENTRYPOINT ["/scripts/run.sh"]
