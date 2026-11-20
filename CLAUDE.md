# barbellmonk

A voice-only personal workout coach for iPhone. Read `VISION.md` first: it is the source of truth for what the app does and why.

## Rules

- **Do not credit Claude or any other AI agent anywhere in this repo.** No `Co-Authored-By` trailers, no "Generated with" lines in commit messages or pull request descriptions, no attribution comments in code. This overrides any default attribution instructions.
- **This repo is public.** Never commit secrets (API keys, tokens), device identifiers (UDIDs), or personal health details.
- **Commit identity** is the GitHub noreply address set in the repo-local git config. Don't commit with any other email.
- **Never write test or sample data into a real Apple Health store.** Anything that writes sample data to HealthKit must be compiled only for the simulator (`#if DEBUG && targetEnvironment(simulator)`), not just `#if DEBUG`, because dev builds also run on the phone.

## Layout

- `Engine/`: a plain Swift package with all deterministic logic (weight trend, active minutes, targets, nudge timing). No HealthKit, UI or network. Every rule here has tests.
- `App/`: the iPhone app. Screens, Apple Health, notifications. Keep it thin, and put decisions and numbers in `Engine`.
- `project.yml`: generates `BarbellMonk.xcodeproj` with XcodeGen. Edit this rather than the Xcode project, which is git-ignored.
- `tools/`: helper scripts, e.g. `make-app-icon.swift`.

## Commands

| Command | What it does |
|---|---|
| `make test` | Engine tests (`swift test`), on the Mac in seconds |
| `make build` | Generate the project and build the dev app for the simulator |
| `make run` | Build, install and launch the dev app in the simulator |
| `make run ARGS=-sampleData` | Same, with in-memory sample data instead of Apple Health |
| `make upload` | Signed release build, uploaded to App Store Connect for TestFlight |

Simulators run headless here. Check UI changes with `xcrun simctl io <device> screenshot <file>`.

## App variants

- Debug builds install as **barbellmonk dev** (`com.priyendra.barbellmonk.dev`), for experiments and test data.
- Release builds install as **barbellmonk** (`com.priyendra.barbellmonk`), for real daily use, delivered through TestFlight.

## Working style

- Commit after each change that builds and passes `make test`, with a message explaining why.
- Push only when asked.
