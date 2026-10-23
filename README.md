# Monarch Codex Android

Flutter Android member app for Monarch Codex. The app uses the official logo, the approved six-item horizontal bottom navigation, a compact push sidebar, black-and-gold styling, UID visibility, and a dark/light appearance toggle.

## Current implementation
- Login and registration UI connected to the mobile API.
- Persisted HTTP session cookies for sign-in continuity.
- Overview reads the signed-in member, NGN/USD wallet balances, exchange-rate reference, KYC status, referral count/link, and unread notification count from the backend.
- Sidebar includes KYC Verification, Referrals, Settings, and Help & Support.
- Wallet money-movement actions still open the existing secure website until dedicated mobile workflows can be connected without bypassing review, KYC, or duplicate-credit safeguards.
- Invest, Market, and Community screens are present; deeper mobile data integration is the next phase. The app does not fabricate balances, prices, earnings, or investment returns.

## API
The mobile API is implemented on the backend feature branch codex/mobile-api under /api/mobile. It must be merged and deployed to https://monarchcodex.online before sign-in from the APK can work. The API uses existing member, wallet, KYC, referral, and notification records. The Android app does not connect directly to MySQL.

## Build APK
The GitHub Actions workflow "Build Monarch Codex Android APK" generates the Android platform project and builds a release APK on pushes to main or codex/**.

1. Open the repository's Actions tab.
2. Open the latest successful "Build Monarch Codex Android APK" run.
3. Download the monarch-codex-android-apk artifact.
4. Extract app-release.apk and install it on a test Android device.

The APK is a test build until the backend API branch is reviewed, merged, and deployed. Do not use it for real financial actions until the end-to-end tests are complete.

## Official branding
assets/images/monarch-codex-logo.svg is copied from the existing Monarch Codex website repository. Do not replace it with a generic crown or placeholder mark.


## Platform completion branch

This branch adds native member notifications, a community feed and composer, Online Cooperative connection submission with manual review status, official social links, and Super Admin screens for Cooperative review, social-link management, and Green/Gold/Red admin permission settings.

The Android app uses the shared API at `https://monarchcodex.online/api/mobile`. The matching website/backend changes are in the companion `trademonarchcodes/monarch-codex-site` branch `codex/platform-completion`.

### Release verification

- The repository workflow `.github/workflows/flutter-android.yml` runs Dart formatting checks, Flutter analysis/tests, and a release APK build.
- Do not distribute an APK unless the workflow has succeeded and the artifact has been checked.
- The companion backend requires the additive migration `migrations/021_platform_completion_foundation.sql`. Apply it only after taking a verified database backup and reviewing the schema.
- Online Cooperative verification is manual. The member submits their registration name and email; the Super Admin confirms with the Cooperative administrator. Never request a Cooperative password or OTP.


## Android system Back navigation

The app handles the Android system Back button and gesture inside Member, Admin, and Sovereign Desk workspaces. It returns to the prior in-app screen or Overview where appropriate and asks for confirmation before exiting from a dashboard root. Verify the latest Flutter checks and release APK build before installing this change.

## In-app updates and navigation badges

The app checks https://monarchcodex.online/api/mobile/app-update/latest on dashboard launch and periodically while the app is open. A newer release shows an update alert and badge. Downloaded APKs are verified against the published SHA-256 checksum before Android's installer opens. Android still requires the member to confirm installation; apps cannot silently replace themselves through a normal APK installer.

The update proxy is implemented in the companion website PR. Hostinger must have MONARCH_ANDROID_RELEASE_TOKEN configured with a GitHub fine-grained token scoped to the private Android repository with repository metadata read and Contents read-only. Keep that token on the server; never put it in Flutter code.

**Stable APK signing is also required for in-place upgrades.** Configure GitHub Actions secrets ANDROID_KEYSTORE_BASE64, ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS, and ANDROID_KEY_PASSWORD using a persistent release keystore. The workflow only publishes the latest-apk release when all four are present, so it does not advertise a debug-signed APK as an installable update. If an already-installed APK was signed with a different key, Android will require a one-time uninstall/reinstall of the consistently signed release; back up anything important before uninstalling. Once the stable signing key is in use, subsequent app updates can be initiated from inside the app.

The member bottom navigation and sidebar show unread badges for relevant notification categories. New community-post counts are tracked on the device/browser since the last time the Community section was opened; these local community counts are not yet synchronized between different devices.

To create a persistent Android release keystore, use Android's keytool to generate it, keep a secure backup, base64-encode the keystore file, and add the four values as repository Actions secrets. Never commit the keystore or its passwords to the repository.
