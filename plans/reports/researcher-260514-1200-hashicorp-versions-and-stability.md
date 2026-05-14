# HashiCorp Products Version Research Report
**Date:** 2026-05-14  
**Conducted by:** Technical Analyst  
**Scope:** Stability assessment of Nomad, Consul, Vault, Consul-template versions currently in plan

---

## Executive Summary

**Plan is outdated.** All four products have newer stable releases available as of May 2026. Plan uses 1.7.6, 1.18.1, 1.15.7, 0.35.0 respectively. Current stable versions are 2.0.1, 1.22.7, 2.0.0, and 0.42.0. However, **upgrading to latest is NOT recommended without careful planning** due to breaking changes and major version transitions. Recommend **staged upgrade path** via intermediate LTS versions where applicable.

---

## Current Versions by Product

### 1. **Nomad: 1.7.6 → 2.0.1** ⚠️ MAJOR VERSION GAP

| Metric | Plan Version | Current Latest | Status |
|--------|-------------|-----------------|--------|
| Version | 1.7.6 | 2.0.1 | 13+ months behind |
| Release Type | Standard GA | Standard GA | — |
| LTS Status | No | No | Skipped 1.10 (last LTS) |
| Support Status | Still supported (2yr window) | Active | Plan version approaching EOL |

**Breaking Changes:** Minimal between 1.7 and 2.0. Only change: licensing log/error output formatting (impacts scripts parsing errors). No API incompatibilities detected.

**Major Shift:** Nomad 2.0 moves from semantic versioning (X.Y.Z) to IBM's Version-Modification-Fix (V.M.F) model:
- **V** (April): Major version, starts new 2-year support lifecycle
- **M** (October): Feature releases, no new support lifecycle
- **F** (Monthly): Patch releases

**Adoption Risk:** LOW for code, MEDIUM for operations due to versioning model change. Requires updated release automation.

**Recommendation:** 
- **Short-term (next 30 days):** Stay on 1.7.6, stable and supported until mid-2025 cutoff
- **Medium-term (Q3 2026):** Upgrade to 1.11.5 (last 1.x stable), test in staging
- **Long-term (Q4 2026):** Upgrade to 2.0.1 after validating new release model in production

---

### 2. **Consul: 1.18.1 → 1.22.7** ✅ STABLE PATH (Avoid 1.22.4)

| Metric | Plan Version | Current Latest | Status |
|--------|-------------|-----------------|--------|
| Version | 1.18.1 | 1.22.7 | 4 minor versions behind |
| Release Type | Standard GA | Standard GA | — |
| LTS Status | LTS (Enterprise) | Standard GA | — |
| Support Status | Supported (2yr) | Active | Directly compatible |

**Breaking Changes:**
1. **Key Name Validation:** KV endpoint now validates key names (may reject previously-valid keys with special chars)
2. **Envoy Version:** Bundled Envoy upgraded from ~1.29 to 1.35.3; support for 1.31.10 removed (auto-managed, no action needed)
3. **Known Issue:** Consul 1.22.4 MUST be skipped; upgrade directly to 1.22.5+

**Upgrade Path:** 1.18.1 → 1.22.7 is a direct, safe jump. No intermediate versions required. Backward compatible.

**Adoption Risk:** LOW. No breaking API changes, only validation tightening.

**Recommendation:**
- **Immediate:** Upgrade to 1.22.7 (direct safe path from 1.18.1)
- **Avoid:** 1.22.4 entirely (known defect, corrective release issued)
- **Monitor:** 2.0.0-rc1 available but pre-release; wait for GA before considering

---

### 3. **Vault: 1.15.7 → 2.0.0** ⚠️ MAJOR VERSION WITH BREAKING CHANGES

| Metric | Plan Version | Current Latest | Status |
|--------|-------------|-----------------|--------|
| Version | 1.15.7 | 2.0.0 (GA 2026-04-14) | 2 months behind |
| Release Type | LTS (1.x model) | Prod (IBM model) | Lifecycle model changed |
| LTS Status | LTS (approx 2yr support) | IBM SC2 (2yr standard + 1yr extended) | — |
| Support Status | Standard support | Active | 1.15 LTS ends Q2 2027 |

**CRITICAL Breaking Changes:**

1. **API Authentication (BREAKING):** Three endpoints now authenticated by default:
   - `sys/generate-root`
   - `sys/replication/dr/secondary/generate-operation-token`
   - `sys/rekey`
   - Mitigation: Set `enable_unauthenticated_access = true` in HCL (backward compat mode)

2. **Azure Auth:** Azure config now takes precedence over `AZURE_*` env vars (inverse of 1.x)
   - Action: Audit all Azure auth deployments; env vars may no longer override config

3. **Docker SDK Migration:** Moved from deprecated `github.com/docker/docker` to `github.com/moby/moby`
   - Impact: Plugins using Docker integration must rebuild

4. **LDAP Static Roles (Enterprise):** Auto-migration from plugin queue to Vault Enterprise Rotation Manager
   - Requires manual review post-upgrade

5. **Managed Keys API Response Change (Enterprise):** Key usage values now strings instead of integers
   - Impact: Any tooling parsing `GET sys/managed-keys/:type/:name` responses

**Adoption Risk:** HIGH. Requires pre-upgrade testing and config changes.

**Recommendation:**
- **HOLD 1.15.7 until:** Full test plan completed (2-4 weeks)
- **Pre-upgrade checklist:**
  1. Audit rekey automation scripts
  2. Audit Azure auth config in all namespaces
  3. Test 2.0 in isolated staging cluster
  4. Update plugin code if using Docker integration
  5. Review and document LDAP static role migration
  6. Update any API response parsers for managed keys
