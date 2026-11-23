#!/usr/bin/env python3
"""Tiny App Store Connect API helper for the TestFlight workflow.

  asc.py create <csr.pem> <out.cer>   – revoke leftover CI certs, create a fresh Apple Development cert, print its id
  asc.py revoke <cert id>             – revoke the cert this run made
"""
import base64, json, os, sys, time, urllib.request, urllib.error
import jwt  # PyJWT

KEY_ID, ISSUER, KEY_PATH = os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"], os.environ["KEY_PATH"]
API = "https://api.appstoreconnect.apple.com/v1"

def token():
    now = int(time.time())
    return jwt.encode({"iss": ISSUER, "iat": now, "exp": now + 1000, "aud": "appstoreconnect-v1"},
                      open(KEY_PATH).read(), algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"})

def call(method, path, body=None):
    req = urllib.request.Request(API + path, method=method,
                                 data=json.dumps(body).encode() if body else None,
                                 headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        print(f"{method} {path} → {e.code}: {e.read().decode()[:800]}", file=sys.stderr)
        raise

def leftovers():
    certs = call("GET", "/certificates?limit=200")["data"]
    for c in certs:
        a = c["attributes"]
        print(f"  cert {c['id']}  {a.get('certificateType')}  {a.get('name')!r}  {a.get('displayName')!r}", file=sys.stderr)
    # Only certificates Xcode/CI made with the API key — never your own or SideStore's.
    return [c["id"] for c in certs
            if c["attributes"].get("certificateType") in ("DEVELOPMENT", "IOS_DEVELOPMENT")
            and "Created via API" in f"{c['attributes'].get('name')} {c['attributes'].get('displayName')}"]

cmd = sys.argv[1]
if cmd == "create":
    for cid in leftovers():
        print(f"revoking leftover CI cert {cid}", file=sys.stderr)
        call("DELETE", f"/certificates/{cid}")
    csr = open(sys.argv[2]).read()
    res = call("POST", "/certificates", {"data": {"type": "certificates", "attributes":
                                          {"certificateType": "DEVELOPMENT", "csrContent": csr}}})
    open(sys.argv[3], "wb").write(base64.b64decode(res["data"]["attributes"]["certificateContent"]))
    print(res["data"]["id"])
elif cmd == "revoke":
    call("DELETE", f"/certificates/{sys.argv[2]}")
    print("revoked", sys.argv[2], file=sys.stderr)
