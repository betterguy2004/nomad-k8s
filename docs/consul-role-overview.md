# Consul Role Overview

## Overview

Consul đóng **3 vai trò chính** trong AWS Nomad Infrastructure:
1. **Service Discovery** - Catalog và routing cho dynamic containers
2. **Cluster Backend** - Storage cho Vault, auto-join cho cluster
3. **Service Mesh** - mTLS encryption và access control (Consul Connect)

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           CONSUL ARCHITECTURE                                │
│                                                                              │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                         CONSUL CLUSTER                                 │  │
│  │                         (3 Server Nodes)                               │  │
│  │                                                                        │  │
│  │  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐                │  │
│  │  │   Node 1    │◄──►│   Node 2    │◄──►│   Node 3    │                │  │
│  │  │   Server    │    │   Server    │    │   Server    │                │  │
│  │  │   Leader    │    │   Follower  │    │   Follower  │                │  │
│  │  └─────────────┘    └─────────────┘    └─────────────┘                │  │
│  │         │                  │                  │                        │  │
│  │         └──────────────────┼──────────────────┘                        │  │
│  │                            │                                           │  │
│  │  ┌─────────────────────────┼─────────────────────────────────────┐    │  │
│  │  │                         │                                      │    │  │
│  │  │    ┌────────────────────┴────────────────────┐                │    │  │
│  │  │    │            CONSUL FEATURES              │                │    │  │
│  │  │    │                                         │                │    │  │
│  │  │    │  ┌─────────────┐  ┌─────────────────┐  │                │    │  │
│  │  │    │  │  Service    │  │   KV Store      │  │                │    │  │
│  │  │    │  │  Catalog    │  │   (Vault data)  │  │                │    │  │
│  │  │    │  └─────────────┘  └─────────────────┘  │                │    │  │
│  │  │    │                                         │                │    │  │
│  │  │    │  ┌─────────────┐  ┌─────────────────┐  │                │    │  │
│  │  │    │  │  Health     │  │   Connect       │  │                │    │  │
│  │  │    │  │  Checks     │  │   (mTLS)        │  │                │    │  │
│  │  │    │  └─────────────┘  └─────────────────┘  │                │    │  │
│  │  │    └─────────────────────────────────────────┘                │    │  │
│  │  └────────────────────────────────────────────────────────────────┘    │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                                                              │
│                    CONSUMERS                                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │   Nomad     │  │   Vault     │  │   Nginx     │  │  Services   │        │
│  │ (register   │  │ (storage    │  │ (discover   │  │ (mesh +     │        │
│  │  services)  │  │  backend)   │  │  upstreams) │  │  mTLS)      │        │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘        │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 1. Service Discovery

