# Releasing (Flutter / pub.dev)

The package is published to [pub.dev](https://pub.dev) as `cookie_munch`.

## One-time: allow publishing

The committed `pubspec.yaml` has `publish_to: none` (it ships that way so the SDK can
be vendored without accidental uploads). **Before the first real publish, remove that
line** so `dart pub publish` targets pub.dev.

## Publish (manual)

```bash
flutter pub get
flutter analyze
flutter test
dart pub publish --dry-run   # verify package contents + score
dart pub publish             # requires pub.dev auth (see below)
```

## pub.dev auth

- **Interactive:** `dart pub login` opens a browser and stores an OAuth token in
  `~/.config/dart/pub-credentials.json`.
- **CI (automated):** use pub.dev's GitHub Actions **automated publishing** — configure
  the package's "Automated publishing" on pub.dev to trust this repo + a tag pattern,
  then a tag-triggered workflow using `dart-lang/setup-dart`'s OIDC exchange publishes
  with no long-lived token. Skeleton:

```yaml
# .github/workflows/publish.yml
name: Publish to pub.dev
on:
  push:
    tags: ["v[0-9]+.[0-9]+.[0-9]+"]
permissions:
  id-token: write   # required for pub.dev OIDC
jobs:
  publish:
    uses: dart-lang/setup-dart/.github/workflows/publish.yml@v1
```

## Token/setup needed

Configure **automated publishing** for `cookie_munch` on pub.dev (repo + tag pattern),
or hold a pub.dev account authorized to publish the package for manual releases.
