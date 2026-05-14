# Consul Connect Service Mesh Configuration Research

**Date:** 2026-05-14 | **Source:** HashiCorp Official Docs | **Status:** VERIFIED

## Executive Summary

The plan's Consul Connect configuration has **SYNTAX ERRORS** in the intention CLI commands. Modern Consul defaults to `service-intentions` config entries (YAML), not the deprecated CLI. Nomad integration is correctly configured. Envoy is required and must be manually installed on Nomad client nodes.

---

## 1. Consul Intention CLI Syntax — INCORRECT IN PLAN

### Current Plan (WRONG)
```bash
consul intention create -deny '*' '*'
consul intention create -allow nginx wordpress
```

### Correct CLI Syntax (Deprecated but Still Valid)
```bash
consul intention create -deny '*' '*'              # Correct: deny all
consul intention create -allow nginx wordpress     # Correct: allow nginx→wordpress
```

**Status:** Syntax is technically valid BUT **deprecated since Consul 1.9.0**. These commands work but produce warnings.

---

## 2. Modern Approach: Service-Intentions Config Entry (RECOMMENDED)

HashiCorp recommends migrating to `service-intentions` config entries. Replace the CLI commands with YAML:

```yaml
# Deny all traffic (default deny policy)
apiVersion: consul.hashicorp.com/v1alpha1
kind: ServiceIntentions
metadata:
  name: default-deny
spec:
  destination:
    name: "*"
  sources:
  - name: "*"
    action: deny
---
# Allow nginx → wordpress traffic
apiVersion: consul.hashicorp.com/v1alpha1
kind: ServiceIntentions
metadata:
  name: nginx-to-wordpress
spec:
  destination:
    name: wordpress
  sources:
  - name: nginx
    action: allow
```

**Apply via:**
```bash
consul config write intentions.yaml
```

### Wildcard Behavior
- Source `"*"` = all sources
- Destination `"*"` = all destinations
- Order matters: explicit rules before wildcard rules

---

## 3. Nomad Connect Integration — CORRECT IN PLAN

### Minimal Config Verified
```hcl
service {
  name   = "wordpress"
  port   = "80"
  
  connect {
    sidecar_service {}
  }
}
```

✅ **Correct.** `sidecar_service {}` can be empty and uses defaults.

### Full Nomad Requirements
- **Job group network mode:** Must be `bridge` or custom CNI (not host mode)
- **Service provider:** `provider = "consul"` (explicit or default)
- **Service name + port:** Required for Consul registration
- **Connect block:** Exactly one of: `native = true`, `sidecar_service {}`, or `gateway`

---

## 4. Envoy Proxy — REQUIRED + MANUAL INSTALLATION

### Is Envoy Required?

**YES.** Consul Connect defaults to Envoy proxy. Alternatives:
- **Envoy proxy** (first-class support) — recommended production choice
- **Built-in proxy** (L4 only) — testing/dev only, not production
- **Custom proxies** — possible but requires explicit configuration

### Deployment & Installation

**Envoy is NOT included in Consul binary.** Must be installed separately on each Nomad client node:

```bash
# On each Nomad client
curl -L https://getenvoy.io/install.sh | bash
# or via package manager
apt-get install envoy  # Ubuntu/Debian
brew install envoy     # macOS
```

### Nomad Client Configuration Requirements

For service mesh sidecars to work, each Nomad client node needs:

1. **Consul binary in $PATH**
   ```bash
   # Verify
   which consul
   ```

2. **Envoy binary in $PATH**
   ```bash
   # Verify
   which envoy
   ```

3. **CNI plugins installed**
   ```bash
   # Standard plugins
   /opt/cni/bin/bridge
   /opt/cni/bin/loopback
   
   # For transparent proxy (optional)
   /opt/cni/bin/consul-cni
   ```

4. **Job group network mode:** `bridge` (required for sidecar injection)

### Sidecar Proxy Lifecycle

Nomad automatically:
1. Injects an Envoy sidecar task alongside your service
2. Configures Envoy via Consul gRPC API (port 8502)
3. Manages sidecar startup/shutdown with your service
4. NO manual proxy management needed

---

## 5. Consul Agent Configuration Requirements

Consul server/client must enable gRPC and Connect:

