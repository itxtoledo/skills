# Compliance configuration

Everything here is a declaration to Apple about what the app does. It feeds the
build, so it has to be right before the first upload.

## Export compliance

`ITSAppUsesNonExemptEncryption` in `Info.plist`. Set it to `false` when the app
only uses standard HTTPS/TLS and no custom cryptography. Without it, App Store
Connect stops each upload and asks for encryption documentation, which delays
TestFlight distribution.

Expo app config:

```json
{ "expo": { "ios": { "config": { "usesNonExemptEncryption": false } } } }
```

Bare Xcode: add the key directly to `Info.plist`.

If the app does implement its own cryptography, or bundles a library that does,
the answer is different and Apple may want documentation. Do not blanket-declare
`false` to skip a prompt.

## Privacy manifest (`PrivacyInfo.xcprivacy`)

Required for apps that call Apple's "required reason" APIs. The manifest declares
which API categories the app touches and why.

| Category | Common reason code | Use |
| --- | --- | --- |
| `NSPrivacyAccessedAPICategoryUserDefaults` | `CA92.1` | Reading/writing the app's own defaults |
| `NSPrivacyAccessedAPICategoryFileTimestamp` | `C617.1` | File metadata inside the app container |
| `NSPrivacyAccessedAPICategoryDiskSpace` | `85F4.1` | Checking free space before writing |
| `NSPrivacyAccessedAPICategorySystemBootTime` | `35F9.1` | Measuring intervals between user events |
| `NSPrivacyAccessedAPICategoryActiveKeyboards` | `3EC4.1` / `54BD.1` | Custom keyboard, or UI adapting to the active keyboard |

Reason codes are case-sensitive and include the period.

The manifest also carries `NSPrivacyTracking` (boolean), `NSPrivacyTrackingDomains`
(array), and `NSPrivacyCollectedDataTypes` (array). For an app with no analytics
and no ad SDK, `NSPrivacyTracking` is `false`, the domains array is empty, and
the collected data types array is empty.

Two practical traps:

- **Declaring more is safe, declaring less is not.** Apple flags missing
  declarations, not extra ones. If a dependency's own manifest is unclear,
  declare the category at app level too.
- **Verify the generated file after a clean build.** Some toolchains merge into an
  existing manifest, some replace it wholesale — replacing can silently drop
  categories that were there before. A replace looks like a regression in the
  final `.ipa`, not like an error during the build.

```bash
# after a clean build / prebuild
plutil -lint <AppName>/PrivacyInfo.xcprivacy
```

## Permission usage strings

Any system permission the app requests needs a purpose string in `Info.plist`
that names the specific feature using it. Generic text ("required for the app to
function") is a rejection. If the app requests no permissions, say so — and if
the OS shows a network or local-network prompt on its own, that is the system
talking, not a permission the app requested.

## Privacy policy content

Apple requires the policy to be linked in App Store Connect metadata **and**
reachable from inside the app. It must cover, explicitly:

- What data is collected
- **How** it is collected
- **Every** use of that data
- Which third parties receive data, and that they provide equivalent protection
- Retention and deletion
- **How a user revokes consent and requests deletion**

Missing any one of these is a rejection under 5.1.1. If the app has no accounts
and no back end, say so plainly — that is a strong privacy story and it also
simplifies the App Privacy questionnaire.

Publish the policy at a stable URL before submitting. If it lives on a site you
deploy, deploy it first and confirm it renders; a policy that 404s during review
counts as missing.

## App Privacy questionnaire

Answer it in App Store Connect, then **publish** it. The rule Apple uses:

> "Collect" means transmitting data off the device in a way that lets you or your
> third-party partners access it for longer than necessary to service the request
> in real time.

An app with no accounts, no back end, and no analytics or advertising SDK
answers **No, we do not collect data from this app**. That produces a
"Data Not Collected" label.

The questionnaire is about what *you or your partners* collect. A read-only
client that sends a user's query to a third-party API to fulfil that query is
not collecting under this definition — but if you bundle an analytics or
advertising SDK, their collection is yours to declare.

## Age rating

App Store Connect asks a seven-step questionnaire: in-app controls and
capabilities, then mature themes, medical, sexuality, violence, chance-based
activities, then a review step.

Answer for what the app **actually shows**. Declaring content more mature than
reality raises the rating and is tolerated; declaring less than reality risks a
rejection for inaccurate metadata.

Things worth thinking about honestly:

- **Unrestricted web access** — if the app can display arbitrary web content the
  user can navigate, that is a yes. Handing a link to the system browser is not
  the same thing as in-app browsing.
- **User-generated content** — this means content created by users *of your app*.
  Rendering someone else's content read-only is a different question.
- **Third-party content** — if the app surfaces content you do not control
  (a feed, listings, reviews, or media served by another service), think about
  whether the mature-theme answers should reflect that, instead of answering
  every category "None" by reflex.

## Screenshots

Upload for every device family the app declares. The console lists the exact
accepted pixel sizes for your app; use those, not remembered ones, because Apple
adjusts them over time.

Practical notes:

- Capture on a simulator at native resolution, then resize if the required size
  differs. Small aspect-ratio differences from a resize are imperceptible.
- Do not ship screenshots of an empty state. Drive the app through a real flow so
  the screenshots show actual content.
- The first three are what people see in the install sheet; put the strongest
  ones first.

## Metadata rules worth knowing

- Third-party brand names belong in the **keywords** field, never in the app name
  or subtitle. Using another company's brand in the name risks a rejection under
  4.1(c).
- The description is for users. The review notes are for the reviewer. Do not
  paste internal explanation into the description.