### Registration Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        SERVICE REGISTRATION                              │
│                                                                          │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │ Nomad Job Starts Container                                        │   │
│  └────────────────────────────┬─────────────────────────────────────┘   │
│                               │                                          │
│                               ▼                                          │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │ Nomad Agent Registers Service to Consul                          │   │
│  │                                                                   │   │
│  │   service {                                                       │   │
│  │     name = "wordpress"                                            │   │
│  │     port = "fpm"        ──► wordpress.service.consul              │   │
│  │     check { tcp }                                                 │   │
│  │   }                                                               │   │
│  └────────────────────────────┬─────────────────────────────────────┘   │
│                               │                                          │
│                               ▼                                          │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │ Consul Catalog Updated                                            │   │
│  │                                                                   │   │
│  │   Services:                                                       │   │
│  │   ├── wordpress                                                   │   │
│  │   │   ├── 10.0.1.5:9000 (healthy)                                │   │
│  │   │   └── 10.0.1.6:9000 (healthy)                                │   │
│  │   ├── laravel                                                     │   │
│  │   │   ├── 10.0.1.7:9000 (healthy)                                │   │
│  │   │   └── 10.0.1.8:9000 (healthy)                                │   │
│  │   └── nginx                                                       │   │
│  │       ├── 10.0.1.5:80                                            │   │
│  │       ├── 10.0.1.6:80                                            │   │
│  │       └── 10.0.1.7:80                                            │   │
│  └──────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
```

### Discovery Flow (Nginx + Consul Template)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        SERVICE DISCOVERY                                 │
│                                                                          │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │ Nginx Template (Nomad template block)                             │   │
│  │                                                                   │   │
│  │   template {                                                      │   │
│  │     data = <<EOF                                                  │   │
│  │     upstream wordpress {                                          │   │
│  │       {{range service "wordpress"}}                               │   │
│  │       server {{.Address}}:{{.Port}};                              │   │
│  │       {{end}}                                                     │   │
│  │     }                                                             │   │
│  │     EOF                                                           │   │
│  │   }                                                               │   │
│  └────────────────────────────┬─────────────────────────────────────┘   │
│                               │                                          │
│                               │ Query Consul API                         │
│                               ▼                                          │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │ Consul Returns Service Instances                                  │   │
│  │                                                                   │   │
│  │   GET /v1/health/service/wordpress?passing=true                   │   │
│  │                                                                   │   │
│  │   Response:                                                       │   │
│  │   [                                                               │   │
│  │     { "Address": "10.0.1.5", "Port": 9000 },                     │   │
│  │     { "Address": "10.0.1.6", "Port": 9000 }                      │   │
│  │   ]                                                               │   │
│  └────────────────────────────┬─────────────────────────────────────┘   │
│                               │                                          │
│                               │ Generate nginx.conf                      │
│                               ▼                                          │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │ Generated Nginx Config                                            │   │
│  │                                                                   │   │
│  │   upstream wordpress {                                            │   │
│  │     server 10.0.1.5:9000;                                        │   │
│  │     server 10.0.1.6:9000;                                        │   │
│  │   }                                                               │   │
│  │                                                                   │   │
│  │   # Auto-updated when services change                             │   │
│  │   # Nginx receives SIGHUP to reload                               │   │
│  └──────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
```

### Service Lifecycle

```
Container Start ──► Register ──► Health Check Pass ──► In Catalog
       │                                                    │
       │                                                    ▼
       │                                            Traffic Routed
       │                                                    │
       │              Health Check Fail ◄───────────────────┘
       │                     │
       │                     ▼
       │              Marked Unhealthy
       │                     │
       │                     ▼
       │              Removed from Routing
       │                     │
Container Stop ◄─────────────┘
       │
       ▼
  Deregister from Consul
```

---

## 2. Cluster Formation & Backend

