job "drone-runner" {
  datacenters = ["dc1"]
  type        = "system"

  group "runner" {
    vault {
      policies = ["drone"]
    }

    task "runner" {
      driver = "docker"

      config {
        image      = "drone/drone-runner-docker:1"
        privileged = true
        volumes = [
          "/var/run/docker.sock:/var/run/docker.sock"
        ]
      }

      template {
        data = <<EOF
{{with secret "secret/data/drone"}}
DRONE_RPC_SECRET={{.Data.data.rpc_secret}}
DRONE_SECRET_PLUGIN_TOKEN={{.Data.data.rpc_secret}}
{{end}}
DRONE_RPC_HOST=drone-server.service.consul
DRONE_RPC_PROTO=http
DRONE_RUNNER_CAPACITY=2
DRONE_RUNNER_NAME={{env "attr.unique.hostname"}}
DRONE_SECRET_PLUGIN_ENDPOINT=http://drone-vault.service.consul:3000
EOF
        destination = "secrets/env"
        env         = true
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }
  }
}
