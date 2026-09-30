# App Store Connect walkthrough

The console is a client-rendered app where several actions look saved and are
not. This file records the traps.

## Navigation that saves time

The URL structure is stable and predictable, which is faster than clicking:

| Page | Path |
| --- | --- |
| App list | `/apps` |
| Version metadata | `/apps/<APP_ID>/distribution/ios/version/inflight` |
| App information (age rating, category) | `/apps/<APP_ID>/distribution/info` |
| App Privacy | `/apps/<APP_ID>/distribution/privacy` |
| TestFlight builds | `/apps/<APP_ID>/testflight/ios` |
| Test information | `/apps/<APP_ID>/testflight/test-info` |
| Users and access | `/access/users` |
| API keys | `/access/integrations/api` |

## Version metadata

Fields, with the limits that matter:

| Field | Limit | Notes |
| --- | --- | --- |
| Promotional Text | 170 | Editable without a new review |
| Description | 4000 | For users, not for the reviewer |
| Keywords | 100 | Comma-separated, no space after commas |
| Support URL | — | Required |
| Marketing URL | — | Optional |
| Copyright | 200 | e.g. `2026 Company Name LTDA` |

**Save the page** when done. The form is one save for all fields.

Automation note: the inputs carry stable `id` attributes (`#description`,
`#keywords`, `#supportUrl`, `#notes`, …). Two caveats if you drive this with a
browser tool:

- Ids containing brackets (some localization fields) break CSS selectors — use
  `[id="..."]` attribute selectors instead.
- Rich-text fields are `contenteditable` divs, not inputs. Setting them requires
  an insert-text command plus a dispatched `input` event, or the framework will
  not register the change.

## App Privacy

Three actions, and all three are needed:

1. **Edit** → enter the Privacy Policy URL → **Save**
2. **Get Started** → answer the data collection question → **Save**
3. **Publish** → confirm in the dialog

Skipping step 3 leaves a draft. The page then looks answered, and submission is
blocked with no obvious pointer to why.

## Age rating

A seven-step wizard. The trap: at the end there are **two** buttons labelled
"Save" — the page-level one at the top and the wizard's own. Clicking only the
page-level button discards the wizard entirely, and the page goes back to showing
"Set Up Age Ratings" as if nothing happened.

Click the wizard's button, and if the page still shows the setup prompt, save the
page too. The resulting rating appears as a number per region.

## Screenshots

The iPhone and iPad tabs are separate and each has its own required size. Upload
for every device family the app declares — an app with tablet support needs iPad
screenshots even if it is mostly used on a phone.

Screenshots save on upload; there is no separate save step.

## App Review Information

Contact details plus **Notes**. The notes are where a reviewer learns what is
normal for this app, which prevents the most common avoidable rejection
(guideline 2.1, "app incomplete"):

- Any region restriction or third-party service that can be slow or unavailable,
  and what the user sees when it is. Say explicitly that a retry is expected.
- Anything that looks like a bug but is not — an empty state, a login-less app,
  a feature that depends on an external API.
- If the app has no account system, say so, so the reviewer does not hunt for a
  demo login.

Write notes about **behaviour and data**. Do not explain internal mechanisms —
that is not what the reviewer is asking about.

## Attaching the build

The version page has a **Build** section with **Add Build**. Select the processed
build, confirm, then **Save** the page. A build that exists in TestFlight but is
not attached to the version cannot be submitted.

## TestFlight

### Internal testing

Works immediately, no Apple review. Create a group (enable automatic
distribution so future builds join it), then add testers from the group's
**Testers** tab. Internal testers must be App Store Connect users, which makes
this unsuitable for sharing with people outside the team.

### External testing and public links

The link for sharing with anyone outside the team.

1. Fill **Test Information** first: beta description, feedback email, marketing
   and privacy URLs, contact details, and the sign-in question. If the app has no
   login, leave "Sign-in required" unchecked — otherwise you will be asked for
   demo credentials you cannot provide.
2. Create an **external** testing group.
3. Add the build to it. The wizard asks for sign-in information (leave unchecked)
   and **What to Test**, which is required — the submit button stays disabled
   until it is filled.
4. **Submit for Review** → the build goes to *Waiting for Review* (Beta App
   Review).
5. On the group page, **Create Public Link** → choose **Open to Anyone** →
   **Confirm**. This produces `https://testflight.apple.com/join/<TOKEN>`.

The link exists immediately but refuses testers until the build is approved.
Anyone opening it early sees:

> This beta isn't accepting any new testers right now.

That is expected, not a misconfiguration. Once Beta App Review approves the
build, the same link starts working with no further action. Approval typically
takes hours and can take a day or two.

Only the **first** build for external testing goes through this. Subsequent
builds of the same version usually distribute without a new review.

## Submitting for review

**Add for Review** is effectively irreversible for that version. Before pressing
it, confirm the checklist in the main SKILL.md. If the user has not explicitly
asked to submit for review, prepare everything and stop — say clearly that it is
one click away rather than clicking it.