### Auto-Join via AWS Tags

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      CLUSTER AUTO-JOIN                                   │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │ EC2 Instance Tags                                                │    │
│  │                                                                  │    │
│  │   Node 1:                                                        │    │
│  │     Name: nomad-node-1                                           │    │
│  │     ConsulAutoJoin: auto-join    ◄── Tag for discovery           │    │
│  │                                                                  │    │
│  │   Node 2:                                                        │    │
│  │     Name: nomad-node-2                                           │    │
│  │     ConsulAutoJoin: auto-join                                    │    │
│  │                                                                  │    │
│  │   Node 3:                                                        │    │
│  │     Name: nomad-node-3                                           │    │
│  │     ConsulAutoJoin: auto-join                                    │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                               │                                          │
│                               ▼                                          │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │ Consul Config (user-data)                                        │    │
│  │                                                                  │    │
│  │   retry_join = [                                                 │    │
│  │     "provider=aws",                                              │    │
│  │     "tag_key=ConsulAutoJoin",                                    │    │
│  │     "tag_value=auto-join"                                        │    │
│  │   ]                                                              │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                               │                                          │
│                               ▼                                          │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │ Consul Agent Startup                                             │    │
│  │                                                                  │    │
│  │   1. Query EC2 API for instances with tag                        │    │
│  │   2. Get private IPs: [10.0.1.5, 10.0.1.6, 10.0.1.7]            │    │
│  │   3. Join cluster using discovered IPs                           │    │
│  │   4. Participate in leader election                              │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                                                                          │
│  Required IAM Permissions:                                               │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │   {                                                              │    │
│  │     "Effect": "Allow",                                           │    │
│  │     "Action": [                                                  │    │
│  │       "ec2:DescribeInstances",                                   │    │
│  │       "ec2:DescribeTags"                                         │    │
│  │     ],                                                           │    │
│  │     "Resource": "*"                                              │    │
│  │   }                                                              │    │
│  └─────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘
```

### Vault Storage Backend

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     VAULT CONSUL BACKEND                                 │
│                                                                          │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │ Vault Config                                                      │   │
│  │                                                                   │   │
│  │   storage "consul" {                                              │   │
│  │     address = "127.0.0.1:8500"                                    │   │
│  │     path    = "vault/"                                            │   │
│  │   }                                                               │   │
│  └────────────────────────────┬─────────────────────────────────────┘   │
│                               │                                          │
│                               ▼                                          │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │ Consul KV Store                                                   │   │
│  │                                                                   │   │
│  │   vault/                                                          │   │
│  │   ├── core/                                                       │   │
│  │   │   ├── leader         ◄── Vault leader election               │   │
│  │   │   ├── seal-config                                            │   │
│  │   │   └── mounts                                                 │   │
│  │   ├── logical/                                                    │   │
│  │   │   ├── database/                                              │   │
│  │   │   └── secret/                                                │   │
│  │   └── sys/                                                        │   │
│  │       ├── policy/                                                │   │
│  │       └── token/                                                 │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Benefits:                                                               │
│  • Distributed storage across 3 nodes                                    │
│  • Automatic replication                                                 │
│  • Leader election for Vault HA                                          │
│  • Consistent reads/writes                                               │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Service Mesh (Consul Connect)

### mTLS Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                       CONSUL CONNECT mTLS                                │
│                                                                          │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │                     CONSUL CA                                     │   │
│  │                                                                   │   │
│  │   • Built-in Certificate Authority                               │   │
│  │   • Issues SPIFFE-compatible certificates                        │   │
│  │   • Automatic rotation (default: 72 hours)                       │   │
│  │                                                                   │   │
│  └────────────────────────────┬─────────────────────────────────────┘   │
│                               │                                          │
│         ┌─────────────────────┼─────────────────────┐                   │
│         │                     │                     │                   │
│         ▼                     ▼                     ▼                   │
│  ┌─────────────┐       ┌─────────────┐       ┌─────────────┐           │
│  │   Nginx     │       │  WordPress  │       │   Laravel   │           │
│  │   Service   │       │   Service   │       │   Service   │           │
│  │             │       │             │       │             │           │
│  │ ┌─────────┐ │       │ ┌─────────┐ │       │ ┌─────────┐ │           │
│  │ │  Envoy  │ │       │ │  Envoy  │ │       │ │  Envoy  │ │           │
│  │ │ Sidecar │ │       │ │ Sidecar │ │       │ │ Sidecar │ │           │
│  │ │         │ │       │ │         │ │       │ │         │ │           │
│  │ │ Cert:   │ │       │ │ Cert:   │ │       │ │ Cert:   │ │           │
│  │ │ nginx.  │ │       │ │ wordpre │ │       │ │ laravel │ │           │
│  │ │ service │ │       │ │ ss.svc  │ │       │ │ .svc    │ │           │
│  │ └────┬────┘ │       │ └────┬────┘ │       │ └────┬────┘ │           │
│  └──────┼──────┘       └──────┼──────┘       └──────┼──────┘           │
│         │                     │                     │                   │
│         │        mTLS         │        mTLS         │                   │
│         └─────────────────────┴─────────────────────┘                   │
│                                                                          │
│  All traffic encrypted with mutual TLS:                                  │
│  • Client verifies server certificate                                    │
│  • Server verifies client certificate                                    │
│  • No plaintext traffic within cluster                                   │
└─────────────────────────────────────────────────────────────────────────┘
```

