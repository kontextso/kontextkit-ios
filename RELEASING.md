# Releasing

- This document describes the process for cutting a new release of **KontextKit**.
- Follow these steps to ensure consistency across releases.
- Replace version `1.0.0` with the proper one instead.

> We use versioning without `v` at the front to align it for both SPM and CocoaPods so please keep that in mind.
> For example: `1.0.0`.

---

## 1. Create a release branch and test

1. Checkout branch `main`.
2. Pull the latest changes.
3. Create a new branch `release/1.0.0`.
4. Make sure it builds:
   ```bash
   xcodebuild build \
     -scheme KontextKit \
     -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest,arch=arm64' \
     -skipPackagePluginValidation
   ```
5. Run tests and make sure they are green:
   ```bash
   xcodebuild test \
     -scheme KontextKit \
     -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest,arch=arm64' \
     -skipPackagePluginValidation
   ```
6. Lint the podspec — this is the same check that `pod trunk push` runs:
   ```bash
   pod lib lint KontextKit.podspec --allow-warnings --use-libraries
   ```

## 2. Update the changelog

Edit `CHANGELOG.md` to include the new release notes at the top.

Standard release:
```markdown
## 1.0.0
* Add new provider.
* Fix some bug.
* Remove old API.
```

If the release contains breaking changes, add a `### Breaking` section before the bullet points:
```markdown
## 2.0.0
### Breaking
Short description of what changed and what integrators need to do.

* Add new feature.
* Fix some bug.
```

## 3. Update the CocoaPods spec

Update the version in `KontextKit.podspec`:

```ruby
s.version = "1.0.0"
```

## 4. Commit changes

Commit the changed files to the `release/1.0.0` branch:

```bash
git add CHANGELOG.md KontextKit.podspec
git commit -m "Prepare release 1.0.0"
```

## 5. Open pull request

1. Create a PR to `main` named: "Release version 1.0.0" and use the latest changelog entry as the PR description.
2. Merge the PR to `main`.

## 6. Create an annotated tag

```bash
git checkout main
git pull
git tag -a 1.0.0 -m "Release 1.0.0"
git push origin 1.0.0
```

## 7. Publish to CocoaPods trunk

```bash
pod trunk push KontextKit.podspec --allow-warnings --use-libraries
```

`--use-libraries` matches the local-lint flag in step 1.6 — without it, recent Xcode SDKs auto-link `SwiftUICore.tbd` (and `CoreAudioTypes` / `UIUtilities`) into the static-framework build and `pod trunk push` fails server-side validation with a linker error. Library-mode validation matches CocoaPods's runtime resolution for static-framework consumers, so dropping the flag isn't a release-quality risk — it's just a build-graph hint the validator needs.

First-time only: `pod trunk register support@kontext.so "Kontext"` and confirm via the link sent to that mailbox.

## 8. Verify

1. Check that the version is available on the [CocoaPods page](https://cocoapods.org/pods/KontextKit).
2. Bump the consuming SDKs (sdk-swift, sdk-react-native, sdk-flutter) to the new KontextKit version and confirm they build.

## Bundled OMID xcframework

KontextKit vendors `Frameworks/OMSDK_Kontextso.xcframework` directly in the repo. Updating it is a regular file replacement — drop the new xcframework in place, bump the IAB version referenced in `CHANGELOG.md`, and follow the normal release flow. The xcframework version (IAB OMID) is independent of KontextKit's semver — bumping the framework is a regular KontextKit minor/major bump per semver rules on the public API.
