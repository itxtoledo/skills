# Signing, archiving, and uploading

This is the step that blocks everything else, and the one where automated tools
fail most confusingly.

## Why not to rely on automated credential setup

**EAS / cloud builders.** `eas build -p ios --non-interactive` stops with:

```
Failed to set up credentials.
Credentials are not set up. Run this command again in interactive mode.
```

It does not create a distribution certificate in non-interactive mode, even when
given an App Store Connect API key through `EXPO_ASC_API_KEY_PATH`,
`EXPO_ASC_API_KEY_KEY_ID`, and `EXPO_ASC_API_KEY_ISSUER_ID`. For unattended
submission, sign locally instead.

**Xcode automatic signing.** `xcodebuild archive` with automatic signing fails in
sequence:

```
error: Signing for "<App>" requires a development team.
error: Your team has no devices from which to generate a provisioning profile.
error: No profiles for '<bundle-id>' were found
```

The cause is that automatic signing requests a **development** profile first, and
development profiles require a registered device. A team that has only ever
built for simulators has no devices. Forcing the distribution identity on top of
automatic signing then produces a conflict:

```
error: has conflicting provisioning settings ... automatically signed for
development, but a conflicting code signing identity ... has been manually
specified
```

The fix is not to fight automatic signing — it is to create the distribution
credential yourself and switch to manual signing.

## The route that works

### 1. Create the certificate and profile through the API

Run `scripts/asc-signing.mjs` (see its header for the environment variables). It:

- resolves the `bundleIds` resource for your bundle id
- reuses a valid `IOS_DISTRIBUTION` certificate if one exists, otherwise creates
  one from a freshly generated CSR
- creates or reuses an `IOS_APP_STORE` provisioning profile bound to that bundle
  id and certificate
- writes `dist.cer` and `profile.mobileprovision` to a working directory

An `IOS_APP_STORE` profile needs no registered devices, which is exactly why it
works here.

The API key needs **App Manager** or higher. A key with a lower role can read
data but cannot create certificates.

### 2. Build a p12 and import it into a dedicated keychain

Use a throwaway keychain rather than the login keychain: it avoids interactive
keychain prompts and touches nothing of the user's.

```bash
openssl x509 -inform DER -in dist.cer -out dist.pem

# -legacy is required. A p12 written by OpenSSL 3 with default settings is
# rejected by macOS `security import` with
#   "MAC verification failed during PKCS12 import (wrong password?)"
# even when the password is correct.
openssl pkcs12 -export -legacy -inkey dist.key -in dist.pem \
  -out dist.p12 -passout pass:<p12-pass> -name "Apple Distribution"

KC=/tmp/build.keychain-db
security create-keychain -p <kc-pass> "$KC"
security set-keychain-settings -lut 3600 "$KC"
security unlock-keychain -p <kc-pass> "$KC"
security import dist.p12 -k "$KC" -P <p12-pass> \
  -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple: -k <kc-pass> "$KC" >/dev/null

# Xcode looks up signing identities through the *keychain search list*.
# Passing --keychain to codesign is not enough: without this step the archive
# fails with "No signing certificate found".
security list-keychains -d user -s \
  $(security list-keychains -d user | tr -d '"' | tr '\n' ' ') "$KC"
```

Verify the identity is visible before archiving:

```bash
security find-identity -v -p codesigning "$KC"
```

### 3. Install the provisioning profile

```bash
mkdir -p ~/Library/MobileDevice/Provisioning\ Profiles
cp profile.mobileprovision \
  ~/Library/MobileDevice/Provisioning\ Profiles/<profile-uuid>.mobileprovision
```

The profile UUID is printed by the signing script and is also inside the file
(`security cms -D -i profile.mobileprovision`).

### 4. Archive

```bash
xcodebuild \
  -workspace <App>.xcworkspace \
  -scheme <App> \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -archivePath /tmp/<App>.xcarchive \
  DEVELOPMENT_TEAM=<TEAM_ID> \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="iPhone Distribution" \
  PROVISIONING_PROFILE_SPECIFIER="<profile name>" \
  archive
```

`DEVELOPMENT_TEAM` is required even with manual signing; without it the project
has no team at all and the archive stops immediately.

Success is `** ARCHIVE SUCCEEDED **`.

### 5. Export and upload

Export options plist:

```xml
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
  <key>teamID</key><string><TEAM_ID></string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>iPhone Distribution</string>
  <key>provisioningProfiles</key>
  <dict>
    <key><bundle-id></key><string><profile name></string>
  </dict>
</dict>
```

```bash
xcodebuild -exportArchive \
  -archivePath /tmp/<App>.xcarchive \
  -exportOptionsPlist export-options.plist \
  -allowProvisioningUpdates \
  -authenticationKeyPath ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8 \
  -authenticationKeyID <KEY_ID> \
  -authenticationKeyIssuerID <ISSUER_ID>
```

Success is `** EXPORT SUCCEEDED **` followed by `Upload succeeded`.

Harmless warnings you can ignore: `Upload Symbols Failed` for framework dSYMs
(React, Hermes, and similar prebuilt frameworks ship without them). They do not
block the upload or review.

### 6. Clean up

```bash
security list-keychains -d user -s ~/Library/Keychains/login.keychain-db
security delete-keychain /tmp/build.keychain-db
```

Restore the search list before deleting the keychain, or the login keychain can
end up dropped from the list.

## After the upload

The build appears in TestFlight as **Processing** for roughly 10–60 minutes, then
becomes **Complete**. Only then can it be attached to a version or distributed.

If the build never appears, the most common cause is a version-string mismatch
with App Store Connect: the upload succeeds but creates a separate version, so it
looks like it vanished. Check the version list, not just the build list.

## Cross-platform projects

If the app config has a single version field shared by iOS and Android, changing
it to match an App Store version also changes the Android version name on the
next release. Android's `versionCode` is what governs updates, so this is
cosmetic, but mention it so it is not a surprise.