### Intentions (Access Control)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                       CONSUL INTENTIONS                                  │
│                                                                          │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │ Intention Rules (Layer 7 ACL)                                     │   │
│  │                                                                   │   │
│  │   Source          Destination      Action    Description         │   │
│  │   ──────          ───────────      ──────    ───────────         │   │
│  │   nginx           wordpress        ALLOW     LB to app           │   │
│  │   nginx           laravel          ALLOW     LB to app           │   │
│  │   wordpress       mysql            ALLOW     App to DB           │   │
│  │   laravel         mysql            ALLOW     App to DB           │   │
│  │   drone-runner    nomad            ALLOW     CI to scheduler     │   │
│  │   *               *                DENY      Default deny all    │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Traffic Flow with Intentions:                                           │
│                                                                          │
│  ┌────────┐     ┌─────────────┐     ┌───────────┐     ┌─────────┐      │
│  │ Client │────►│    Nginx    │────►│ WordPress │────►│  MySQL  │      │
│  └────────┘     └─────────────┘     └───────────┘     └─────────┘      │
│                        │                                                 │
│                        │ Check intention                                 │
│                        ▼                                                 │
│                 ┌─────────────┐                                         │
│                 │   Consul    │                                         │
│                 │             │                                         │
│                 │ nginx →     │                                         │
│                 │ wordpress?  │                                         │
│                 │             │                                         │
│                 │ ✓ ALLOW     │                                         │
│                 └─────────────┘                                         │
│                                                                          │
│  Blocked Traffic Example:                                                │
│                                                                          │
│  ┌────────────┐         ┌───────────┐                                   │
│  │ drone-     │────X───►│ WordPress │   ✗ No intention exists          │
│  │ runner     │         │           │   ✗ Default DENY applies         │
│  └────────────┘         └───────────┘                                   │
└─────────────────────────────────────────────────────────────────────────┘
```

### Nomad Job with Connect

```hcl
# Nomad job với Consul Connect sidecar
job "wordpress" {
  group "wordpress" {
    
    network {
      mode = "bridge"  # Required for Connect
      port "fpm" { to = 9000 }
    }
    
    service {
      name = "wordpress"
      port = "fpm"
      
      # Enable Consul Connect sidecar proxy
      connect {
        sidecar_service {
          proxy {
            # Upstream to MySQL (via Connect)
            upstreams {
              destination_name = "mysql"
              local_bind_port  = 3306
            }
          }
        }
      }
    }
    
    task "wordpress" {
      # App connects to localhost:3306
      # Envoy proxy routes to mysql.service.consul
      env {
        DB_HOST = "127.0.0.1"
        DB_PORT = "3306"
      }
    }
  }
}
```

---

## 4. Health Checking

```
┌─────────────────────────────────────────────────────────────────────────┐
│                       HEALTH CHECKING                                    │
│                                                                          │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │ Health Check Types                                                │   │
│  │                                                                   │   │
│  │   TCP Check:                                                      │   │
│  │   ┌─────────────────────────────────────────────────────────┐    │   │
│  │   │ check {                                                  │    │   │
│  │   │   type     = "tcp"                                       │    │   │
│  │   │   port     = "fpm"                                       │    │   │
│  │   │   interval = "10s"                                       │    │   │
│  │   │   timeout  = "2s"                                        │    │   │
│  │   │ }                                                        │    │   │
│  │   └─────────────────────────────────────────────────────────┘    │   │
│  │                                                                   │   │
│  │   HTTP Check:                                                     │   │
│  │   ┌─────────────────────────────────────────────────────────┐    │   │
│  │   │ check {                                                  │    │   │
│  │   │   type     = "http"                                      │    │   │
│  │   │   path     = "/health"                                   │    │   │
│  │   │   interval = "10s"                                       │    │   │
│  │   │   timeout  = "2s"                                        │    │   │
│  │   │ }                                                        │    │   │
│  │   └─────────────────────────────────────────────────────────┘    │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  Health Status Flow:                                                     │
│                                                                          │
│  Every 10s:                                                              │
│  ┌──────────┐     TCP/HTTP      ┌──────────────┐                        │
│  │ Consul   │─────────────────►│   Service    │                        │
│  │ Agent    │                   │   Port 9000  │                        │
│  └────┬─────┘◄──────────────────└──────────────┘                        │
│       │           Response                                               │
│       │                                                                  │
│       ▼                                                                  │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │ Update Service Status                                             │   │
│  │                                                                   │   │
│  │   wordpress:                                                      │   │
│  │   ├── 10.0.1.5:9000  Status: passing   ✓ In routing             │   │
│  │   ├── 10.0.1.6:9000  Status: passing   ✓ In routing             │   │
│  │   └── 10.0.1.7:9000  Status: critical  ✗ Removed from routing   │   │
│  └──────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 5. Consul Ports & Communication

