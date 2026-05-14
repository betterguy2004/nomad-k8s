# Drone CI Vault Integration Research Report

**Date:** 2026-05-14  
**Focus:** Verify Drone's Vault secret management—native support status, YAML syntax, server environment variables, deprecation status

---

## Executive Summary

**Status:** Drone's Vault integration is ACTIVE and SUPPORTED via a dedicated extension plugin (drone-vault). The plan's configuration uses outdated environment variable naming conventions. The `DRONE_VAULT_ADDR` and `DRONE_VAULT_TOKEN` syntax in the plan is **NOT correct** for current Drone versions.

**Recommendation:** Replace with runner-side extension configuration using:
- `DRONE_SECRET_PLUGIN_ENDPOINT` (runner config)
- `DRONE_SECRET_PLUGIN_TOKEN` (runner config)
- Standard `VAULT_ADDR` and `VAULT_TOKEN` (plugin container env)

---

## Question 1: Is Drone's native Vault integration still supported?

**Answer:** YES, but NOT as a built-in feature. Support is provided via the **drone-vault extension plugin** (separate, officially maintained container service).

**Architecture:**
- drone-vault runs as an **independent Docker container** on port 3000
- Registers as a **secret extension** with Drone runners (not server)
- Requires Drone server **v1.3 or higher**
- NOT available on Drone Cloud (self-hosted only)

