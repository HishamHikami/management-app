"""Push notifications through Firebase Cloud Messaging (HTTP v1 API).

No Google SDK: a service-account key signs a short JWT (RS256, via `cryptography`), which is
exchanged for an access token, cached for ~50 minutes. Sending runs in a background thread so
requests never wait on Google. If FIREBASE_CREDENTIALS is empty, nothing is sent.
"""

import base64
import json
import logging
import threading
import time
import urllib.error
import urllib.request

from django.conf import settings
from django.db import close_old_connections

log = logging.getLogger("org.push")

_token = {"value": None, "expires": 0.0}
_lock = threading.Lock()


def enabled():
    return bool(settings.FIREBASE_CREDENTIALS and settings.FIREBASE.get("projectId"))


def _b64(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def _access_token():
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import padding

    with _lock:
        if _token["value"] and _token["expires"] > time.time() + 60:
            return _token["value"]
        with open(settings.FIREBASE_CREDENTIALS) as f:
            sa = json.load(f)
        now = int(time.time())
        header = _b64(json.dumps({"alg": "RS256", "typ": "JWT"}).encode())
        claims = _b64(json.dumps({
            "iss": sa["client_email"],
            "scope": "https://www.googleapis.com/auth/firebase.messaging",
            "aud": sa.get("token_uri", "https://oauth2.googleapis.com/token"),
            "iat": now,
            "exp": now + 3600,
        }).encode())
        key = serialization.load_pem_private_key(sa["private_key"].encode(), password=None)
        sig = key.sign(f"{header}.{claims}".encode(), padding.PKCS1v15(), hashes.SHA256())
        assertion = f"{header}.{claims}.{_b64(sig)}"
        body = (
            "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=" + assertion
        ).encode()
        req = urllib.request.Request(
            sa.get("token_uri", "https://oauth2.googleapis.com/token"),
            data=body,
            headers={"Content-Type": "application/x-www-form-urlencoded"},
        )
        with urllib.request.urlopen(req, timeout=15) as r:
            data = json.load(r)
        _token["value"] = data["access_token"]
        _token["expires"] = time.time() + int(data.get("expires_in", 3600)) - 600
        return _token["value"]


def _send_one(access, device_token, kind, object_id, title, body, urgent):
    msg = {
        "message": {
            "token": device_token,
            "notification": {"title": title, "body": body},
            "data": {"kind": kind, "id": str(object_id or "")},
            "android": {
                "priority": "HIGH" if urgent or kind in ("task", "meeting") else "NORMAL",
                "notification": {"channel_id": "updates", "tag": f"{kind}-{object_id}"},
            },
        }
    }
    url = f"https://fcm.googleapis.com/v1/projects/{settings.FIREBASE['projectId']}/messages:send"
    req = urllib.request.Request(
        url,
        data=json.dumps(msg).encode(),
        headers={"Authorization": f"Bearer {access}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=15):
            return True
    except urllib.error.HTTPError as e:
        # 404 UNREGISTERED / 400 INVALID_ARGUMENT: the app was removed or the token is stale.
        if e.code in (400, 404):
            return False
        log.warning("FCM send failed: HTTP %s", e.code)
        return True


def send(member_ids, kind, object_id, title, body, urgent=False):
    from .models import Device

    if not enabled():
        return
    tokens = list(Device.objects.filter(member_id__in=member_ids).values_list("token", flat=True))
    if not tokens:
        return
    try:
        access = _access_token()
    except Exception as e:  # noqa: BLE001 - never let push break the app
        log.warning("FCM auth failed: %s", e)
        return
    stale = [t for t in tokens if not _send_one(access, t, kind, object_id, title, body, urgent)]
    if stale:
        Device.objects.filter(token__in=stale).delete()


def send_async(member_ids, kind, object_id, title, body, urgent=False):
    if not enabled():
        return

    def run():
        try:
            send(member_ids, kind, object_id, title, body, urgent)
        except Exception as e:  # noqa: BLE001
            log.warning("Push failed: %s", e)
        finally:
            close_old_connections()

    threading.Thread(target=run, daemon=True).start()
