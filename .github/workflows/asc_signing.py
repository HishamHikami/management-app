"""App Store signing without registered devices, for the iOS workflow (ios.yml).

Uses the App Store Connect API key (from GitHub secrets) to:
  setup         create a fresh Apple Distribution certificate (new private key + CSR) and an
                App Store provisioning profile for the app, and write them to a folder
  patch-project switch the Runner target to manual signing with that profile
  wait-build    wait until App Store Connect has finished processing the uploaded build
  cleanup       delete the profile and revoke the certificate created by `setup` (never any other)

Lives next to the workflow on purpose: the server's deploy script only accepts reviewed files
under .github/workflows/, so this file is covered by the same review.
"""

import base64
import json
import os
import re
import secrets
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID

API = "https://api.appstoreconnect.apple.com/v1"


def token():
    with open(os.environ["ASC_KEY_PATH"]) as f:
        key = f.read()
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
        key,
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
    )


def call(method, path, body=None, fatal=True):
    req = urllib.request.Request(
        API + path,
        method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": f"Bearer {token()}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            data = r.read()
            return json.loads(data) if data else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")[:2000]
        if not fatal:
            print(f"warning: {method} {path} -> HTTP {e.code}: {detail}")
            return None
        sys.exit(f"App Store Connect API {method} {path} failed: HTTP {e.code}\n{detail}")


def q(params):
    return "?" + urllib.parse.urlencode(params)


def bundle_resource_id(identifier):
    res = call("GET", "/bundleIds" + q({"filter[identifier]": identifier, "limit": 200}))
    for item in res.get("data", []):
        if item["attributes"]["identifier"] == identifier:
            return item["id"]
    sys.exit(f"Bundle ID {identifier} is not registered in Certificates, Identifiers & Profiles.")


def setup(out, identifier, profile_name):
    os.makedirs(out, exist_ok=True)
    bid = bundle_resource_id(identifier)

    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    csr = (
        x509.CertificateSigningRequestBuilder()
        .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "KSA Riyadh CI")]))
        .sign(key, hashes.SHA256())
    )
    csr_pem = csr.public_bytes(serialization.Encoding.PEM).decode()
    res = call("POST", "/certificates", {"data": {"type": "certificates", "attributes": {
        "certificateType": "DISTRIBUTION", "csrContent": csr_pem}}})
    cert_id = res["data"]["id"]
    state = {"certificate_id": cert_id}
    _save(out, state)  # saved early so cleanup can revoke even if a later step fails

    cert = x509.load_der_x509_certificate(base64.b64decode(res["data"]["attributes"]["certificateContent"]))
    password = secrets.token_urlsafe(18)
    # Legacy PKCS#12 algorithms: macOS `security import` doesn't accept the newer ones.
    enc = (serialization.PrivateFormat.PKCS12.encryption_builder()
           .kdf_rounds(50000)
           .key_cert_algorithm(pkcs12.PBES.PBESv1SHA1And3KeyTripleDESCBC)
           .hmac_hash(hashes.SHA1())
           .build(password.encode()))
    p12 = pkcs12.serialize_key_and_certificates(b"KSA Riyadh CI", key, cert, None, enc)
    with open(f"{out}/dist.p12", "wb") as f:
        f.write(p12)
    with open(f"{out}/p12pass", "w") as f:
        f.write(password)

    res = call("POST", "/profiles", {"data": {
        "type": "profiles",
        "attributes": {"name": profile_name, "profileType": "IOS_APP_STORE"},
        "relationships": {
            "bundleId": {"data": {"type": "bundleIds", "id": bid}},
            "certificates": {"data": [{"type": "certificates", "id": cert_id}]},
        },
    }})
    attrs = res["data"]["attributes"]
    state.update(profile_id=res["data"]["id"], uuid=attrs["uuid"], name=attrs["name"])
    _save(out, state)
    with open(f"{out}/profile.mobileprovision", "wb") as f:
        f.write(base64.b64decode(attrs["profileContent"]))
    print(f"Created certificate {cert_id} and profile '{attrs['name']}' ({attrs['uuid']}).")