**Credibility:** [Official Drone documentation](https://docs.drone.io/runner/extensions/vault/) + [GitHub drone-vault repo](https://github.com/drone/drone-vault) (maintained by Drone project)

---

## Question 2: Correct YAML syntax for Vault secrets in .drone.yml

**Answer:** Use the `kind: secret` resource format (modern syntax):

```yaml
---
kind: secret
name: dockerhub_username
get:
  path: secret/data/drone
  name: dockerhub_username
---
kind: secret
name: dockerhub_password
get:
  path: secret/data/drone
  name: dockerhub_password
```

Then reference in pipeline steps:

```yaml
kind: pipeline
name: default

steps:
  - name: publish
    image: plugins/docker
    settings:
      username:
        from_secret: dockerhub_username
      password:
        from_secret: dockerhub_password
```

**Path Structure Notes:**
- `path`: Full Vault KV path to the secret (e.g., `secret/data/drone`, `kv/data/secret/drone/docker/login`)
- `name`: Specific field within that Vault secret to extract
- **NOT** the old flat syntax (`secrets: docker_username: path: secret/docker_username`)

**Credibility:** [Drone official docs](https://docs.drone.io/secret/external/vault/) + [Community guide (Medium)](https://cogarius.medium.com/2-3-complete-guide-to-ci-cd-pipelines-with-drone-io-on-kubernetes-drone-vault-extension-a9914228ad15)

---

## Question 3: Required Drone server environment variables for Vault

**Answer:** Vault configuration is RUNNER-SIDE, not server-side. No `DRONE_VAULT_*` variables needed on the server.

**Runner Configuration (where drone-runner is deployed):**

```bash
DRONE_SECRET_PLUGIN_ENDPOINT=http://vault-extension.service.consul:3000
DRONE_SECRET_PLUGIN_TOKEN=bea26a2221fd8090ea38720fc445eca6
```

**Vault Extension Container Configuration:**

```bash
docker run -d \
  --env=DRONE_SECRET=bea26a2221fd8090ea38720fc445eca6 \
  --env=VAULT_ADDR=http://active.vault.service.consul:8200 \
  --env=VAULT_TOKEN=${VAULT_TOKEN} \
  --env=VAULT_AUTH_TYPE=token \
  --publish=3000:3000 \
  drone/vault-secrets:latest
```

**Key Points:**
- `DRONE_SECRET`: Shared secret (generated via `openssl rand -hex 16`)—must match between extension and runner
- `VAULT_ADDR`: Vault server address
- `VAULT_TOKEN`: Vault authentication token (or use AppRole auth)
- `DRONE_SECRET_PLUGIN_ENDPOINT`: Runner points to extension service
- `DRONE_SECRET_PLUGIN_TOKEN`: Runner uses shared secret to authenticate with extension

**Credibility:** [Drone runner extensions docs](https://docs.drone.io/runner/extensions/vault/) + [GitHub drone-vault](https://github.com/drone/drone-vault)

---

## Question 4: Does Drone need `DRONE_VAULT_SECRET` or `DRONE_VAULT_TOKEN`?

**Answer:** NO to both. Neither `DRONE_VAULT_SECRET` nor `DRONE_VAULT_TOKEN` are valid Drone variables.

**Deprecated/Incorrect Variables:**
- `DRONE_VAULT_ADDR` ✗ (does NOT exist in current Drone)
- `DRONE_VAULT_TOKEN` ✗ (does NOT exist in current Drone)
- `DRONE_VAULT_SECRET` ✗ (not a valid Drone variable)

**Plan's Current Syntax is Incorrect:**
```yaml
DRONE_VAULT_ADDR=http://active.vault.service.consul:8200
DRONE_VAULT_TOKEN=${VAULT_TOKEN}
```

This appears to be from an older Drone version (pre-1.3) or legacy documentation. Current versions use the extension architecture (runner-side only).

**Credibility:** Search of Drone 0.8.0+ docs, GitHub plugin repo, and current official documentation show NO references to `DRONE_VAULT_*` prefixed variables.

---

## Trade-Off Analysis

| Aspect | Status |
|--------|--------|
| **Native support** | Extension-based (plugin architecture, not built-in) |
| **Maturity** | Stable; Drone v1.3+ required |
| **Maintenance** | Actively maintained by Drone project |
| **Complexity** | Moderate—requires separate service deployment |
| **YAML syntax** | `kind: secret` + `get: {path, name}` (modern, clean) |
| **Deprecation risk** | LOW—no plans to remove extension architecture |
| **Multi-backend** | Vault only (no AWS Secrets Manager, etc.) |

---

## Architectural Fit for Plan

**Current Plan Problems:**
1. Server-side Vault config (`DRONE_VAULT_*`) is outdated—plan assumes pre-v1.3 architecture
2. No mention of runner-side extension configuration
3. No explicit `kind: secret` syntax in plan

**Recommended Changes:**
1. Deploy drone-vault extension as separate service in cluster
2. Configure runner with `DRONE_SECRET_PLUGIN_ENDPOINT` and `DRONE_SECRET_PLUGIN_TOKEN`
3. Update .drone.yml to use `kind: secret` with `get:` section
4. Remove server-side `DRONE_VAULT_*` variables from plan

**Integration Points:**
- Extension can run in same K8s namespace as Drone runner
- Service discovery via DNS (e.g., `vault-secrets.default.svc.cluster.local`)
- Shared secret passed securely via runner environment or ConfigMap

---

## Adoption Risk Assessment

| Risk | Level | Mitigation |
|------|-------|-----------|
| Drift from old docs | MEDIUM | Current official docs are clear; plan needs update |
| Service availability | LOW | Extension failure = graceful pipeline pause, not crash |
| Token refresh | LOW | Plugin handles TTL + auto-renewal (AppRole mode) |
| Version compatibility | LOW | Drone v1.3+ maintained for 5+ years |
| Consul DNS dependency | MEDIUM | Requires working DNS resolution to Vault service |

---

## Source Credibility Assessment

| Source | Credibility | Recency |
|--------|------------|---------|
| docs.drone.io (official) | ★★★★★ | Current (2025) |
| GitHub drone/drone-vault | ★★★★★ | Maintained; last update 2024-2025 |
| Medium guide (Cogarius) | ★★★★☆ | Practical examples; dated to ~2021 but still accurate |
| 0-8-0.docs.drone.io | ★★★☆☆ | Historical; v0.8.0 from ~2016 |

---

## Unresolved Questions

1. **AppRole vs Token Auth:** Plan uses bearer tokens. Should consider AppRole for automated token renewal in production?
2. **Secret Access Control:** Plan doesn't show `x-drone-*` Vault metadata keys for access restrictions. Should these be added?
3. **Consul DNS Reliability:** Is Consul DNS guaranteed available in nomad-k8s cluster, or should IP addresses be used instead?
4. **Extension Redundancy:** Should multiple drone-vault replicas run behind a load balancer, or is single instance sufficient?

---

## Recommendation: Configuration Fix Priority

**CRITICAL (immediate):**
- Replace `DRONE_VAULT_ADDR` and `DRONE_VAULT_TOKEN` environment variables in plan
- Add `DRONE_SECRET_PLUGIN_ENDPOINT` and `DRONE_SECRET_PLUGIN_TOKEN` to runner config
- Deploy drone-vault as separate Kubernetes service

**HIGH (before pipeline use):**
- Update .drone.yml to use `kind: secret` with `get:` syntax
- Add `x-drone-repos` and `x-drone-events` metadata to restrict secret access per repo

**MEDIUM (operational):**
- Document secret path conventions in team docs
- Set up secret rotation policy for `DRONE_SECRET` shared secret
- Monitor drone-vault container logs for auth failures

---

## References

- [Drone Runner Extensions: Vault](https://docs.drone.io/runner/extensions/vault/)
- [Drone Secret Management](https://docs.drone.io/secret/external/vault/)
- [GitHub: drone/drone-vault](https://github.com/drone/drone-vault)
- [Cogarius: Drone Vault Extension Guide (Medium)](https://cogarius.medium.com/2-3-complete-guide-to-ci-cd-pipelines-with-drone-io-on-kubernetes-drone-vault-extension-a9914228ad15)
- [Drone 0.8.0: Vault Integration (Historical)](https://0-8-0.docs.drone.io/setup-vault-integration/)

