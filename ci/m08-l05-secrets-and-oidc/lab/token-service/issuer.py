"""Lab stand-in for GitHub's OIDC token service (M08-L05 "Secrets and OIDC"). LAB ONLY.

GitHub gives every job that has `permissions: id-token: write` two variables, ACTIONS_ID_TOKEN_REQUEST_URL and
ACTIONS_ID_TOKEN_REQUEST_TOKEN. The job calls the URL with the bearer token and gets back a short-lived JWT, signed
by GitHub, whose claims say which repository, branch and workflow the job is running for.

Gitea 28.1.0 has no such service. This one does the same job for the lab:
  1. the job sends the runtime token Gitea already gave it (ACTIONS_RUNTIME_TOKEN) as the bearer token;
  2. we ask Gitea itself whether that token is genuine and for which run (Gitea's artifact API accepts it only for
     its own run and job); claims the job makes about itself are never trusted;
  3. we read that run from Gitea's API (repository, branch from the run's workflow ref, event, commit, actor) and
     check it is still running;
  4. we sign a JWT (RS256, a key generated at start-up, published as JWKS) that expires in 5 minutes.
The private key never leaves this container. Vault (or a cloud) checks the signature with the published JWKS.
"""
import base64, json, os, time, uuid, urllib.request, urllib.error
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs
import jwt
from cryptography.hazmat.primitives.asymmetric import rsa

ISS = os.environ["ISSUER"]                  # e.g. http://token-service:8080
GITEA = os.environ["GITEA_URL"]             # http://gitea:3000
TOKEN_FILE = os.environ["GITEA_TOKEN_FILE"]   # a read-only lab token for the Gitea API, read per request, never logged
TTL = 300
KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)
KID = uuid.uuid4().hex[:16]
JWK = json.loads(jwt.algorithms.RSAAlgorithm.to_jwk(KEY.public_key())) | {"kid": KID, "use": "sig", "alg": "RS256"}

def log(msg): print(time.strftime("%H:%M:%S"), msg, flush=True)

def http(method, url, token, body=None, scheme="token"):
    req = urllib.request.Request(url, method=method, data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Authorization": f"{scheme} {token}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=10) as r: return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e: return e.code, {}

def b64json(seg): return json.loads(base64.urlsafe_b64decode(seg + "=" * (-len(seg) % 4)))

def mint(runtime_token, audience, repository):
    try: rt = b64json(runtime_token.split(".")[1])        # claims are only read here; Gitea verifies them below
    except Exception: return None, "bearer token is not a Gitea runtime token"
    run_id, job_id = rt.get("RunID"), rt.get("JobID")
    st, _ = http("POST", f"{GITEA}/twirp/github.actions.results.api.v1.ArtifactService/ListArtifacts", runtime_token,
                 {"workflowRunBackendId": str(run_id), "workflowJobRunBackendId": str(job_id)}, scheme="Bearer")
    if st != 200: return None, f"Gitea did not accept the runtime token (HTTP {st})"
    st, run = http("GET", f"{GITEA}/api/v1/repos/{repository}/actions/runs/{run_id}", open(TOKEN_FILE).read().strip())
    if st != 200: return None, f"run {run_id} is not a run of {repository}"
    if run.get("status") not in ("in_progress", "running", "waiting"): return None, f"run {run_id} is not running"
    wf, ref = run["path"].split("@", 1)                   # "deploy.yml@refs/heads/main"
    pr = run["event"].startswith("pull_request")
    now = int(time.time())
    claims = {"iss": ISS, "aud": audience, "sub": f"repo:{repository}:" + ("pull_request" if pr else f"ref:{ref}"),
              "repository": repository, "ref": ref, "sha": run["head_sha"], "event_name": run["event"],
              "workflow_ref": f"{repository}/.gitea/workflows/{wf}@{ref}", "run_id": str(run_id),
              "actor": (run.get("trigger_actor") or {}).get("login", ""), "jti": str(uuid.uuid4()),
              "iat": now, "nbf": now, "exp": now + TTL}
    return jwt.encode(claims, KEY, algorithm="RS256", headers={"kid": KID}), claims

class H(BaseHTTPRequestHandler):
    def send(self, code, obj):
        b = json.dumps(obj).encode(); self.send_response(code); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def log_message(self, *a): pass
    def do_GET(self):
        u = urlparse(self.path); q = parse_qs(u.query)
        if u.path == "/.well-known/openid-configuration":
            return self.send(200, {"issuer": ISS, "jwks_uri": f"{ISS}/.well-known/jwks", "subject_types_supported": ["public"],
                                   "response_types_supported": ["id_token"], "id_token_signing_alg_values_supported": ["RS256"],
                                   "claims_supported": ["sub", "aud", "exp", "iat", "iss", "jti", "nbf", "ref", "repository", "sha", "event_name", "workflow_ref", "run_id", "actor"]})
        if u.path == "/.well-known/jwks": return self.send(200, {"keys": [JWK]})
        if u.path == "/token":
            auth = self.headers.get("Authorization", "")
            aud, repo = q.get("audience", [""])[0], q.get("repository", [""])[0]
            if not auth.lower().startswith("bearer ") or not aud or not repo: return self.send(400, {"message": "need bearer token, audience, repository"})
            tok, c = mint(auth.split(" ", 1)[1], aud, repo)
            if not tok: log(f"refused: {c}"); return self.send(403, {"message": c})
            log(f"issued sub={c['sub']} aud={aud} run={c['run_id']} expires in {TTL}s")
            return self.send(200, {"value": tok})
        self.send(404, {"message": "not found"})

log(f"lab token service, issuer {ISS}, signing key kid={KID} (RS256), token lifetime {TTL}s")
ThreadingHTTPServer(("0.0.0.0", 8080), H).serve_forever()
