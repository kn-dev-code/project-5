# Football Winner

Pick winners of live NFL and college football games, bet coins on them, and
spend winnings in the shop.

## How it fits together

| Folder | What it is |
| --- | --- |
| `lib/` | The Flutter app. |
| `packages/football_core/` | Pure Dart code shared by the app and server: models, betting rules, the accounts and betting servers, and the game feeds. |
| `server/` | The HTTP server. It runs the accounts and betting servers, saves their data to disk, and checks ESPN for scores every 30 seconds to pay out bets and send notifications. |

Live games and scores come from ESPN's public scoreboard
(`packages/football_core/lib/feeds/espn_game_feed.dart`). The API is
unofficial and unlicensed for commercial use, so ESPN could change or block it
without notice. Everything that depends on its format is in that one file.

## Running the server

```sh
cd server
dart pub get
dart run bin/server.dart
```

Settings come from environment variables:

| Variable | Default | Meaning |
| --- | --- | --- |
| `PORT` | `8080` | Port to listen on. |
| `DATA_DIR` | `data` | Where accounts and the betting ledger are saved. Use a persistent volume in production. |
| `GAME_FEED` | `espn` | `espn` for live games, or `fake` for made-up games that finish every 12 minutes, handy for testing. |
| `POLL_SECONDS` | `30` | How often to check scores. |
| `ALLOWED_ORIGIN` | `*` | Origin the web app is served from, for CORS. |

To deploy it as a container (for example on Cloud Run, Fly.io or a VPS), build
from the repository root:

```sh
docker build -f server/Dockerfile -t football-server .
docker run -p 8080:8080 -v football-data:/data football-server
```

Data is kept in JSON files, so run a single instance only.

For a step-by-step guide to running it on Google Cloud's free e2-micro machine
with https, see [deploy/README.md](deploy/README.md).

## Running the app

Point the app at a server when building or running it:

```sh
flutter run --dart-define=API_URL=http://localhost:8080
```

From the Android emulator, the development machine is `http://10.0.2.2:8080`.
Release builds should use an `https` address. For CI, set the `API_URL`
repository variable and the workflow passes it to the APK build.

Without `API_URL`, the app runs the servers itself, on the device, with
made-up games. The tests use this mode, and it works offline.

## Tests

```sh
flutter test                                # app
(cd packages/football_core && dart test)    # shared code and ESPN parsing
(cd server && dart test)                    # HTTP API end to end
```
