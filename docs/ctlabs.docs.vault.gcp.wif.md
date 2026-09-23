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

---

### One-time Vault Setup

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

3. **Define a role.** The `aud` (audience) claim on the issued token must
   match what you configure as the "Allowed audiences" on the GCP provider
   side (or GCP's default expected audience pattern, if you leave it out):

```bash
vault write identity/oidc/role/gcp-wif \
    key=gcp-wif-key \
    ttl=10m
```

4. **Look up the `sub` claim** you'll bind IAM permissions to. Vault sets
   `sub` to the calling identity's **entity ID** (a stable UUID, not the
   username) - decode a test token to see it before writing the IAM binding
   in the GCP setup below:

```bash
TOKEN=$(vault read -field=token identity/oidc/token/gcp-wif)
echo "$TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | python3 -m json.tool
# {
#   "iss": "https://vdb1.ctlabs.internal:8200",
#   "sub": "3f2c1a9e-....-....-....-............",   <- this is the value GCP will see
#   "aud": "...",
#   ...
# }
```

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
   The `--issuer-uri` must be **exactly** the string you pinned in
   `identity/oidc/config issuer=...` on the Vault side (step 1 above) - not a
   sub-path of it:

```bash
gcloud iam workload-identity-pools providers create-oidc vault-provider \
    --project=my-project \
    --workload-identity-pool=ctlabs-vault-pool \
    --location=global \
    --issuer-uri="https://vdb1.ctlabs.internal:8200" \
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
   pool - always scope to `.../subject/<value>` for a single identity):

```bash
PROJECT_NUMBER=$(gcloud projects describe my-project --format='value(projectNumber)')

gcloud iam service-accounts add-iam-policy-binding \
    terraform-runner@my-project.iam.gserviceaccount.com \
    --project=my-project \
    --role=roles/iam.workloadIdentityUser \
    --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/ctlabs-vault-pool/subject/3f2c1a9e-....-....-....-............"
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
to `terraform.auth: {method: vault, ...}` on the next save from the editor
