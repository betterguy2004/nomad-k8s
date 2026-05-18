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
{{- with secret "secret/data/drone/server" }}
DRONE_RPC_SECRET={{ .Data.data.rpc_secret }}
{{- end }}
{{- range service "drone-server" }}
DRONE_RPC_HOST={{ .Address }}:{{ .Port }}
{{- end }}
DRONE_RPC_PROTO=http
DRONE_RUNNER_CAPACITY=2
DRONE_RUNNER_NAME={{ env "attr.unique.hostname" }}
EOF
        destination = "secrets/runner.env"
        env         = true
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }
  }
}
