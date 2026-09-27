# Flathub preparation audit

This is an audit and handoff checklist, not a submission manifest. A Flathub manifest is intentionally not included yet: the source URL, app ID, and licensing route need decisions before a truthful, buildable manifest can be written.

## Project facts inspected

- Echo is a Flutter/Dart Linux desktop application. The current Linux build script runs `flutter pub get` followed by `flutter build linux --release`.
- The repository URL recorded in the project context is `https://github.com/apptechsolutions352-del/Echo`; the GitHub repository is private. The local `.git` directory has no Git metadata, so its commit history cannot be inspected from this checkout.
- The only published release visible in the inspected release list was `v0.1.0` (2026-09-26). Flathub asks for meaningful project history, real-world use, and maintenance commitment; source-available apps should have sustained history and tagged releases. One known release is a review risk, not enough evidence to conclude acceptance or rejection.
- The Linux application ID, desktop file, and metainfo currently use `org.echo.Echo`. Flathub requires an ID in a namespace controlled by the developer. This ID implies the `echo.org` domain, whose ownership was not established. If the project is submitted under its GitHub repository, a possible repository-derived ID is `io.github.apptechsolutions352_del.Echo`; it is only a candidate, and the repository must be publicly reachable and the ID confirmed before use.
- The desktop entry is `packaging/org.echo.Echo.desktop`; the scalable SVG icon is `packaging/icons/org.echo.Echo.svg`; the AppStream file is `packaging/org.echo.Echo.metainfo.xml`.
- The metainfo currently declares `LicenseRef-proprietary`, but there is no project `LICENSE` or license/terms URL. I added the known homepage `https://echo-2ve.pages.dev/`; the metadata still lacks screenshot entries. Flathub requires an accurate project license; proprietary metadata needs a license link. Graphical submissions need at least one screenshot.

## Source-build work and risks

- Flathub disables network access during the build. Echo's existing command invokes `flutter pub get`, which normally fetches Dart packages, so a manifest must provide pinned public sources for Flutter and every locked dependency instead of relying on runtime network access.
- `media_kit` requires `libmpv` on Linux. Its `media_kit_libs_linux` package also downloads and builds mimalloc during CMake configuration. These dependencies must be supplied and built offline from declared sources; the current release bundle cannot be copied into a source-built Flathub submission.
- `metadata_god` builds Rust native code through Cargokit; its Rust crate and locked Cargo dependencies must be available offline and their license files installed.
- The file picker uses the XDG FileChooser portal. The app also scans and watches selected music folders, owns the MPRIS bus name `org.mpris.MediaPlayer2.echo`, and sends one first-launch POST to `https://echo-2ve.pages.dev/api/install`. A Flatpak will need narrowly justified filesystem/portal, session-bus, audio, and network permissions, then functional testing inside the sandbox.
- Existing build artifacts or release archives must not be placed in the Flathub pull request.

## Local validation status

- `appstreamcli validate --pedantic packaging/org.echo.Echo.metainfo.xml` fails: it reports `cid-contains-uppercase-letter` for `org.echo.Echo`; its homepage reachability check could not resolve `echo-2ve.pages.dev` from this environment. The final ID and upstream metainfo need correction and screenshots before revalidating from a network-enabled environment.
- `flatpak`, `flatpak-builder`, `flatpak-builder-lint`, and `desktop-file-validate` are not installed in this environment. A local Flatpak build, sandbox run, and Flathub linter run have therefore not been completed.

## Decisions needed before writing a final manifest

1. Choose whether Echo's source can be made publicly accessible. A source-built Flathub app requires a public, pinned source reference. Keeping the source repository private prevents Flathub from building it.
2. Confirm the actual project license and publish its terms at a stable URL. Do not replace `LicenseRef-proprietary` with an open-source identifier unless the author chooses that license.
3. Confirm the Flatpak ID and namespace ownership. For a GitHub-hosted public source repository, use the corresponding `io.github` ID and update the ID consistently in upstream CMake, desktop, MPRIS identity/metadata, and AppStream files.
4. Provide direct, public screenshot URLs and confirm the website URL for the AppStream metadata.

The binary-only `extra-data` approach is a separate option, not used here. Flathub permits `extra-data` for non-redistributable downloads, but the upstream-author policy says redistribution permission is generally implicit for upstream submissions. It should not be treated as a guaranteed way to keep a source-available project private. It would also require a stable public archive URL, exact size and SHA-256, and an install-time network download; Flathub would not be building Echo from source. Ask Flathub reviewers whether that route is appropriate before preparing it.

## Submission sequence after blockers are resolved

1. Publish a source repository and tagged, reproducible release, or obtain reviewer guidance on an allowed `extra-data` route.
2. Integrate the final ID, license URL, homepage, screenshots, desktop file, and scalable icon in the upstream project.
3. Create the top-level `<app-id>.yml` manifest, enumerate and checksum all source inputs, and build/test it with Flathub's builder and linter.
4. Fork `flathub/flathub`, check out its `new-pr` branch, add the required manifest files, and open a PR against `new-pr`. No PR has been opened or submitted.

Flathub publishes download statistics. These are downloads, not verified completed installations or unique devices.

## Current Flathub references

- Requirements: https://docs.flathub.org/docs/for-app-authors/requirements
- Submission process: https://docs.flathub.org/docs/for-app-authors/submission
- MetaInfo guidelines: https://docs.flathub.org/docs/for-app-authors/metainfo-guidelines
- Manifest and repository linter: https://docs.flathub.org/docs/for-app-authors/linter
- App statistics: https://docs.flathub.org/docs/for-app-authors/maintenance#download-statistics
- Latest Flathub Freedesktop runtime observed during this audit: `26.08`.
