# HashiCorp Vault Policy Documentation

Vault policies are the primary mechanism for authorizing users and applications. They use a Path-Based model to grant or deny access to specific endpoints within the Vault API.

## 1. Policy Capabilities (Permissions)

Every path defined in a policy must be associated with one or more of the following capabilities. These define the "what" that a user is allowed to do at a specific "where."

| Capability | Description                                                                         |
|------------|-------------------------------------------------------------------------------------|
| `create`   | Allows creating data at the given path.                                             |
| `read`     | Allows reading data from the given path.                                            |
| `update`   | Allows changing data at the given path.                                             |
| `patch`    | Allows partial updates to data at the given path (supported by some engines).       |
| `delete`   | Allows deleting the data at the given path.                                         |
| `list`     | Allows listing the keys at the given path (requires the path to end with a `/`).    |
| `sudo`     | Allows access to paths that are otherwise restricted to root-only users.            |
| `deny`     | Explicitly disallows access. Always takes precedence over any other permission.     |

---

## 2. Global System Endpoints (`sys/`)

The `sys/` prefix is used for administrative tasks. Access to these typically requires `sudo` privileges for sensitive operations.

| Endpoint Path             | Purpose | Recommended Capabilities                                                                |
|---------------------------|-------------------------------------------------|-------------------------------------------------|
| `sys/auth`                | Manage authentication methods (enable/disable). | `create`, `read`, `update`, `delete`, `sudo`    |
| `sys/mounts`              | Manage secrets engine mounts.                   | `create`, `read`, `update`, `delete`, `sudo`    |
| `sys/policies/acl`        | Create, read, and manage ACL policies.          | `create`, `read`, `update`, `delete`, `list`    |
| `sys/health`              | Check the health status of the Vault cluster.   | `read`                                          |
| `sys/seal` / `sys/unseal` | Manual sealing and unsealing of the Vault.      | `write`, `sudo`                                 |
| `sys/capabilities-self`   | Allows a user to check their own permissions.   | `update`                                        |

---

## 3. Secret Engine Endpoints

Depending on the engine enabled, the endpoints vary. Below are the standard patterns for the engines used in the CTLABS environment.

### KV (Key-Value) Secret Engine (v2)
| Endpoint Path            | Purpose                                  | Required Capabilities       |
|--------------------------|------------------------------------------|-----------------------------|
| `secret/data/<path>`     | Read or Write the actual secret data.    | `read`, `create`, `update`  |
| `secret/metadata/<path>` | Manage versions, deletion, and metadata. | `read`, `list`, `delete`    |

### GCP Secret Engine (The Identity Broker)
| Endpoint Path         | Purpose                               | Required Capabilities      |
|-----------------------|---------------------------------------|----------------------------|
| `gcp/config`          | Global configuration (admin only).    | `sudo`, `read`, `update`   |
| `gcp/roleset/<name>`  | Create or manage roleset definitions. | `create`, `read`, `update` |
| `gcp/token/<roleset>` | **Generate a JIT Token for a user.**  | `read`                     |
| `gcp/key/<roleset>`   | Generate a JIT Service Account Key.   | `read`                     |

---

## 4. Auth Method Endpoints

These endpoints govern how users log in and how their identities are managed.

| Endpoint Path            | Purpose                                      | Required Capabilities              |
|--------------------------|----------------------------------------------|------------------------------------|
| `auth/ldap/login/<user>` | Login endpoint for LDAP users.               | `create` (Standard for login)      |
| `auth/token/lookup-self` | Allow a user to see their own token info.    | `read`                             |
| `auth/token/revoke-self` | Allow a user to log out (revoke token).      | `update`                           |
| `identity/group`         | Manage internal groups for mapping policies. | `create`, `read`, `update`, `list` |

---

## 5. Policy Syntax Examples

### Example: The Developer Policy
This policy allows a developer to log in, check their own capabilities, and generate a JIT token for GCP.

```hcl
# Allow looking up token properties
path "auth/token/lookup-self" {
  capabilities = ["read"]
}

# Allow checking own capabilities
path "sys/capabilities-self" {
  capabilities = ["update"]
}

# Allow acquiring a JIT token from a specific GCP roleset
path "gcp/token/dev-storage-roleset" {
  capabilities = ["read"]
}

# Explicitly deny access to admin config
path "gcp/config" {
  capabilities = ["deny"]
}
```

### Example: The Lab Admin Policy
This policy allows full management of the CTLABS environment.

```hcl
# Manage all secret engines
path "sys/mounts/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Full control over the GCP engine
path "gcp/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
```

---

## 6. Best Practices

1. **Principle of Least Privilege**: Never use `*` (wildcards) at the root level. Always scope paths as tightly as possible (e.g., `gcp/token/my-app` instead of `gcp/*`).
2. **List Capability**             : Remember that `list` requires the trailing slash. `path "gcp/roleset/" { capabilities = ["list"] }` is correct; omitting the `/` will often fail.
3. **Audit Readiness**             : Use descriptive policy names (e.g., `gcp-jit-storage-viewer`) to make audits of Identity Groups easier.

## 7. Architectural Best Practices: Mount-Level Isolation

While Vault policies provide fine-grained control, **separation of responsibility** should begin at the infrastructure level by utilizing multiple mount points.

* **Attack Surface Reduction**      : Using multiple mount points (e.g., `kv-app-finance/`, `kv-app-marketing/`) shrinks the attack surface. In a monolithic mount, a single policy misconfiguration—such as an accidental wildcard (`*`) or an overly permissive `list` capability—puts the entire secret inventory at risk. With segmented mounts, a configuration error is strictly contained within that specific engine's logical boundary.
* **Blast Radius Mitigation**       : Segregation ensures that an administrative error (e.g., accidentally disabling a secrets engine) or a compromised credential only impacts a subset of the organization's data. 
* **Environment & Team Segregation**: Distinct mounts for `dev/`, `stage/`, and `prod/` prevent lateral movement. A developer with elevated permissions in a development mount cannot exploit a policy flaw to access production secrets, as they reside on a completely different API path and physical storage prefix.
* **Delegated Administration**      : You can grant "Lead" roles `sudo` capabilities over specific mounts. This allows teams to manage their own secret lifecycles (tuning TTLs, max versions, etc.) without requiring global `sys/mounts` permissions, adhering to the Principle of Least Privilege.

> [!TIP]
> Always enable engines at specific, descriptive paths:
> `vault secrets enable -path=ctlabs-prod-storage kv-v2`
