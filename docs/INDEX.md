# Documentation Index

Complete guide to the nomad-k8s infrastructure project documentation.

## Quick Navigation

### For First-Time Users
1. **Start here**: [README.md](../README.md) — Project overview, quick start, prerequisites (5 min read)
2. **Then deploy**: [Deployment Guide](./deployment-guide.md) — Step-by-step instructions (30-40 min to execute)
3. **Reference**: [System Architecture](./system-architecture.md) — Understand the design

### For Infrastructure Deep-Dives
- [System Architecture](./system-architecture.md) — Complete technical design, 5 infrastructure layers, HA strategy
- [Consul Role Overview](./consul-role-overview.md) — Service discovery, Connect mesh, mTLS encryption
- [Secrets Management Flow](./secrets-management-flow.md) — Vault integration, dynamic credentials, policies

### For Developers & Contributors
- [Code Standards](./code-standards.md) — Terraform, HCL, Bash conventions, best practices
- [Codebase Summary](./codebase-summary.md) — Directory structure, file organization, metrics

### For Maintainers
- [Documentation Status](./DOCUMENTATION-STATUS.md) — Audit report, coverage assessment, maintenance schedule

---

## Documentation Files

### Root Level

#### [README.md](../README.md) — Entry Point
**Length**: 209 LOC  
**Purpose**: Project overview, directory structure, prerequisites, deployment order, verification checklist  
**Best for**: Understanding what the project does, verifying you have tools installed, seeing deployment sequence

**Key Sections**:
- Quick Links to specialized docs
- Directory structure with explanations
- Prerequisites checklist
- 7-step deployment order
- Quick reference commands
- Security summary
- Environment variables

---

### Documentation Directory (`/docs`)

#### [System Architecture](./system-architecture.md) — Technical Design
**Length**: 476 LOC  
**Purpose**: Complete infrastructure design, all layers, data flows, disaster recovery  
**Best for**: Understanding how everything works, architecture decisions, HA/scaling strategies

**Key Sections**:
- High-level infrastructure diagram
- 5 infrastructure layers (network, cluster, Packer, data, CDN)
- Nomad jobs (WordPress, Laravel, Nginx, Drone)
- Service discovery & mesh (Consul Connect)
- Secrets management architecture (Vault)
- Deployment flow diagrams
- Disaster recovery strategy
- File reference index

**Diagrams**: ASCII architecture, data flow sequences

---

#### [Deployment Guide](./deployment-guide.md) — Step-by-Step
**Length**: 639 LOC  
**Purpose**: Hands-on instructions from scratch, with verification at each step  
**Best for**: Actually deploying the infrastructure, troubleshooting issues

**Key Sections**:
- Pre-deployment checklist (11 items)
- Environment setup (.env template)
- 8 sequential deployment steps with sub-steps
- Verification commands after each step
- Troubleshooting section (6 common issues with diagnostics)
- Cleanup instructions
- Quick reference command list

**Commands**: Actual terraform, packer, nomad commands with explanations

---

#### [Consul Role Overview](./consul-role-overview.md) — Service Discovery
**Length**: 556 LOC  
**Purpose**: Deep-dive into Consul architecture, service discovery, Connect mesh, mTLS  
**Best for**: Understanding service-to-service communication, health checking, access control

**Key Sections**:
1. Service Discovery
   - Registration flow (Nomad → Consul)
   - Discovery flow (Nginx → Consul Template → upstream blocks)
   - Service lifecycle
2. Cluster Formation & Backend
   - Auto-join via AWS tags
   - Vault storage backend in Consul
3. Service Mesh (Consul Connect)
   - mTLS encryption with Envoy sidecars
   - Intentions (access control rules)
   - Nomad job configuration with Connect
4. Health Checking (TCP, HTTP)
5. Ports & Security Groups
6. Summary table
7. Troubleshooting commands

**Diagrams**: Registration flow, discovery flow, mTLS architecture, intentions, health checks

---

#### [Secrets Management Flow](./secrets-management-flow.md) — Vault Integration
**Length**: 447 LOC  
**Purpose**: Complete secrets architecture, dynamic credentials, rotation, policies  
**Best for**: Understanding how secrets work, dynamic database credentials, credential rotation

**Key Sections**:
1. Vault Auto-Unseal (AWS KMS)
2. Dynamic Database Credentials
   - Vault database engine config
   - Nomad template blocks
   - Credential lifecycle with TTL
