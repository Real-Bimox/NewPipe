# NewPipe agent guidelines

Standing instructions for AI agents working in this local NewPipe checkout.

This file is for this repository only. Follow the upstream NewPipe contribution
rules in [.github/CONTRIBUTING.md](.github/CONTRIBUTING.md) and the project
overview in [README.md](README.md). If these instructions conflict with a direct
owner instruction, ask before proceeding unless the owner instruction clearly
resolves the conflict.

## Project orientation

- NewPipe is a GPL-3.0-or-later libre streaming front-end.
- This checkout tracks the `dev` branch of `https://github.com/Real-Bimox/NewPipe.git`.
- The upstream README says the current codebase is in maintenance mode and that
  new-feature work belongs on `refactor`; bugfix and maintenance work belongs on
  the current maintenance branches.
- Main modules:
  - `app`: Android app, legacy Java/Kotlin UI and platform code.
  - `shared`: Kotlin Multiplatform and Compose shared code.
  - `desktopApp`: Compose desktop app entry point.
  - `iosApp`: iOS app project.
  - `buildSrc`: custom Gradle build logic.
- NewPipe uses NewPipeExtractor for service parsing. If a change depends on
  extractor behavior, verify it against the app and prefer the documented
  `settings.gradle.kts` local `includeBuild("../NewPipeExtractor")` path.

## Owner and agent rules

- Keep changes small, focused, and directly tied to the requested issue.
- Do not add AI/model/tool attribution to commits, branch names, PR text, or file
  content. Commit messages should contain only the substantive message.
- Respect NewPipe's AI policy in `.github/CONTRIBUTING.md`: do not use AI for
  large generated features, do not use AI to fill issue/PR templates, and fully
  understand and review any AI-assisted code before it is kept.
- Do not rewrite history, force-push, delete branches, delete existing files, or
  perform other destructive operations without explicit owner approval.
- Do not introduce secrets, credentials, proprietary services, binary blobs, or
  closed-source Google dependencies. NewPipe must remain compatible with F-Droid
  expectations and devices without Google Play Services.
- If a task raises legal, license, security, release-signing, or privacy
  questions, stop and ask the owner.

## Development conventions

- Use the repo's Gradle wrapper: `./gradlew`.
- Java and Kotlin style is enforced by Checkstyle and ktlint. Keep formatting
  consistent with `.editorconfig`, `checkstyle/`, and existing code.
- Kotlin uses JDK toolchain 21. Local builds need JDK 21 and Android SDK licenses
  accepted.
- Prefer existing architecture and package patterns over new abstractions.
- Keep Android XML resources, translations, and string names consistent with the
  existing `app/src/main/res` layout. Translation work should normally happen in
  Weblate; avoid broad manual translation churn.
- Keep dependency changes minimal and justified. Version catalog edits belong in
  `gradle/libs.versions.toml`; preserve dependency ordering because
  `checkDependenciesOrder` validates it.
- For database/schema changes, update the relevant Room schema files and add or
  update migration tests.
- For UI work, validate behavior on realistic Android configurations. Preserve
  privacy-oriented defaults and account-free flows.

## Branching and sync

- Start by checking status and branch state with `git status --short --branch`.
- Pull before beginning work when the owner asks for synced work or when local
  state may be stale.
- Do not work directly on `dev` for larger changes intended as PRs; create a
  focused branch with a descriptive name. Very small local-only maintenance edits
  may stay on the current branch if the owner asked for that.
- Never discard untracked or modified files unless the owner explicitly asks.
  Treat local changes as owner work until proven otherwise.

## Verification commands

Use the narrowest check that covers the change, then broaden when risk warrants.

- Standard CI-equivalent JVM build and tests:
  `./gradlew assembleDebug lintDebug testDebugUnitTest --stacktrace -DskipFormatKtlint`
- Android instrumentation tests, when emulator/device coverage is needed:
  `./gradlew connectedCheck --stacktrace`
- Style checks used by debug builds:
  `./gradlew :app:runCheckstyle :app:runKtlint :app:checkDependenciesOrder`
- Unit tests only:
  `./gradlew testDebugUnitTest --stacktrace`
- Build debug APK:
  `./gradlew assembleDebug --stacktrace`

If a command cannot be run locally because dependencies, Android SDK, network, or
emulator access are unavailable, report that clearly and state what was verified
instead.

## Completion expectations

- Explain the files changed and the verification performed.
- Mention any tests that were skipped and why.
- Leave the working tree clean only when the owner asked for commits or cleanup.
  Otherwise leave local edits visible for review.
