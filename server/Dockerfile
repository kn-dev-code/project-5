# Builds the Football Winner server. Run from the repository root, since the
# server uses packages/football_core:
#
#   docker build -f server/Dockerfile -t football-server .
#   docker run -p 8080:8080 -v football-data:/data football-server

FROM dart:stable AS build

# Fetch dependencies first so they're cached between code changes.
WORKDIR /app
COPY packages/football_core/pubspec.* packages/football_core/
COPY server/pubspec.* server/
WORKDIR /app/server
RUN dart pub get

WORKDIR /app
COPY packages/football_core packages/football_core
COPY server server
WORKDIR /app/server
RUN dart pub get --offline
RUN dart compile exe bin/server.dart -o bin/server

# A minimal image with just the compiled server and the runtime files it
# needs, including the CA certificates for calling ESPN over https.
FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/server/bin/server /app/bin/server

ENV DATA_DIR=/data
VOLUME /data
EXPOSE 8080
CMD ["/app/bin/server"]
