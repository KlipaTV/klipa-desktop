# Microsoft Store listing

Everything Partner Center asks for when Klipa Player is submitted to the
Microsoft Store, ready to paste. Nothing here is uploaded automatically, and
no tool signs in to Partner Center. Check the text after any edit with:

```bash
dart tool/check_store_listing.dart
```

It enforces the field limits below, the "free IPTV" ban in every language, no
em or en dash, and links only to Klipa's own sites and the GNU licenses.

## Files

| File | Partner Center field | Limit |
| --- | --- | --- |
| `listing/<locale>/description.txt` | Store listings > Description | 10,000 characters |
| `listing/<locale>/short_description.txt` | Store listings > Short description | 1,000 |
| `listing/<locale>/features.txt` | Store listings > Product features, one per line | 20 features, 200 each |
| `listing/<locale>/search_terms.txt` | Store listings > Search terms, one per line | 7 terms, 30 each, 21 words in all |
| `listing/<locale>/release_notes.txt` | Store listings > What's new in this version | 1,500 |
| `copyright.txt` | Store listings > Copyright and trademark info (every language) | 200 |
| `additional_license_terms.txt` | Store listings > Additional license terms (every language) | 10,000 |
| `certification_notes.txt` | Submission options > Notes for certification | 2,000 |

The text follows the app as it is: live channels only (the Xtream login is
live-only), now and next from the provider's guide, an English interface. It
names no provider and claims no content, and it repeats the zero-network start
recorded in `docs/product.md` and `docs/security-model.md`. A change to what the
app does with data changes this text, the privacy page and the klipa.tv copy
together.

Listing languages, and the Partner Center language to pick for each folder:

| Folder | Language | Folder | Language |
| --- | --- | --- | --- |
| `en` | English (United States) | `eu` | Basque |
| `es` | Spanish (Spain) | `pl` | Polish |
| `pt` | Portuguese (Portugal) | `tr` | Turkish |
| `fr` | French (France) | `ar` | Arabic (Saudi Arabia) |
| `de` | German (Germany) | `zh` | Chinese (Simplified, China) |
| `it` | Italian (Italy) | | |

The package declares only `en-us`, because the interface is English. Partner
Center then offers an English listing; the other ten are added with
**Store listings > Manage additional languages**, and each description says
the interface is in English.

Fields that are the same in every language: **Product name** is the reserved
name (`displayName` in `../msix/store-identity.json`), **Developed by** is
`Klipa Project`.

**Screenshots:** every `store-msix` run saves `store-01-library.png` and
`store-02-full-screen.png` (1920 x 1080) in the artifact's `smoke/` folder:
the installed package on the runner, with Big Buck Bunny from
`certification-test.m3u` paused after it has played (`step-playing.png` is
the same screen while it plays). Partner Center needs at least one 1366 x 768
or larger PNG and uses the English ones for every language. Give each the
caption "Big Buck Bunny (c) Blender Foundation, CC BY 3.0, from a public
test stream". `certification-test.m3u` holds only open test streams and is
also the playlist the certification notes give the tester.

## Properties

- **Category:** Photo & video (Google Play files the Android app under video
  players). Entertainment is the alternative.
- **Privacy policy URL:** `https://klipa.tv/privacy/#desktop`. The desktop
  section of that page ships on the klipa-web branch prepared for this
  release and must be live before the submission is sent.
- **Website:** `https://klipa.tv/desktop/`
- **Support contact info:** `hello@klipa.tv`
- **Product declarations:** leave "This app has been tested to meet
  accessibility guidelines" unchecked (not measured). Uncheck "Windows can
  include this app's data in automatic backups to OneDrive": the library key
  is sealed to the Windows account with DPAPI, so a library restored on
  another PC cannot be opened and the app would reset it.
- **System requirements:** Windows 10 version 1809 or later, x64 (the
  manifest's `MinVersion` is 10.0.17763.0).

## Age ratings (IARC questionnaire)

Category: **Utility, Productivity, Communication, or Other** (a media player
for the user's own sources, like other players in the Store).

| Question | Answer | Why |
| --- | --- | --- |
| Violence, fear, sexuality, nudity, language, drugs, gambling in the product | No to each | The app's own interface has none of it and ships no content |
| Users can interact or exchange content with other users | No | No chat, sharing or accounts |
| Shares the user's location with other users | No | No location access |
| Allows purchases of digital goods | No | No purchases on desktop (D-0009, D-0025 is only a proposal) |
| Unrestricted internet access, such as a web browser | No | It plays only the addresses the user enters; it does not browse the web |

Expected result: IARC 3+, PEGI 3, ESRB Everyone, USK 0. Before sending, open
Google Play Console > App content > Content rating for the Android app and
keep both stores' answers the same; if Play answered the last question with
Yes, answer Yes here too.

## Pricing, markets and publishing

- **Pricing:** Free. **Markets:** the owner's choice (all markets by default).
- **In-app offers:** none through the Store. The app's "Support Klipa" link
  opens `https://klipa.tv/support/` (GitHub Sponsors) in the browser and
  unlocks nothing. Store Policy 10.8.2 (text of 2026-09-15) allows voluntary
  donations through a secure third-party payment and asks for that use to be
  noted during submission: the certification notes say it, and if Partner
  Center asks about third-party payments, declare it there too. The support
  page must be live before the submission, or the tester meets a dead link.
- **Packages:** the unsigned `KlipaPlayer-<version>-x64.msix` from a green
  `windows-release` run whose artifact name has no `PLACEHOLDER-IDENTITY`
  suffix. The Store signs it after certification.
- **Publishing:** "Publish this submission manually", so the klipa.tv change
  goes live the same day as the listing.
