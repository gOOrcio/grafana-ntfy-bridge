ARG ELIXIR_VERSION=1.17.3
ARG OTP_VERSION=27.2
ARG ALPINE_VERSION=3.20.3

# ---- Build ----
FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-alpine-${ALPINE_VERSION} AS build

WORKDIR /app
ENV MIX_ENV=prod

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mix deps.compile

COPY lib lib
RUN mix release

# ---- Runtime ----
FROM alpine:${ALPINE_VERSION} AS runtime

RUN apk add --no-cache libstdc++ libgcc ncurses-libs && \
    addgroup -g 1000 bridge && \
    adduser -u 1000 -G bridge -s /bin/sh -D bridge

WORKDIR /app
COPY --from=build --chown=bridge:bridge /app/_build/prod/rel/bridge ./

USER bridge
EXPOSE 4000

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1:4000/health || exit 1

ENTRYPOINT ["./bin/bridge"]
CMD ["start"]
