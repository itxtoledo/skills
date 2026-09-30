---
name: apple-app-store-submission
description: 'End-to-end procedure for shipping an iOS app to TestFlight and the App Store — compliance config, signing credentials, archiving and uploading, App Store Connect metadata, privacy answers, age rating, screenshots, and beta review. Use this skill whenever the task involves publishing an iOS app to Apple: App Store submission, TestFlight, a store release, App Store Connect, "submit my app", "get it on the App Store", provisioning profiles, distribution certificates, export compliance, privacy manifests, Beta App Review, public TestFlight links, or uploading a build. Applies to Expo, React Native, Flutter, and native Xcode projects. Consult it before touching signing or store configuration, because the order of operations matters and several steps fail in confusing ways when done out of order.'
---

# Shipping an iOS app to the App Store

The store submission is not one step, it is five, and they constrain each other:

```
compliance config  →  signed build  →  upload  →  App Store Connect  →  TestFlight / review
```

Two things make this harder than it looks:

1. **Config feeds the build, and the build feeds the console.** Changing the
   app version, bundle id, or privacy declarations after uploading means
   rebuilding and re-uploading, and often re-doing console answers. Get the
   config right first.
2. **Signing is the step that blocks everything.** Automated tools (EAS and
   Xcode's automatic signing) both assume an Apple team with a registered
   physical device. A fresh team usually has none, and both fail with messages
   that point away from the real cause. `references/signing-and-upload.md`
   covers the route that always works.

Before starting, confirm the project builds and runs on a simulator. Submitting
an app that has never been executed is how you discover a crash during review.

## Step 0: collect the four identifiers

Ask for these up front; nothing proceeds without them.

| Identifier | Where to find it |
| --- | --- |
| **Bundle ID** | The app's own config, e.g. `com.company.appname` |
| **Apple ID** | The email of the Apple Developer account |
| **Team ID** | https://developer.apple.com/account/#/membership/ — the 10-character "Team ID" |
| **App ID (numeric)** | App Store Connect; it is the number in the app's URL, `/apps/<ID>/...` |

If the app record does not exist in App Store Connect yet, create it first
(My Apps → + → New App), because several later steps need the numeric ID.

For the App Store Connect API (used for signing and uploading), also get an
**Issuer ID** and a **team API key** from App Store Connect → Users and Access →
Integrations → App Store Connect API. The key needs **App Manager** or higher to
create distribution certificates and provisioning profiles. Store the `.p8` file
outside the repository.

## Step 1: compliance in the app config

Two declarations that cause avoidable rejection or upload friction. For Expo
projects they live in the app config; for bare Xcode projects, in `Info.plist`
and `PrivacyInfo.xcprivacy` directly.

**Export compliance.** Without it, every upload prompts for encryption
documentation. If the app only uses standard HTTPS:

```json
"ios": { "config": { "usesNonExemptEncryption": false } }
```

**Privacy manifest.** Required for "required reason" APIs — `UserDefaults`,
file timestamps, disk space, system boot time, active keyboards. Declare the
categories the app and its dependencies actually use, with valid reason codes.
Two things bite here:

- Declaring an extra category is harmless; a *missing* one is what Apple flags.
- Merging behaviour varies by toolchain. Some generators merge into the existing
  manifest, some replace it. Always verify the generated file after a clean
  build rather than assuming.

**Version string.** The build's `CFBundleShortVersionString` must exactly match a
version that already exists in App Store Connect, otherwise the upload creates a
*new* version and the metadata you filled in is orphaned. Check both sides before
building. Note that cross-platform projects often share one version field between
iOS and Android, so changing it has a second effect.

For the full checklist including the privacy-policy content Apple requires, see
`references/compliance.md`.

## Step 2: public URLs

Apple requires a privacy policy URL in the metadata **and** reachable from inside
the app, plus a support URL. Publish both before submitting; a dead or missing
policy is a common rejection.

The policy must state, explicitly: what data is collected, how it is collected,
every use of it, which third parties receive it and that they offer equivalent
protection, retention and deletion, and how a user withdraws consent and
requests deletion. Missing any one of those is a rejection under guideline 5.1.1.

### A hard rule about what goes in public text

Store copy, App Review notes, beta descriptions, and the privacy policy describe
**what the app does and what data is involved**. They do not describe **how the
app is built internally**.

This matters for two reasons. Implementation detail is not what App Review asks
for, so it adds no value; and publishing how a product works can hand away a
competitive advantage for no benefit. If the app reaches a service in a
non-obvious way, describe the outcome — "the app queries the service's public
API for X" — not the mechanism. Keep mechanism in internal docs and code
comments, where it helps future maintainers.

## Step 3: sign and build

Read `references/signing-and-upload.md`. The short version: create a
distribution certificate and an App Store provisioning profile through the App
Store Connect API, import them into a dedicated keychain, and archive with manual
signing. `scripts/asc-signing.mjs` generates the certificate and profile;
`scripts/export-options.plist` is the export template.

The two failures that waste the most time:

- Automated credential setup refuses to run non-interactively, so CI-style
  submission needs manual signing.
- Xcode's automatic signing tries to create a *development* profile first, which
  requires a registered device. On a team with no devices this fails with a
  message about missing devices rather than about signing.

## Step 4: App Store Connect

Read `references/asc-console.md` for the field-by-field walkthrough, including
the places where the UI silently discards your input. The high points:

- Fill version metadata, then **save the page**.
- Answer App Privacy, then **publish** it — answering without publishing leaves
  a draft that blocks submission.
- Complete the age rating questionnaire and save it from *inside* the wizard,
  then save the page.
- Upload screenshots at the sizes the console asks for, for every device family
  the app supports.
- Attach the processed build to the version.
- Write App Review notes that explain user-visible behaviour, especially
  anything a reviewer might read as broken (region restrictions, third-party
  outages, empty states).

## Step 5: TestFlight

Internal testers work immediately and skip Apple review. External testers —
including anyone joining through a public link — require the first build to pass
**Beta App Review**. The public link can be created before approval; it simply
refuses new testers until then, which is expected rather than a bug. Details in
`references/asc-console.md`.

## Step 6: before pressing submit

Submitting for review is effectively irreversible for that version. Confirm:

- The app was exercised on both an iPhone and an iPad simulator, since reviewers
  check both when the app declares tablet support.
- Every console section shows saved data, not a draft.
- The build is attached to the version being submitted.
- Review notes explain every non-obvious behaviour.
- Nothing in store copy, review notes, or the privacy policy describes internal
  implementation.
- Someone tested the build through TestFlight first.

## When something goes wrong

`references/troubleshooting.md` maps the exact error strings to causes and fixes.
Consult it before improvising, because several of these messages name the wrong
problem.

## A note on verification

Unit tests and type-checks will not catch the problems that matter most here —
display bugs, failed network fallbacks, and error text leaking into the UI.
Install the build on a simulator, walk the primary flow, and look at the screen.
Several of the most damaging issues in real submissions were visible in one
screenshot and invisible to every automated check.
