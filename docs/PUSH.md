# Push notifications (Firebase Cloud Messaging)

Optional. Without it everything still works and updates appear in the app's **Inbox**. With it,
phones get a notification for new tasks, announcements, meeting invitations/changes, minutes and
the morning reminders. No app rebuild is needed: the app downloads the public Firebase settings
from the server when it starts.

## 1. Create the Firebase project (free)
1. Go to <https://console.firebase.google.com> → **Add project** (e.g. "KSA Riyadh Unit").
   Google Analytics can be off.
2. **Add app → Android**. Package name: `com.halacreative.ksa_riyadh`. Skip downloading
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
In `/etc/orgmanager/env`:
```
FIREBASE_CREDENTIALS=/var/lib/orgmanager/firebase.json
FIREBASE_PROJECT_ID=your-project-id
FIREBASE_API_KEY=AIza...
FIREBASE_APP_ID=1:1234567890:android:abc123
FIREBASE_SENDER_ID=1234567890
```
Then `systemctl restart orgmanager`. Open the app (sign out and in once on phones that were
already signed in) and allow notifications. Profile → *Phone notifications* shows "On".

The server signs a short-lived token with the service account and calls Google's FCM HTTP v1
API from a background thread — no extra Python packages or memory.