3. Static Secrets (KV v2)
   - Path structure for static values
   - Nomad template syntax
4. Vault Policies (Access Control)
   - Per-application policies
   - Nomad-Vault integration
5. Drone CI/CD Secrets Flow
6. Security Boundaries (3 layers: network, application, infrastructure)
7. Secrets inventory table
8. Troubleshooting commands

**Diagrams**: Auto-unseal flow, database credential flow, lifecycle diagram, policy architecture, security boundaries

---

#### [Code Standards](./code-standards.md) — Development Patterns
**Length**: 809 LOC  
**Purpose**: Naming conventions, best practices, patterns for future work  
**Best for**: Contributing code, understanding existing patterns, adding features

**Key Sections**:
1. **Terraform & Terragrunt**
   - File organization (environments vs. stacks)
   - Naming conventions (snake_case)
   - Best practices (remote state, providers, count vs. for_each, conditionals, locals, data sources, lifecycle rules)
   - Terragrunt patterns (dependencies, input inheritance)

2. **HCL Configuration Files**
   - Nomad job structure with example
   - Consul configuration
   - Vault configuration
   - Nomad configuration

3. **Packer**
   - Pattern and benefits

4. **Docker Images**
   - Naming convention, template, push instructions

5. **Bash Scripts**
   - Naming convention, template, best practices

6. **Git Workflow**
   - Branch naming, commit messages (Conventional Commits), .gitignore

7. **Documentation**
   - Naming, structure, code examples

8. **Summary Table**: Key principles (DRY, single responsibility, naming, IaC-first, secrets, observability, testability, documentation)

**Code Examples**: Complete templates for Terraform resources, Nomad jobs, Vault configs, Bash scripts

---

#### [Codebase Summary](./codebase-summary.md) — Project Structure
**Length**: 485 LOC  
**Purpose**: Directory map, file organization, metrics, key dependencies  
**Best for**: Understanding codebase structure, finding files, understanding dependencies

**Key Sections**:
1. Project Overview (brief description, size metrics)
2. Directory Map (visual tree)
3. `infra/environments/dev/` (Terragrunt root, module structure)
4. `infra/stacks/` (4 modules: base-infra, cluster, data, cdn)
5. `infra/packer/` (AMI build)
6. `infra/shared/` (configs, scripts)
7. `jobs/` (Nomad jobs)
8. `vault/` (initialization script)
9. `docker/` (application images)
10. `scripts/` (utilities)
11. `docs/` (documentation)
12. File metrics (code distribution, Terraform breakdown)
13. Data flows (job deployment, secret lifecycle)
14. Key dependencies (external services, software versions, internal references)
15. Security architecture
16. Deployment checklist
17. Maintenance notes
18. File size distribution

**Tables**: Metrics, dependencies, quick reference

---

#### [DOCUMENTATION-STATUS.md](./DOCUMENTATION-STATUS.md) — Audit Report
**Length**: 520 LOC  
**Purpose**: Verification that docs match code, coverage assessment, maintenance plan  
**Best for**: Confirming documentation is current, understanding coverage gaps

**Key Sections**:
1. Inventory (all 7 files, LOC counts)
2. Size compliance (all within limits)
3. Coverage assessment (11 functional areas)
4. Code reference verification
5. CLI command verification
6. File path verification
7. Variable name verification
8. Cross-references check
9. Accuracy assessment (examples, environment values, API responses)
10. Deployment guide quality (8 steps, 6 troubleshooting scenarios)
11. Architecture documentation (7 layers, 5 data flows)
12. Maintenance triggers and schedule
13. Sign-off checklist

---

## Documentation Statistics

### By Size

| File | LOC | Type |
|------|-----|------|
| code-standards.md | 809 | Reference |
| deployment-guide.md | 639 | How-to |
| consul-role-overview.md | 556 | Technical Deep-dive |
| system-architecture.md | 476 | Architecture |
| codebase-summary.md | 485 | Codebase Overview |
| secrets-management-flow.md | 447 | Technical Deep-dive |
| DOCUMENTATION-STATUS.md | 520 | Audit Report |
| INDEX.md (this file) | 300+ | Navigation |
| README.md | 209 | Entry Point |
| **TOTAL** | **~4,900** | **Production-Grade** |

### By Type