- **Upgrade path:** 1.15.7 → 2.0.0 (direct, but requires above validation)
- **Fallback plan:** Keep 1.21.5 as alternate LTS if 2.0 migration blocked

---

### 4. **Consul-template: 0.35.0 → 0.42.0** ✅ SAFE UPGRADE

| Metric | Plan Version | Current Latest | Status |
|--------|-------------|-----------------|--------|
| Version | 0.35.0 | 0.42.0 | 7 patch versions behind |
| Release Type | Standard | Standard | — |
| Support Status | Still supported | Active | Plan version stable |

**Security Fixes (CRITICAL):**
- **CVE HCSEC-2026-12 (Published May 12, 2026):** Sandbox path bypass in file template helper via symlink attack
- Affected: consul-template ≤0.41.4
- Fix: Included in 0.42.0
- Impact: If templates use file helper with untrusted paths, **upgrade immediately**

**Other Improvements:**
- Go updated to 1.26.2
- nomadVar helper now returns map values instead of pointers (minor, backward-compatible)
- Improved error handling and backoff retry logic

**Adoption Risk:** LOW. No breaking changes. Security fix is backward-compatible.

**Recommendation:**
- **Urgent:** Upgrade to 0.42.0 (security fix for symlink vulnerability)
- Safe for immediate deployment

---

## Installation Method Verification

### APT Repository: `apt.releases.hashicorp.com` ✅ STILL RECOMMENDED (2026)

**Status:** Official, maintained, and current.

**Installation Steps:**

```bash
# 1. Install GPG key
wget -O- https://apt.releases.hashicorp.com/gpg | \
  sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

# 2. Add repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
  https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list

# 3. Update and install
sudo apt update
sudo apt install nomad consul vault consul-template
```

**Repository Features:**
- GPG-signed packages (security best practice)
- Supports Debian, Ubuntu, Fedora, CentOS, RHEL, AmazonLinux
- Test channel available for RC/beta releases
- Both OSS and Enterprise editions packaged

**Recommendation:** Continue using `apt.releases.hashicorp.com`. It is the official, signed, recommended method for 2026.

---

## Version Stability Trade-off Matrix

| Product | Plan Ver | Current Ver | Stability | Urgency | Effort | Risk |
|---------|----------|------------|-----------|---------|--------|------|
| **Nomad** | 1.7.6 | 2.0.1 | Stable ↔ New | Low | High | Medium |
| **Consul** | 1.18.1 | 1.22.7 | Stable ↔ Stable | Medium | Low | Low |
| **Vault** | 1.15.7 | 2.0.0 | Stable ↔ New | High | High | High |
| **Consul-template** | 0.35.0 | 0.42.0 | Stable ↔ Stable | HIGH (CVE) | Low | Low |

---

## Recommended Upgrade Sequence

### Phase 1 (Immediate - Week 1)
1. **Consul-template 0.35.0 → 0.42.0** (security fix, low risk)
2. **Consul 1.18.1 → 1.22.7** (safe, direct upgrade, no breaking changes)

### Phase 2 (Staged - Weeks 2-4)
1. Set up isolated staging Vault cluster
2. Test Vault 2.0.0 against plan's config
3. Document required config changes (auth endpoints, Azure auth, etc.)
4. Validate all plugins compile against new Docker SDK

### Phase 3 (Controlled - Month 2)
1. **Nomad 1.7.6 → 1.11.5** (intermediate stable before major version jump)
2. Test release automation against new V.M.F versioning model
3. Deploy to staging first

### Phase 4 (After Validation - Month 3)
1. **Vault 1.15.7 → 2.0.0** (only after Phase 2 validation complete)
2. **Nomad 1.11.5 → 2.0.1** (only after Phase 3 validation complete)

---

## Unresolved Questions

1. **Enterprise vs OSS:** Are you using Consul Enterprise LTS variants? If so, Consul 1.18.1 may have extended LTS support (verify license/contract).

2. **Nomad 1.10 LTS:** Was 1.10.x considered? It's the last LTS before 2.0. Current plan skipped it. Recommend checking if stability/support is valued over feature freshness.

3. **Vault Plugin Ecosystem:** Are custom plugins deployed? Verify Docker SDK compatibility before 2.0 upgrade. Do any parse `managed-keys` API responses?

4. **Azure Auth Scope:** How extensively does plan use Azure auth? Need to audit all Azure-backed services for env var precedence inversion.

5. **Vault Rekey Automation:** Is rekey automated via API? If so, plan must add token auth before 2.0 upgrade (can't use old unauthenticated mode).

6. **LDAP Static Roles:** Is Vault Enterprise used with LDAP static roles? If so, 2.0 migration to Rotation Manager requires testing.

---

## Sources

- [Nomad Releases](https://releases.hashicorp.com/nomad/)
- [Consul Releases](https://releases.hashicorp.com/consul/)
- [Vault Releases](https://releases.hashicorp.com/vault)
- [Consul-Template Releases](https://releases.hashicorp.com/consul-template/)
- [Nomad v2.0.x release notes](https://developer.hashicorp.com/nomad/docs/release-notes/v2-0-x)
- [Vault 2.0 Breaking Changes](https://patchwindow.serverdigital.net/brief/vault-2-0-released)
- [Consul LTS Support](https://developer.hashicorp.com/consul/docs/upgrade/lts)
- [HCSEC-2026-12: Consul-template Symlink CVE](https://discuss.hashicorp.com/t/hcsec-2026-12-consul-template-vulnerable-to-sandbox-path-bypass-in-file-helper-through-symlink-attack/77414)
- [HashiCorp Official Packaging Guide](https://www.hashicorp.com/en/official-packaging-guide)
- [IBM HashiCorp Support Lifecycle](https://www.ibm.com/support/pages/ibm-hashicorp-self-managed-product-support-lifecycle-addendum)
