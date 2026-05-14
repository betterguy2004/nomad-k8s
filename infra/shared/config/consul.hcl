datacenter = "dc1"
data_dir   = "/opt/consul"

server           = true
bootstrap_expect = SERVER_COUNT

bind_addr   = "IP_ADDRESS"
client_addr = "0.0.0.0"

retry_join = ["RETRY_JOIN"]

connect {
  enabled = true
}

ui_config {
  enabled = true
}

ports {
  grpc = 8502
}
