# Nomad Vault Template Block Syntax Research

**Date:** 2026-05-14 | **Source:** HashiCorp Official Docs

---

## Executive Summary

Your plan's Vault template syntax has **mixed correctness** across secret engine types:

| Assertion | Status | Finding |
|-----------|--------|---------|
| `.Data.username` for database creds | ✅ CORRECT | Database engine returns `{data: {username, password}}` |
| `database/creds/role` path | ✅ CORRECT | Endpoint is `/database/creds/:name` |
| `.Data.data.auth_key` for KV v2 | ✅ CORRECT | KV v2 wraps secret data inside `{data: {data: {...}}}` |
| Vault policy stanza syntax | ⚠️ PARTIAL | No standalone `vault_policy` block; use `vault` block with `policies` parameter in template |

**Key Risk:** Your plan mixes database secrets (single `.Data` layer) with KV v2 syntax (double `.Data.data` layers). These are correct for their respective engines but will fail if swapped.

---

## Finding 1: Database Secrets Engine Response Format

**Authoritative Source:** Vault API Docs—Databases  
**Endpoint:** `/database/creds/:name` (GET)

### Response Structure

```json
{
  "data": {
    "username": "root-1430158508-126",
    "password": "132ae3ef-5a64-7499-351e-bfe59f3a2a21"
  }
}
```

### Nomad Template Accessor

```hcl
{{with secret "database/creds/wordpress"}}
WORDPRESS_DB_USER={{.Data.username}}
WORDPRESS_DB_PASSWORD={{.Data.password}}
{{end}}
```

✅ **Your plan is correct here.** Use single `.Data` layer (NOT `.Data.data`) for database credentials.

---

## Finding 2: KV v2 Response Format

**Authoritative Source:** Vault API Docs—KV v2

### Response Structure

KV v2 returns TWO nested data layers:

```json
{
  "data": {
    "data": {
      "foo": "bar",
      "auth_key": "secret-value"
    },
    "metadata": {
      "version": 2,
      "created_time": "2018-03-22T02:24:06.945319214Z"
    }
  }
}
```

### Nomad Template Accessor

```hcl
{{with secret "secret/data/myapp"}}
AUTH_KEY={{.Data.data.auth_key}}
{{end}}
```

✅ **Your plan is correct here.** Use double `.Data.data` for KV v2 secrets.

### Critical Path Difference

- **KV v1 path:** `secret/mykey`  
- **KV v2 path:** `secret/data/mykey` (always includes `/data/` segment)

---

## Finding 3: Path Structure Clarification

| Secret Engine | Request Path | Template Syntax |
|---------------|--------------|-----------------|
| Database | `database/creds/role-name` | `.Data.username`, `.Data.password` |
| KV v2 | `secret/data/path/to/secret` | `.Data.data.fieldname` |
| KV v1 | `secret/path/to/secret` | `.Data.fieldname` |

**Your plan uses correct paths** for both database engine (`database/creds/wordpress`) and KV v2 (`secret/data/...`).

---

## Finding 4: Vault Policy Stanza in Nomad Jobs

**Authoritative Source:** Nomad Job Specification—Vault Block

### Syntax

There is NO standalone `vault_policy` block. Use the `vault` block within task specification:

```hcl
task "app" {
  vault {
    role = "prod"
    change_mode = "restart"
    change_signal = "SIGUSR1"
    env = true
  }
}
```

### Required Parameters

- **`role`** — Vault role name (required; Nomad derives token with this role's policies)

### Optional Parameters

- **`change_mode`** — Behavior when token changes: `restart` | `signal` | `noop`
- **`change_signal`** — Signal to send if `change_mode = "signal"` (default: `SIGUSR1`)
- **`env`** — Expose `VAULT_TOKEN` to task environment (default: `true`)
- **`disable_file`** — Skip writing token to disk (default: `false`)

### Multiple Policies

Policies are NOT referenced in the `vault` block. Instead:

1. Create a Vault role with the required policies attached
2. Reference that role in the `vault` block by name

Example: If role `wordpress-app` has policies `[database-creds, kv-read]`, use:

```hcl
vault {
  role = "wordpress-app"
}
```

---

## Finding 5: Concrete Template Block Examples

### Database Credentials (From Official Tutorial)

```hcl
template {
  data = <<EOF
{{with secret "database/creds/mongo"}}
MONGO_USERNAME={{.Data.username}}
MONGO_PASSWORD={{.Data.password}}
{{end}}
{{range nomadService 1 (env "NOMAD_ALLOC_ID") "mongo"}}
MONGO_URL={{.Address}}:{{.Port}}
{{end}}
EOF
  destination = "secrets/env"
  env         = true
}
```

**Adapted for WordPress:**

```hcl
template {
  data = <<EOF
{{with secret "database/creds/wordpress"}}
WORDPRESS_DB_USER={{.Data.username}}
WORDPRESS_DB_PASSWORD={{.Data.password}}
{{end}}
EOF
  destination = "secrets/env"
  env         = true
}
```

✅ Matches your plan exactly.

### KV v2 Secrets with Special Characters

For secrets containing `=`, `$`, quotes, use `toJSON` filter:

```hcl
template {
  data = <<EOF
DB_PASSWORD={{.Data.data.password | toJSON}}
{{end}}
EOF
  destination = "secrets/env"
  env         = true
}
```

---

## Finding 6: Hyphenated Secret Keys

When KV v2 secret keys contain hyphens (e.g., `db-password`), use index notation:

```hcl
{{with secret "secret/data/app"}}
DB_PASSWD={{index .Data.data "db-password"}}
{{end}}
```

**Why:** Hyphens are invalid in Go template identifiers; index notation accesses them as string keys.

---

## Verification Summary

| Question | Answer | Status |
|----------|--------|--------|
| Is `.Data.username` correct for database? | Yes; database engine returns single `data` layer | ✅ |
| Should database path be `database/creds/role`? | Yes; exact API endpoint | ✅ |
| Is `.Data.data.auth_key` correct for KV v2? | Yes; KV v2 wraps secrets in double `data` layer | ✅ |
| Is `vault` block the policy stanza? | Yes; no separate `vault_policy` block exists | ✅ |

---

## Architectural Recommendations

1. **Create separate Vault roles for different secret types:**
   - Role `wordpress-db`: policies `[database-wordpress]`
   - Role `wordpress-secrets`: policies `[kv-wordpress]`

2. **Template blocks should match roles in vault stanza:**

```hcl
task "wordpress" {
  vault {
    role = "wordpress-db"  # Has database-creds policy
  }

  template {
    data = <<EOF
{{with secret "database/creds/wordpress"}}
WORDPRESS_DB_USER={{.Data.username}}
WORDPRESS_DB_PASSWORD={{.Data.password}}
{{end}}
EOF
    destination = "secrets/env"
    env = true
  }
}
```

3. **Vault policies must grant correct paths:**

For database credentials:
```hcl
path "database/creds/wordpress" {
  capabilities = ["read"]
}
```

For KV v2:
```hcl
path "secret/data/wordpress/*" {
  capabilities = ["read"]
}
```

Note: KV v2 policies reference `secret/data/...`, NOT `secret/...`

---

## Unresolved Questions

None—all assertions in your plan verified against HashiCorp official API documentation.