def _save(out, state):
    with open(f"{out}/state.json", "w") as f:
        json.dump(state, f)


def patch_project(pbxproj, identifier, team, profile_name):
    """Manual Apple Distribution signing for the app target's build configurations only."""
    with open(pbxproj) as f:
        text = f.read()
    keys = ("CODE_SIGN_STYLE", "CODE_SIGN_IDENTITY", '"CODE_SIGN_IDENTITY[sdk=iphoneos*]"',
            "DEVELOPMENT_TEAM", "PROVISIONING_PROFILE_SPECIFIER", "PROVISIONING_PROFILE")
    changed = 0

    def fix(m):
        nonlocal changed
        block = m.group(0)
        if f"PRODUCT_BUNDLE_IDENTIFIER = {identifier};" not in block:
            return block
        lines = [l for l in block.split("\n") if not any(l.strip().startswith(k + " ") for k in keys)]
        add = [
            "\t\t\t\tCODE_SIGN_STYLE = Manual;",
            '\t\t\t\tCODE_SIGN_IDENTITY = "Apple Distribution";',
            '\t\t\t\t"CODE_SIGN_IDENTITY[sdk=iphoneos*]" = "Apple Distribution";',
            f"\t\t\t\tDEVELOPMENT_TEAM = {team};",
            f'\t\t\t\tPROVISIONING_PROFILE_SPECIFIER = "{profile_name}";',
        ]
        changed += 1
        return "\n".join(lines[:1] + add + lines[1:])

    text = re.sub(r"buildSettings = \{.*?\n\t\t\t\};", fix, text, flags=re.S)
    if not changed:
        sys.exit("Could not find the app target's build settings in project.pbxproj.")
    with open(pbxproj, "w") as f:
        f.write(text)
    print(f"Manual signing set on {changed} build configuration(s).")


def wait_build(identifier, build_number, out, minutes=30):
    apps = call("GET", "/apps" + q({"filter[bundleId]": identifier}))
    app = next((a for a in apps.get("data", []) if a["attributes"]["bundleId"] == identifier), None)
    if not app:
        sys.exit(f"No app with bundle ID {identifier} in App Store Connect (create it under Apps → +).")
    deadline = time.time() + minutes * 60
    state = "not visible yet"
    while time.time() < deadline:
        res = call("GET", "/builds" + q({"filter[app]": app["id"], "filter[version]": build_number, "limit": 1}),
                   fatal=False) or {}
        if res.get("data"):
            state = res["data"][0]["attributes"].get("processingState")
            if state == "VALID":
                print(f"Build {build_number} is processed and ready in TestFlight.")
                return
            if state in ("FAILED", "INVALID"):
                sys.exit(f"App Store Connect could not process build {build_number}: {state}. Check email from Apple.")
        print(f"Waiting for App Store Connect to process build {build_number} ({state})…")
        time.sleep(30)
    # Keep the certificate: revoking it while Apple is still processing could spoil the build.
    open(f"{out}/keep", "w").close()
    print(f"Build {build_number} still processing after {minutes} min; it will appear in TestFlight later. "
          "The signing certificate is kept this time (revoke 'KSA Riyadh CI' later if needed).")


def cleanup(out):
    try:
        with open(f"{out}/state.json") as f:
            state = json.load(f)
    except OSError:
        print("Nothing to clean up.")
        return
    if state.get("profile_id"):
        call("DELETE", f"/profiles/{state['profile_id']}", fatal=False)
    if state.get("certificate_id") and not os.path.exists(f"{out}/keep"):
        call("DELETE", f"/certificates/{state['certificate_id']}", fatal=False)
        print("Removed the temporary signing certificate and profile.")


if __name__ == "__main__":
    cmd, *args = sys.argv[1:]
    {"setup": setup, "patch-project": patch_project, "wait-build": wait_build, "cleanup": cleanup}[cmd](*args)