| Type | Count | Purpose |
|------|-------|---------|
| Entry Points | 1 | README.md — Quick orientation |
| How-To Guides | 1 | deployment-guide.md — Hands-on instructions |
| Architecture Docs | 3 | system-architecture, consul-role, secrets-management |
| Reference Docs | 2 | code-standards, codebase-summary |
| Meta Docs | 2 | INDEX, DOCUMENTATION-STATUS |

---

## Reading Paths

### Path 1: Fresh Deployment (40 minutes)

1. README.md (5 min) — Understand the project
2. Deployment Guide (30 min) — Follow step-by-step
3. Quick reference (5 min) — Copy commands as needed

**Outcome**: Fully deployed infrastructure in 30-40 minutes

---

### Path 2: Architectural Understanding (90 minutes)

1. README.md (5 min) — Overview
2. System Architecture (30 min) — All layers
3. Consul Role Overview (20 min) — Service discovery
4. Secrets Management Flow (20 min) — Vault integration
5. Codebase Summary (15 min) — File organization

**Outcome**: Complete understanding of how infrastructure works

---

### Path 3: Contributing Code (45 minutes)

1. Codebase Summary (10 min) — Where files are
2. Code Standards (20 min) — Patterns to follow
3. System Architecture (10 min) — Design decisions
4. Reference docs as needed

**Outcome**: Ready to add features, fix bugs, improve infrastructure

---

### Path 4: Maintenance & Operations (ongoing)

- **Daily**: Quick reference commands in deployment guide
- **Weekly**: Check DOCUMENTATION-STATUS for needed updates
- **On-demand**: Architecture docs for design decisions
- **On-demand**: Code standards for new contributions

---

## Cross-Reference Map

```
README.md
├─ System Architecture (quick link)
├─ Deployment Guide (quick link)
├─ Consul Role (quick link)
└─ Secrets Management (quick link)

System Architecture
├─ Deployment Guide (how to implement)
├─ Consul Role (service mesh section)
├─ Secrets Management (secrets section)
├─ Code Standards (patterns used)
└─ Codebase Summary (file locations)

Deployment Guide
├─ System Architecture (reference)
├─ Consul Role (service discovery section)
├─ Secrets Management (Vault setup section)
└─ Code Standards (for contributions)

Consul Role Overview
├─ System Architecture (cluster layer)
├─ Secrets Management (Consul backend)
└─ Code Standards (HCL patterns)

Secrets Management Flow
├─ System Architecture (security layer)
├─ Code Standards (HCL patterns)
└─ Deployment Guide (Vault initialization)

Code Standards
├─ Codebase Summary (file organization)
├─ System Architecture (patterns reference)
└─ Deployment Guide (CLI commands)

Codebase Summary
├─ Code Standards (file naming)
├─ System Architecture (layer details)
└─ Deployment Guide (deployment order)

DOCUMENTATION-STATUS
├─ All files (verification of accuracy)
└─ INDEX (this file)
```

---

## Search Tips

**Looking for**... | **Check**
---|---
Terraform patterns | code-standards.md → Terraform section
How to deploy | README.md or deployment-guide.md
Service discovery | consul-role-overview.md
Vault setup | secrets-management-flow.md or deployment-guide.md (Step 5)
Directory structure | codebase-summary.md or README.md
Troubleshooting | deployment-guide.md → Troubleshooting section
File locations | codebase-summary.md → Directory map
Architecture overview | system-architecture.md
Security | system-architecture.md → Security section
HA / Scaling | system-architecture.md → Disaster Recovery section
Commands reference | deployment-guide.md → Quick reference

---

## How to Contribute

When adding features or fixing bugs:

1. **Read**: code-standards.md for patterns to follow
2. **Reference**: codebase-summary.md for file locations
3. **Update**: These docs if you change structure
4. **Test**: deployment-guide.md procedures remain accurate
5. **Report**: Any inaccuracies to DOCUMENTATION-STATUS for next audit

---

## Maintenance Schedule

- **Weekly**: Review commits; update if code changes
- **Monthly**: Verify links remain valid
- **Quarterly**: Run through deployment-guide.md; update if procedures change
- **Annually**: Full audit + version compatibility review

---

## Document Quality

✅ **All documentation is**:
- Verified against actual codebase
- Tested for accuracy (commands, paths, syntax)
- Cross-referenced and linked
- Organized by user journey
- Self-contained (each doc stands alone)
- Comprehensive (covers all key areas)
- Maintainable (clear structure for future updates)

---

**Last Updated**: 2026-05-14  
**Status**: Production-Ready  
**Next Review**: 2026-06-14
