# Publishing RT Trainer on the Mac App Store

RT Trainer is set up as a paid-up-front app (for example £9.99) with no in-app purchases. Every scenario ships inside the app, and new scenarios download free.

## 1. One-time setup

1. Join the [Apple Developer Program](https://developer.apple.com/programs/) (£79/year).
2. In [App Store Connect](https://appstoreconnect.apple.com) › Business, accept the **Paid Apps Agreement** and add your bank and tax details. Paid apps can't go on sale until this is active.
3. In [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list), register an App ID such as `uk.yourname.rttrainer`. No extra capabilities are needed.

## 2. Configure the project

1. Open `App/RTTrainer.xcodeproj` in Xcode 16 or later.
2. Edit `App/Config.xcconfig`:
   - `DEVELOPMENT_TEAM`: your 10-character Team ID (developer.apple.com › Account › Membership).
   - `PRODUCT_BUNDLE_IDENTIFIER`: the App ID you registered.
3. Select the **RT Trainer** scheme and press ⌘R to check that it runs. Allow microphone and speech recognition when asked.

Already set up in the project:

| Item | Setting |
|---|---|
| App Sandbox | On, with Microphone and Outgoing Connections (Client) |
| Hardened Runtime | On |
| Privacy manifest | `App/PrivacyInfo.xcprivacy`: no tracking, no data collected |
| Export compliance | `ITSAppUsesNonExemptEncryption = NO`, so no questions at upload |
| Category | Education |
| Minimum macOS | 14.0 |
| Version | 1.0 (build 1). Raise the build number for each upload. |

## 3. Create the App Store listing

In App Store Connect › Apps › **+** › New App:

- **Platform:** macOS. **Name:** for example "RT Trainer – UK Radio Practice". **Bundle ID:** the one above. **SKU:** any unique string.
- **Pricing and Availability:** pick the £9.99 price point (Apple shows it as a tier; UK customers pay £9.99 including VAT). Choose the countries you want.
- **App Privacy:** answer **"No, we do not collect data from this app"**.
- **Privacy Policy URL:** host `docs/PRIVACY.md` somewhere public (a GitHub Pages site or the file's GitHub URL) after adding your email address.
- **Category:** Education (secondary: Reference).
- **Age rating:** 4+.
- **Screenshots:** at least one at 1280×800, 1440×900, 2560×1600 or 2880×1800.
- **Description:** say plainly that it's a practice aid, not an approved training device, and isn't affiliated with the CAA. App Review rejects apps that appear to claim official status.

## 4. Upload

1. In Xcode, set the destination to **Any Mac**, then **Product › Archive**.
2. In the Organizer, choose **Distribute App › App Store Connect › Upload**. Xcode signs it automatically.
3. Back in App Store Connect, pick the build in your version, fill in **App Review Information** (tell the reviewer: "Pick any scenario, press Start Scenario, hold the space bar and speak; a headset is recommended"), and **Submit for Review**.

## Notes

- `make run` (the Swift Package build in `scripts/build-app.sh`) still works for development. It isn't sandboxed and can't be submitted.
- Before release, check the phraseology against the current edition of [CAP 413](https://www.caa.co.uk/cap413).
- Using the CAA's name or logo in the app name, icon or screenshots is likely to be rejected and may infringe their trademark. Mentioning "CAP 413" in descriptive text is fine.
