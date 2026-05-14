# Plan Verification Report

**Date:** 2026-05-14  
**Plan:** `plans/260513-1617-aws-nomad-infra`  
**Status:** Verified & Updated

---

## Verification Summary

| Area | Status | Action Taken |
|------|--------|--------------|
| HashiCorp Versions | Updated | Nomad 2.0.1, Consul 1.22.7, Vault 2.0.0, Consul-template 0.42.0 |
| Envoy (Consul Connect) | Added | Install in Packer AMI + CNI plugins |
| Vault KMS Auto-Unseal | Verified | `seal "awskms"` syntax correct |
| Nomad Vault Template | Verified | `.Data.username` and `.Data.data.x` correct per engine |
| Consul Intentions | Updated | Migrated from deprecated CLI to config entries |
| Drone Vault Integration | Updated | Extension architecture (drone-vault service) |

---

## Critical Issues Found & Fixed

### 1. Consul-template CVE (CRITICAL)
- **Issue:** Version 0.35.0 has security vulnerability (CVE HCSEC-2026-12)
- **Fix:** Updated to 0.42.0 in Phase 1

### 2. Missing Envoy Installation (CRITICAL)
- **Issue:** Consul Connect requires Envoy binary, not included in plan
- **Fix:** Added Envoy 1.29.2 + CNI plugins installation to Packer script

### 3. Outdated Drone Vault Config (HIGH)
- **Issue:** `DRONE_VAULT_ADDR` and `DRONE_VAULT_TOKEN` don't exist in modern Drone
- **Fix:** Added drone-vault extension job, updated runner with `DRONE_SECRET_PLUGIN_*` vars

### 4. Deprecated Consul Intentions CLI (MEDIUM)
- **Issue:** `consul intention create -allow` deprecated since Consul 1.9.0
- **Fix:** Replaced with `consul config write` using service-intentions config entries

---

## Verified Correct (No Changes Needed)

| Component | Verification |
|-----------|--------------|
| Vault KMS seal stanza | `seal "awskms"` is correct (not `seal "kms"`) |
| Database secrets template | `.Data.username` / `.Data.password` correct |
| KV v2 secrets template | `.Data.data.auth_key` correct (double data) |
| IAM permissions | `kms:Encrypt`, `kms:Decrypt`, `kms:DescribeKey` complete |
| Nomad Connect block | `sidecar_service {}` minimal config correct |

---

## Files Modified

| Phase | File | Changes |
|-------|------|---------|
| 1 | `phase-01-packer-ami-build.md` | Updated versions, added Envoy + CNI |
| 5 | `phase-05-hashicorp-configuration.md` | Config entries for intentions |
| 7 | `phase-07-ci-cd-pipeline.md` | Added drone-vault job, updated runner |
| - | `plan.md` | Added verified date, version table |

---

## Breaking Changes to Note (Vault 2.0.0)

When implementing, be aware of Vault 2.0 breaking changes:
1. Three API endpoints now require authentication by default
2. Azure auth precedence reversed (env vars no longer override config)
3. If using Enterprise: LDAP static roles, managed keys API require migration

---

## Resolved Questions

| Question | Answer |
|----------|--------|
| Docker Hub credentials | Use existing: `asdads6495` |
| GitHub OAuth app | Personal account: `betterguy2004` |
| Backup strategy | Basic: RDS 7 days auto, S3 versioning enabled |

## Remaining Question

- **Envoy version alignment**: Consul 1.22.7 tested with Envoy 1.29.x? (verify during implementation)

---

## Sources

- [HashiCorp Vault AWS KMS Seal](https://developer.hashicorp.com/vault/docs/configuration/seal/awskms)
- [Nomad Vault Integration](https://developer.hashicorp.com/nomad/docs/integrations/vault)
- [Consul Service Intentions](https://developer.hashicorp.com/consul/docs/connect/config-entries/service-intentions)
- [Drone Vault Extension](https://docs.drone.io/runner/extensions/vault/)
- [Consul Connect Envoy](https://developer.hashicorp.com/consul/docs/connect/proxies/envoy)
