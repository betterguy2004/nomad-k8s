#!/bin/bash
set -e

echo "Configuring Consul service intentions..."

echo "Setting default deny..."
cat <<EOF | consul config write -
Kind = "service-intentions"
Name = "*"
Sources = [
  {
    Name   = "*"
    Action = "deny"
  }
]
EOF

echo "Allowing nginx -> wordpress..."
cat <<EOF | consul config write -
Kind = "service-intentions"
Name = "wordpress"
Sources = [
  {
    Name   = "nginx"
    Action = "allow"
  }
]
EOF

echo "Allowing nginx -> laravel..."
cat <<EOF | consul config write -
Kind = "service-intentions"
Name = "laravel"
Sources = [
  {
    Name   = "nginx"
    Action = "allow"
  }
]
EOF

echo "Allowing apps -> mysql..."
cat <<EOF | consul config write -
Kind = "service-intentions"
Name = "mysql"
Sources = [
  {
    Name   = "wordpress"
    Action = "allow"
  },
  {
    Name   = "laravel"
    Action = "allow"
  }
]
EOF

echo "Allowing drone-runner -> nomad..."
cat <<EOF | consul config write -
Kind = "service-intentions"
Name = "nomad"
Sources = [
  {
    Name   = "drone-runner"
    Action = "allow"
  }
]
EOF

echo "Consul intentions configured successfully"
consul intention list
