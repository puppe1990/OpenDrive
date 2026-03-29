# syntax=docker/dockerfile:1

ARG ELIXIR_VERSION=1.18.4
ARG OTP_VERSION=27
ARG DEBIAN_VERSION=bookworm

FROM elixir:${ELIXIR_VERSION}-otp-${OTP_VERSION}-slim AS builder

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends build-essential git curl ca-certificates sqlite3 libsqlite3-dev && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get --only ${MIX_ENV}
RUN mix deps.compile

COPY lib lib
COPY priv priv
COPY assets assets
RUN mix compile
RUN mix assets.deploy
RUN mix release

FROM debian:${DEBIAN_VERSION}-slim AS runner

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 sqlite3 ca-certificates curl && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV MIX_ENV=prod \
    PHX_SERVER=true \
    PORT=4000 \
    DATABASE_PATH=/data/open_drive.db

RUN mkdir -p /data

COPY --from=builder /app/_build/prod/rel/open_drive ./

EXPOSE 4000

CMD ["/app/bin/open_drive", "start"]
