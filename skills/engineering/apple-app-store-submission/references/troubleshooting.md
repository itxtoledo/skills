# Troubleshooting

Several of these messages name the wrong problem. Match on the quoted string.

## Signing and credentials

| Message | Real cause | Fix |
| --- | --- | --- |
| `Credentials are not set up. Run this command again in interactive mode.` | Automated credential setup cannot create a distribution certificate non-interactively | Sign locally: create the certificate and profile via the API, archive with manual signing |
| `Signing for "<App>" requires a development team.` | `DEVELOPMENT_TEAM` is not set in the generated project | Pass `DEVELOPMENT_TEAM=<TEAM_ID>` to `xcodebuild` |
| `Your team has no devices from which to generate a provisioning profile.` | Automatic signing asked for a **development** profile, which needs a registered device | Use an `IOS_APP_STORE` profile with `CODE_SIGN_STYLE=Manual` |
| `has conflicting provisioning settings ... automatically signed for development` | Automatic signing combined with a manually forced distribution identity | Pick one: manual signing throughout |
| `No signing certificate "iOS Distribution" found` | The certificate exists but in a keychain Xcode does not consult | Add the keychain to the search list: `security list-keychains -d user -s ...` |
| `MAC verification failed during PKCS12 import (wrong password?)` | A p12 written by OpenSSL 3 with default algorithms; macOS cannot read it | Re-export with `openssl pkcs12 -export -legacy ...` |
| `No profiles for '<bundle-id>' were found` | No App Store profile installed for that bundle id | Install the generated profile into `~/Library/MobileDevice/Provisioning Profiles/` |
| API returns 403 when creating a certificate | The API key's role is too low | Use a key with **App Manager** or higher |

## Build and upload

| Message | Real cause | Fix |
| --- | --- | --- |
| `** ARCHIVE FAILED **` with no obvious error above it | Usually signing; grep the log for `error:` rather than reading the tail | `grep -n "error:" build.log` |
| Upload succeeds but the build is not on the version | The build's version string does not match any version in App Store Connect, so a new version was created | Align the version string on both sides, rebuild, re-upload |
| `Upload Symbols Failed` for framework dSYMs | Prebuilt frameworks ship without debug symbols | Harmless; ignore |
| Build stuck on **Processing** | Normal | Wait 10–60 minutes |

## App Store Connect

| Symptom | Cause | Fix |
| --- | --- | --- |
| "Set Up Age Ratings" keeps reappearing | The page-level Save was clicked instead of the wizard's Save | Click the wizard's Save, then save the page |
| App Privacy looks filled but submission is blocked | Answers were saved but never published | Edit → answer → Save → **Publish** → confirm |
| Cannot attach a build | Build still processing, or the version string does not match | Wait for **Complete**; verify the version |
| Public TestFlight link refuses testers | Beta App Review has not approved the first external build | Wait; the link activates on its own |
| "Sign-in required" cannot be unchecked | It is a checkbox styled like a radio; clicking the wrong element toggles a different field | Target the checkbox whose `id` is the demo-account field |
| Metadata entered via automation is empty after reload | The framework never registered the change | For `contenteditable` fields, dispatch an `input` event after inserting text |

## App Review rejections worth pre-empting

| Guideline | Typical trigger | Prevention |
| --- | --- | --- |
| 5.1.1 | Privacy policy missing, or missing one of the required disclosures | Publish a policy covering collection, use, third parties, retention, and consent withdrawal; link it in metadata and in the app |
| 2.1 | Reviewer hits an error state and reads the app as incomplete | Explain region restrictions and third-party outages in the review notes; make error states offer a retry |
| 2.3.1(a) | Undocumented behaviour the reviewer notices | Describe user-visible behaviour and data flow in the notes — without describing internals |
| 4.1(c) | A third-party brand in the app name or subtitle | Keep other companies' marks in the keywords field only |
| 4.2 | App reads as a thin wrapper with no native value | Make sure the native functionality is obvious from the first screen |
| 2.4.1 | App declares tablet support but is unusable on iPad | Test on an iPad simulator; reviewers do |

## Debugging a Safari-based browser automation bridge

If store filling is driven through a browser automation bridge and the extension
never connects, check for orphaned server processes holding the bridge port. The
symptom is a listener reporting `failed` or a bridge reporting `disconnected`
even with the browser open. Processes left behind by earlier sessions occupy the
port range, the new server binds a different port, and the extension — which
looks on a fixed port — never finds it. Terminate the orphans and let the server
bind the expected port.
