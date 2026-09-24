CTLABS - Automation
===================

GCP Auth via Workload Identity Federation (Vault OIDC)
--------------------------------------------------------

This is the second supported `terraform.auth.method` for the ansible/ctrl
container, alongside the existing [Vault GCP Secrets Engine](./ctlabs.docs.vault.engine.gcp.md).

Where the GCP Secrets Engine requires Vault to hold a long-lived **Admin
Service Account key** (`vault write gcp/config credentials=@...json`) and use
it to call GCP's IAM API on your behalf, Workload Identity Federation (WIF)
flips the trust direction: **Vault never holds any GCP credential at all.**
Vault's built-in `identity/oidc` engine signs a short-lived JWT about its own
identities, and GCP is configured to trust Vault's signature directly. No
service-account key is ever created, in Vault or in GCP, and the whole
exchange is 3 plain HTTPS calls - no `gcloud`/Cloud SDK install required
anywhere.

### Runtime flow (implemented in `ctlabs/lib/gcp_auth.rb`)

1. `vault read identity/oidc/token/<vault_role>` -> short-lived signed JWT.
2. `POST https://sts.googleapis.com/v1/token` (token exchange) with that JWT
   as `subject_token`, `audience` = the WIF provider's resource name ->
   federated GCP token (unprivileged, scoped only to "act as this WIF
   identity").
3. `POST https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/<SA_EMAIL>:generateAccessToken`
   using the federated token as bearer auth -> final OAuth2 access token with
   the target service account's actual IAM permissions. This is what gets
   injected as `GOOGLE_OAUTH_ACCESS_TOKEN` / `CLOUDSDK_AUTH_ACCESS_TOKEN`,
   exactly like the Vault Secrets Engine path.

### Three tokens, three independent lifetimes

Each hop above produces its own token with its own TTL - they are **not**
chained or capped by each other, which is easy to assume incorrectly (we did,
2026-09-24):

| # | Token                           | Lifetime governed by                                       | Cached / visible anywhere? |
|---|---------------------------------|------------------------------------------------------------|-----------------------------|
| 1 | Vault OIDC identity token       | `ttl=` on `identity/oidc/role/<name>` (e.g. `10m`)         | No - consumed immediately by step 2 |
| 2 | Federated STS token             | Google's default for the token-exchange grant type         | No - consumed immediately by step 3 |
| 3 | Final impersonated access token | `generateAccessToken`'s own default (**1 hour**, since `ctlabs/lib/gcp_auth.rb`'s `generate_access_token` doesn't pass a `lifetime` param) | **Yes** - this is what `GcpAuth`'s `@wif_cache` holds and what the `/vault/info` webgui panel and `$GOOGLE_OAUTH_ACCESS_TOKEN` both show |

So a short Vault role `ttl` (e.g. `10m`) only bounds how long the *identity
assertion* is valid for exchange - it has **no effect** on how long the
resulting GCP credential actually lives. If you want the final GCP token to
be shorter-lived too (tighter security posture, closer to how the Vault GCP
Secrets Engine path ties the GCP token TTL directly to Vault's own lease),
that requires explicitly passing a `lifetime` field in the `generateAccessToken`
request body in `GcpAuth.generate_access_token` - not currently implemented.

---

### One-time Vault Setup

0. **ACL policy.** The token running these commands (and `vault_oidc_setup.py`)
   needs this attached. Note `identity/oidc/config` only needs `update`, never
   `create` - it's a singleton that already exists the moment the identity
   engine is up, so a policy with only `create` here 403s on the very first
   write, not just on re-runs:

```hcl
path "identity/oidc/config" {
  capabilities = ["read", "update"]
}
path "identity/oidc/key/*" {
  capabilities = ["create", "read", "update", "delete"]
}
path "identity/oidc/role/*" {
  capabilities = ["create", "read", "update", "delete"]
}
path "identity/oidc/token/*" {
  capabilities = ["read"]
}
```

1. **Pin Vault's OIDC issuer** to a fixed, externally-resolvable string. GCP
   will validate the `iss` claim on every token against exactly this string,
   so set it explicitly instead of relying on Vault's default (which follows
   `api_addr` and can drift):

```bash
vault write identity/oidc/config issuer="https://vdb1.ctlabs.internal:8200"
```

2. **Enable a signing key** (no GCP credential involved - Vault's own key):

```bash
vault write identity/oidc/key/gcp-wif-key \
    allowed_client_ids="*" rotation_period=24h verification_ttl=24h
```

3. **Define a role, with `client_id` set to the GCP audience string.** Vault's
   `client_id` becomes the token's `aud` claim. If you leave it unset, Vault
   auto-generates a random one (e.g. `z2GjUgfvrkXy0yLdKN8kCOgbFP`) - and GCP's
   WIF provider rejects any token whose `aud` doesn't equal the provider's own
   resource name (by default, unless you widen it with `--allowed-audiences`),
   so an unset `client_id` **always** fails with `The audience in ID Token
   [...] does not match the expected audience` (hit this exact bug
   2026-09-23, right after fixing the issuer mismatch below). The audience
   string is fully computable in advance - project number is fixed, pool/
   provider names are whatever you choose - so get it before writing the role:

```bash
PROJECT_NUMBER=$(gcloud projects describe my-project --format='value(projectNumber)')
AUDIENCE="//iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/ctlabs-vault-pool/providers/vault-provider"

vault write identity/oidc/role/gcp-wif \
    key=gcp-wif-key \
    ttl=10m \
    client_id="${AUDIENCE}"
```

   If you didn't do this up front, it's a safe idempotent fix after the fact -
   just re-run the same `vault write` with `client_id` added once you know the
   audience (`vault_oidc_setup.py --client-id ...` does the same).

4. **Look up the `sub` claim** you'll bind IAM permissions to. Vault sets
   `sub` to the calling identity's **entity ID** (a stable UUID, not the
   username) - decode a test token to see it before writing the IAM binding
   in the GCP setup below:

```bash
TOKEN=$(vault read -field=token identity/oidc/token/gcp-wif)
echo "$TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | python3 -m json.tool
# {
#   "iss": "https://vdb1.ctlabs.internal:8200/v1/identity/oidc",   <- NOTE: Vault appends
#                                                                       this suffix automatically -
#                                                                       use the FULL string below,
#                                                                       not the bare issuer= value
#   "sub": "3f2c1a9e-....-....-....-............",   <- this is the value GCP will see
#   "aud": "...",
#   ...
# }
```

   **`vault_oidc_setup.py` prints this `iss` value directly** - always copy it
   from the script's output rather than reusing the bare `--issuer`/`issuer=`
   value; using the un-suffixed address as `--issuer-uri` on the GCP side
   causes GCP to reject every token with `the issuer in ID Token ... does not
   match the expected one in config` (hit this exact bug 2026-09-23).

5. **Reachability note:** Google's STS service normally verifies the JWT
   signature by fetching Vault's OIDC discovery + JWKS documents over the
   internet. If Vault (`https://vdb1.ctlabs.internal:8200`) is **not**
   internet-reachable, use GCP's "OIDC without discovery" mode instead
   (upload the JWKS JSON directly to the WIF provider - see step 3 below) so
   GCP never needs to reach Vault at all.

---

### One-time GCP Setup

All commands below assume you're authenticated as a human with
`Owner`/`IAM Admin` on the target project, and use `my-project` as a
placeholder - swap in your real project ID throughout.

0. **Enable the required APIs** (one-time per project):

```bash
gcloud services enable iam.googleapis.com \
    sts.googleapis.com \
    iamcredentials.googleapis.com \
    --project=my-project
```

1. **Create a Workload Identity Pool** (one per project/org, reusable across
   labs):

```bash
gcloud iam workload-identity-pools create ctlabs-vault-pool \
    --project=my-project \
    --location=global \
    --display-name="CTLabs Vault OIDC Pool"
```

2. **Create an OIDC provider** in that pool, pointing at Vault as the issuer.
   The `--issuer-uri` must be **exactly** the real `iss` claim from step 4
   above - Vault appends `/v1/identity/oidc` to whatever you pinned in
   `identity/oidc/config issuer=...`, so that suffix must be included here too:

```bash
gcloud iam workload-identity-pools providers create-oidc vault-provider \
    --project=my-project \
    --workload-identity-pool=ctlabs-vault-pool \
    --location=global \
    --issuer-uri="https://vdb1.ctlabs.internal:8200/v1/identity/oidc" \
    --attribute-mapping="google.subject=assertion.sub"
```

   If Vault isn't reachable from Google (see reachability note above), pass
   `--jwk-json-path=<path to Vault's JWKS>` instead of relying on
   `--issuer-uri` discovery. Fetch the JWKS from
   `https://vdb1.ctlabs.internal:8200/v1/identity/oidc/.well-known/keys`.
   Re-upload it whenever Vault's signing key rotates.

3. **Create (or reuse) a target service account** with the IAM roles your
   Terraform run actually needs - this SA lives purely in GCP, no key is ever
   generated for it:

```bash
gcloud iam service-accounts create terraform-runner \
    --project=my-project \
    --display-name="Terraform Runner (WIF)"
```

```bash
# example: grant it editor on the project - scope this down to whatever
# your Terraform modules actually touch (compute, gke, etc.)
gcloud projects add-iam-policy-binding my-project \
    --member="serviceAccount:terraform-runner@my-project.iam.gserviceaccount.com" \
    --role="roles/editor"
```

4. **Grant the WIF pool permission to impersonate that SA**, scoped to the
   specific `sub` value you looked up in Vault step 4 (never grant the whole
   pool - always scope to `.../subject/<value>` for a single identity). Note
   the scheme is singular **`principal://`**, not `principalSet://` -
   `principalSet://` is only for attribute-based *groups* of identities (or a
   `/*` wildcard for the whole pool); binding one specific `subject` value
   requires `principal://` or GCP rejects it with `INVALID_ARGUMENT: ... is
   of an unknown type`:

```bash
PROJECT_NUMBER=$(gcloud projects describe my-project --format='value(projectNumber)')

gcloud iam service-accounts add-iam-policy-binding \
    terraform-runner@my-project.iam.gserviceaccount.com \
    --project=my-project \
    --role=roles/iam.workloadIdentityUser \
    --member="principal://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/ctlabs-vault-pool/subject/3f2c1a9e-....-....-....-............"
```

5. **Note the provider's resource name** - this is the `audience` value used
   in the ctlabs Terraform editor:

```
//iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/ctlabs-vault-pool/providers/vault-provider
```

   (substitute the real `PROJECT_NUMBER` from step 4)

---

### CTLabs Configuration

In the Terraform editor's **GCP Authentication** section, set:

| Field                          | Value                                                              |
|--------------------------------|--------------------------------------------------------------------|
| Auth Method                    | `Workload Identity Federation (via Vault OIDC)`                    |
| Vault OIDC Role                | `gcp-wif` (the role created in step 2 of the Vault setup)          |
| WIF Provider Audience          | The provider resource name from GCP step 5                         |
| Impersonated Service Account   | `terraform-runner@my-project.iam.gserviceaccount.com`              |

This is stored in the lab YAML as:

```yaml
terraform:
  auth:
    method: wif
    vault_role: gcp-wif
    audience: "//iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/ctlabs-vault-pool/providers/vault-provider"
    service_account: terraform-runner@my-project.iam.gserviceaccount.com
```

The older `terraform.vault: {project, roleset}` shape is still read
(auto-treated as `method: vault`) for backward compatibility, but is rewritten
to `terraform.auth: {method: vault, ...}` on the next save from the editor.

---

### Cleanup

Both scripts accept `--cleanup` to tear down what they created. Neither is
all-or-nothing by default - they only remove the specific things that are
safe to assume aren't shared:

```bash
# Vault side: deletes the role, then the key
python3 vault_oidc_setup.py --cleanup --role-name gcp-wif --key-name gcp-wif-key
# add --reset-issuer to also clear identity/oidc/config issuer (global setting,
# left alone by default in case something else depends on it)

# GCP side: by default only removes the WIF impersonation binding for --subject
python3 gcp_wif_setup.py --cleanup --project my-project --subject <sub-claim>
# add --delete-provider / --delete-pool (30-day soft-delete) /
# --delete-service-account / --remove-sa-roles to go further
```

Both prompt for confirmation before deleting anything unless you pass `--yes`.

---

### Controlling the token's OAuth scope

By default the final impersonated token is scoped to just
`https://www.googleapis.com/auth/cloud-platform`. Add a `scopes` list to
widen or narrow it (e.g. to reach Google Workspace APIs):

```yaml
terraform:
  auth:
    method: wif
    vault_role: gcp-wif
    audience: "..."
    service_account: terraform-runner@my-project.iam.gserviceaccount.com
    scopes:
      - https://www.googleapis.com/auth/cloud-platform
      - https://www.googleapis.com/auth/spreadsheets
```

Also exposed as a "OAuth Scopes" field (one per line) in the Terraform
editor's WIF fields, and in `labs/terraform_profiles.yml` entries.

**Important caveat for Workspace APIs**: this only grants the impersonated
service account access to resources explicitly *shared with the SA's own
email address* (e.g. sharing a specific Sheet with it, same as sharing with
any other collaborator) - it is **not** domain-wide access to any user's
data. Full Domain-Wide Delegation (acting *as* a specific Workspace user) is
a separate, unrelated flow (a self-signed JWT with a `sub` claim naming the
user, authorized in the Workspace Admin console) that does not compose with
WIF this way.

Only the `scope` of the *final* token (hop 3, `generateAccessToken`) is
configurable this way - the intermediate STS-exchanged token (hop 2) always
requests plain `cloud-platform`, since that's all it needs to make the hop 3
call itself.

The active scope of a cached token is visible in the webgui's Vault Login
info panel ("Active GCP Tokens"), sourced from Google's own `tokeninfo`
introspection of the live token - not from what was merely requested, so it
reflects what the token can actually do.