```
┌─────────────────────────────────────────────────────────────────────────┐
│                       CONSUL PORTS                                       │
│                                                                          │
│   Port      Protocol    Purpose                                          │
│   ────      ────────    ───────                                          │
│   8300      TCP         Server RPC (Raft consensus)                      │
│   8301      TCP/UDP     Serf LAN (gossip within datacenter)              │
│   8302      TCP/UDP     Serf WAN (gossip across datacenters)             │
│   8500      TCP         HTTP API + UI                                    │
│   8501      TCP         HTTPS API (if TLS enabled)                       │
│   8502      TCP         gRPC (Connect proxy, xDS)                        │
│   8600      TCP/UDP     DNS interface                                    │
│                                                                          │
│  Security Group Rules:                                                   │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │   # Cluster internal (self-reference)                            │   │
│  │   ingress {                                                       │   │
│  │     from_port = 8300                                              │   │
│  │     to_port   = 8302                                              │   │
│  │     protocol  = "tcp"                                             │   │
│  │     self      = true                                              │   │
│  │   }                                                               │   │
│  │                                                                   │   │
│  │   # HTTP API (admin access)                                       │   │
│  │   ingress {                                                       │   │
│  │     from_port   = 8500                                            │   │
│  │     to_port     = 8500                                            │   │
│  │     protocol    = "tcp"                                           │   │
│  │     cidr_blocks = [var.allowed_cidr]                              │   │
│  │   }                                                               │   │
│  └──────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 6. Summary: Consul Responsibilities

| Role | Function | Without Consul |
|------|----------|----------------|
| **Service Discovery** | Dynamic service catalog | Hardcode IPs, manual updates |
| **Health Checking** | Auto-remove unhealthy | Dead services receive traffic |
| **Vault Backend** | Distributed KV storage | Need external storage (S3/DynamoDB) |
| **Cluster Auto-join** | AWS tag-based discovery | Manual cluster config |
| **Service Mesh** | mTLS + Intentions | Unencrypted traffic, no ACL |
| **DNS** | Service DNS resolution | No `service.consul` names |

---

## 7. Troubleshooting Commands

```bash
# Check Consul cluster status
consul members
consul operator raft list-peers

# View service catalog
consul catalog services
consul catalog nodes

# Check service health
consul health checks wordpress
consul health service wordpress

# View KV store (Vault data)
consul kv get -recurse vault/

# Test DNS resolution
dig @127.0.0.1 -p 8600 wordpress.service.consul

# Check Connect CA
consul connect ca get-config

# List intentions
consul intention list

# Test intention (will traffic be allowed?)
consul intention check nginx wordpress

# Debug service registration
consul services register -name=test -port=8080
consul services deregister test
```

---

## References

- [Consul Service Discovery](https://developer.hashicorp.com/consul/docs/concepts/service-discovery)
- [Consul Connect (Service Mesh)](https://developer.hashicorp.com/consul/docs/connect)
- [Vault Consul Backend](https://developer.hashicorp.com/vault/docs/configuration/storage/consul)
- [Nomad Consul Integration](https://developer.hashicorp.com/nomad/docs/integrations/consul-integration)