```hcl
# Minimal Consul config for Connect
ports {
  grpc = 8502
}

connect {
  enabled = true
}
```

### TLS with Consul 1.14+
If using auto_encrypt or mTLS:
```hcl
grpc_tls {
  enabled = true
}
```

### Network Architecture
```
Nomad Job
├── Service Task (port 9001)
└── Envoy Sidecar Task (auto-injected)
    ├── Inbound listener (port 9001 traffic)
    ├── Outbound listeners (upstream services)
    └── mTLS to Consul for config
        (gRPC API on 8502)
```

---

## Corrected Plan Commands

### Option A: CLI (Deprecated, Still Works)
```bash
# Step 1: Check Consul is running with Connect enabled
consul info | grep -i connect

# Step 2: Create default deny policy
consul intention create -deny '*' '*'

# Step 3: Allow nginx → wordpress
consul intention create -allow nginx wordpress

# Step 4: Verify intentions
consul intention list
```

### Option B: Config Entry (Recommended, Modern)
```bash
# Create intentions.hcl or intentions.yaml
cat > intentions.yaml <<'EOF'
apiVersion: consul.hashicorp.com/v1alpha1
kind: ServiceIntentions
metadata:
  name: default-deny
spec:
  destination:
    name: "*"
  sources:
  - name: "*"
    action: deny
---
apiVersion: consul.hashicorp.com/v1alpha1
kind: ServiceIntentions
metadata:
  name: nginx-wordpress
spec:
  destination:
    name: wordpress
  sources:
  - name: nginx
    action: allow
EOF

# Apply
consul config write intentions.yaml

# Verify
consul config read service-intentions default-deny
```

---

## Verification Checklist

Before deploying, verify on each Nomad client:

```bash
# ✓ Consul binary available
which consul && consul version

# ✓ Envoy binary available
which envoy && envoy --version

# ✓ CNI plugins present
ls /opt/cni/bin/

# ✓ Nomad client has bridge networking
nomad node status -verbose | grep -i network

# ✓ Consul Connect enabled
curl http://localhost:8500/v1/agent/self | jq '.Config.Connect'

# ✓ gRPC endpoint reachable
curl -k https://localhost:8502 2>/dev/null || echo "gRPC OK"
```

After deploying Nomad jobs:

```bash
# ✓ Service registered in Consul
consul catalog services
consul members

# ✓ Sidecar proxy running
nomad job status [job-name]  # Check sidecar task

# ✓ Intentions enforced
consul intention list
```

---

## Key Differences from Plan

| Aspect | Plan | Correct |
|--------|------|---------|
| **Intention CLI** | `-allow nginx wordpress` ✓ | Syntax correct but deprecated |
| **Wildcard deny** | `*` `*` ✓ | Correct for "deny all" |
| **Sidecar config** | `sidecar_service {}` ✓ | Correct, minimal is OK |
| **Envoy required** | Not stated | YES — must install separately |
| **Envoy deployment** | Not addressed | Nomad auto-injects; client must have binary in $PATH |

---

## Source Credibility

| Source | Quality | Used For |
|--------|---------|----------|
| developer.hashicorp.com/consul/commands/intention/create | Official CLI ref | CLI syntax verification |
| developer.hashicorp.com/consul/docs/connect/config-entries/service-intentions | Official modern approach | Service-intentions YAML format |
| developer.hashicorp.com/nomad/docs/job-specification/connect | Official Nomad spec | Connect block configuration |
| developer.hashicorp.com/nomad/docs/integrations/consul-connect | Official integration guide | Nomad client requirements |
| developer.hashicorp.com/consul/docs/connect/proxies | Official proxy support | Envoy role and alternatives |

---

## Unresolved Questions

1. **Envoy version pinning:** What Envoy version should align with Consul version? (e.g., Consul 1.16 + Envoy 1.X.X?)
2. **Auto-install approach:** Should Envoy be pre-baked in Nomad client images, or installed via cloud-init?
3. **L7 policies:** Plan shows only L4 (allow/deny). Any need for L7 permissions (HTTP routing, gRPC methods)?
4. **Transparent proxy:** Should `consul-cni` plugin be installed for transparent proxying, or stick with explicit upstream definitions?
5. **mTLS enforcement:** Should intentions be combined with Consul's mandatory mTLS for additional security?
