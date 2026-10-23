# Releasing Velora

## Branches and source

`main` holds release-ready work. `test` is used to validate changes before they are promoted. The repository is independently maintained, with its origin as an Illogical Impulse fork documented in the README and NOTICE.

Keep release commits focused and preserve human author metadata and third-party credits. Version numbers come from `VERSION`; record user-visible changes in `CHANGELOG.md` and release notes in `RELEASE_NOTES.md`.

## Validation before publication

```bash
python3 -m unittest discover -s tests -v
bash -n velora install.sh setup diagnose scripts/install.sh \
  dots/.config/quickshell/ii/scripts/maintenance/velora.sh
./velora install --dry-run
./velora install --dry-run --build-package --build-from-source
./velora package --output ./artifacts/release
```

Inspect the resulting package with `pacman -Qip` and `pacman -Qlp`. Verify that shell source, shaders, shape submodule files, dependency manifests, the launcher, license notices, and the package source metadata are included. Runtime `config.json`, install markers, developer metadata, and temporary build files must be absent.

Use an Arch test account to verify fresh installation, component selection, package installation, source builds, repeat installation, microphone/audio controls, monitor configuration, lock screen, wallpapers, updates, and configuration recovery. Record test results rather than treating a generated package as proof of a complete desktop installation.

Use `velora update --check --channel release` after publishing a stable release to verify detection. Before the first release exists, this command should explain that there is no published release.

## Artifacts and publication

Package builds use a reviewed source archive with its checksum in the generated PKGBUILD. The package version includes `VERSION`, a Git revision count, and the source commit. Commit release changes before producing the final distributable so its embedded revision identifies the committed source.

```bash
sha256sum artifacts/release/velora-*.pkg.tar.zst > artifacts/release/SHA256SUMS
```

When publication is authorized, create an annotated `vVERSION` tag on the tested commit and push the intended branches and tag. The release workflow builds a package in an Arch container and prepares a **draft** GitHub release. Review its artifacts, notes, validation results, and version before publishing it.

A local commit, package build, or draft release does not publish a stable version. Do not push branches, push tags, or publish a release until those actions are authorized.

## Recoverability

Before deleting remote branches or rewriting local fork-specific commit messages, retain a Git bundle and a record of branch tips under `artifacts/release/`. These local backups are ignored by Git and must not be included in source packages or release uploads. Keep them until the release and history changes have been verified.
