# Releasing to Google Play and the App Store

Builds run on GitHub Actions (this repo is public; signing material lives only in
**Settings → Secrets and variables → Actions**, never in files). Every push that changes `mobile/`
builds both apps; you can also run them by hand from the **Actions** tab → *iOS* / *Android* →
**Run workflow**.

App ID everywhere: `com.halacreative.ksariyadh` · Name: **KSA Riyadh Unit** · Home-screen label: **KSA Riyadh**

---

## 1. Android: upload key (once)

You need Java's `keytool`. Easiest on Windows: install **Temurin JDK 17** from https://adoptium.net
(or use Android Studio's). In PowerShell:

```powershell
keytool -genkeypair -v -keystore ksa-riyadh-upload.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000
```
Choose a strong password (remember it), answer the name questions (any values). Then:
```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("ksa-riyadh-upload.jks")) | Set-Clipboard
```
Add these **repository secrets**:

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | paste (the clipboard from the command above) |
| `ANDROID_KEYSTORE_PASSWORD` | your keystore password |
| `ANDROID_KEY_ALIAS` | `upload` |
| `ANDROID_KEY_PASSWORD` | same password (unless you chose a different key password) |

Keep `ksa-riyadh-upload.jks` + password in a safe place (password manager / private drive).
With **Play App Signing** (default), Google holds the real signing key; if this upload key is ever
lost, Google support can reset it.

Run **Actions → Android → Run workflow**. When green, open the run → **Artifacts** → download
`ksa-riyadh-android-N` → it contains `app-release.aab` (for Play) and `app-release.apk`.

## 2. Google Play (personal account)

1. Play Console → **Create app** → name `KSA Riyadh Unit`, default language English, App, Free.
2. **Set up your app** (the dashboard checklist) — answers are in [STORE.md](STORE.md):
   privacy policy URL, app access (reviewer login), ads (no), content rating, target audience
   (18+), data safety, government app (no), financial features (none), health (no).
3. **Store listing**: texts, icon `mobile/branding/icon-512-play.png`, feature graphic
   `mobile/branding/feature-graphic.png`, phone screenshots from `mobile/branding/screenshots/`.
4. **Testing → Closed testing → Create track** → upload the `.aab` → add testers by email
   (your members' Google accounts, at least **12**) → roll out. Share the opt-in link with them.
5. New personal accounts must run the closed test with **12+ testers for 14 days**; then
   **Apply for production** in the dashboard and roll out. Members keep the app and get updates.

## 3. Apple: API key for automatic signing (once)

1. https://appstoreconnect.apple.com → **Users and Access → Integrations → App Store Connect API**
   → **Team Keys → +** → name `GitHub builds`, access **Admin** (needed so the build can create
   its distribution certificate and profile) → **Generate** → **Download** the `.p8` (once only;
   if the browser saves it as `.p8.pem`, that's fine — it's the same text).
2. Note the **Key ID** and the **Issuer ID** (top of that page). Your **Team ID** is at
   https://developer.apple.com/account → Membership details.
3. Add repository secrets:

| Secret | Value |
|---|---|
| `ASC_KEY_ID` | Key ID |
| `ASC_ISSUER_ID` | Issuer ID |
| `ASC_KEY_P8` | the whole text of the `.p8` file (open it in Notepad, copy everything incl. the BEGIN/END lines) |
| `APPLE_TEAM_ID` | Team ID |

4. App Store Connect → **Apps → + New App**: iOS, name `KSA Riyadh Unit`, language English,
   bundle ID `com.halacreative.ksariyadh` (registered earlier with Push), SKU `ksariyadh`,
   access **Full**.
5. **Actions → iOS → Run workflow**. It builds, signs and uploads; the build shows in
   **TestFlight** 5–30 minutes later (answer "None of the algorithms" / no encryption if asked —
   the app already declares it).

## 4. TestFlight, then the unlisted App Store page

1. **TestFlight → External testing → +** group `Members` → add the build → fill *Test information*
   (reviewer login from STORE.md) → submit for beta review (usually < 1 day) → **Enable public link**
   and share it. Members install **TestFlight**, then the app. Builds expire after 90 days.
2. **App Store** tab → version 1.x: texts, screenshots (`mobile/branding/screenshots/` are
   1290×2796, accepted for 6.9"), privacy policy URL, **App Privacy** answers (STORE.md),
   **App Review Information** → sign-in required → reviewer login → **Submit for review**.
3. After approval, request **Unlisted App Distribution**:
   https://developer.apple.com/contact/request/unlisted-app/ — app name, Apple ID, and
   "Members-only app for our association; accounts are created by invitation only." Once approved
   the app is reachable only through its App Store link (not in search). Share that link.

## Every update

Bump `version:` in `mobile/pubspec.yaml` (e.g. `1.1.0+3` → `1.2.0+4`; build numbers are set
automatically by the workflows), push, then upload the new `.aab` to Play and pick the new build in
App Store Connect / TestFlight.
