# Push notifications (Firebase Cloud Messaging)

Optional. Without it everything still works and updates appear in the app's **Inbox**. With it,
phones get a notification for new tasks, announcements, meeting invitations/changes, minutes and
the morning reminders. No app rebuild is needed: the app downloads the public Firebase settings
from the server when it starts.

## 1. Create the Firebase project (free)
1. Go to <https://console.firebase.google.com> → **Add project** (e.g. "KSA Riyadh Unit").
   Google Analytics can be off.
2. **Add app → Android**. Package name: `com.halacreative.ksariyadh`. Skip downloading
   `google-services.json` — it isn't needed.
3. **Project settings → General → Your apps**: note the **App ID** (`1:…:android:…`),
   **Project ID**, **Web API key** and, under **Cloud Messaging**, the **Sender ID**.

## 2. Service account for the server
**Project settings → Service accounts → Generate new private key**. A JSON file downloads —
treat it like a password.

```bash
install -m 600 -o orgmanager -g orgmanager firebase-key.json /var/lib/orgmanager/firebase.json
```
(Copy it to the droplet with `scp` first, then delete your local copy.) It goes in the app's data
folder because `/etc/orgmanager` is readable by root only; only the `orgmanager` user can read it.

## 3. Settings
In `/etc/orgmanager/env` (values from `google-services.json` and `GoogleService-Info.plist`;
they are public app settings, but are kept out of this public repo):
```
FIREBASE_CREDENTIALS=/var/lib/orgmanager/firebase.json
FIREBASE_PROJECT_ID=ksa-riyadh-unit
FIREBASE_SENDER_ID=<GCM_SENDER_ID / project_number>
FIREBASE_ANDROID_APP_ID=<mobilesdk_app_id from google-services.json>
FIREBASE_ANDROID_API_KEY=<api_key.current_key from google-services.json>
FIREBASE_IOS_APP_ID=<GOOGLE_APP_ID from GoogleService-Info.plist>
FIREBASE_IOS_API_KEY=<API_KEY from GoogleService-Info.plist>
```
Then `systemctl restart orgmanager`. Open the app and allow notifications; Profile →
*Phone notifications* shows "On". iPhones also need the APNs key uploaded in Firebase
(Project settings → Cloud Messaging → Apple app configuration).

The server signs a short-lived token with the service account and calls Google's FCM HTTP v1
API from a background thread — no extra Python packages or memory.
