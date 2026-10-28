locals {
  net    = "dr-net"             # the lab network (10.0.202.0/24); it is not part of the environment
  prefix = "dr"
}

data "docker_network" "lab" {
  name = local.net
}

# ---------- volumes: the environment's data. NOT backups: the disaster deletes them with everything else ----------
resource "docker_volume" "data" {
  for_each = toset(["pgdata", "vaultdata", "tsdb", "grafana"])
  name     = "${local.prefix}-${each.key}"
  labels {
    label = "course"
    value = "devops"
  }
}

resource "docker_image" "img" {
  for_each = {
    postgres   = "localhost:5001/allcs/postgres:18.6-wal"
    agent      = "localhost:5001/allcs/backup-agent:1.0"
    vault      = "hashicorp/vault:2.1.2"
    prometheus = "prom/prometheus:v3.15.0"
    grafana    = "grafana/grafana:13.2.4"
  }
  name         = each.value
  keep_locally = true
}

# ---------- the catalog database (on AWS: RDS) ----------
resource "docker_container" "db" {
  name     = "${local.prefix}-db"
  hostname = "db"
  image    = docker_image.img["postgres"].image_id
  memory   = 384
  restart  = "unless-stopped"
  networks_advanced {
    name         = data.docker_network.lab.name
    ipv4_address = "10.0.202.10"
    aliases      = ["db"]
  }
  env = [
    "DB_SOURCE=${var.db_source}",
    "BUCKET=http://10.0.202.6:9000",
    "POSTGRES_DB=catalog",
    "POSTGRES_PASSWORD=${var.db_admin_password}",
    "TZ=UTC",
  ]
  command = ["postgres",
    "-c", "archive_mode=on",
    "-c", "archive_command=archive-wal.sh %p %f",
    "-c", "archive_timeout=${var.archive_timeout}",
    "-c", "timezone=UTC", "-c", "log_timezone=UTC",
  ]
  volumes {
    volume_name    = docker_volume.data["pgdata"].name
    container_path = "/var/lib/postgresql"
  }
  upload {
    file    = "/docker-entrypoint-initdb.d/10-seed.sql"
    content = file("${path.module}/files/postgres/10-seed.sql")
  }
  upload {
    file    = "/docker-entrypoint-initdb.d/20-replication.sh"
    content = file("${path.module}/files/postgres/20-replication.sh")
  }
  labels {
    label = "course"
    value = "devops"
  }
}

# ---------- Vault: the secrets (raft storage on its own volume, starts sealed) ----------
resource "docker_container" "vault" {
  name     = "${local.prefix}-vault"
  hostname = "vault"
  image    = docker_image.img["vault"].image_id
  command  = ["server"]
  memory   = 256
  restart  = "unless-stopped"
  networks_advanced {
    name         = data.docker_network.lab.name
    ipv4_address = "10.0.202.11"
    aliases      = ["vault"]
  }
  env = ["TZ=UTC"]
  volumes {
    volume_name    = docker_volume.data["vaultdata"].name
    container_path = "/vault/file"
  }
  upload {
    file    = "/vault/config/vault.hcl"
    content = file("${path.module}/files/vault.hcl")
  }
  labels {
    label = "course"
    value = "devops"
  }
}

# ---------- the backup agent: base backups + Vault snapshots -> the off-site bucket ----------
resource "docker_container" "backup_agent" {
  name     = "${local.prefix}-backup-agent"
  hostname = "backup-agent"
  image    = docker_image.img["agent"].image_id
  memory   = 128
  restart  = "unless-stopped"
  networks_advanced {
    name         = data.docker_network.lab.name
    ipv4_address = "10.0.202.12"
  }
  env = [
    "BUCKET=http://10.0.202.6:9000",
    "PGPASSWORD=${var.db_admin_password}",
    "VAULT_ADDR=http://10.0.202.11:8200",
    "VAULT_TOKEN=${var.vault_snapshot_token}",
    "VAULT_EVERY=60",
    "BASE_EVERY=21600",
    "TZ=UTC",
  ]
  depends_on = [docker_container.db, docker_container.vault]
  labels {
    label = "course"
    value = "devops"
  }
}

# ---------- monitoring: Prometheus + Grafana, config and dashboards from this repo ----------
resource "docker_container" "prometheus" {
  name     = "${local.prefix}-prometheus"
  hostname = "prometheus"
  image    = docker_image.img["prometheus"].image_id
  memory   = 256
  restart  = "unless-stopped"
  networks_advanced {
    name         = data.docker_network.lab.name
    ipv4_address = "10.0.202.13"
  }
  ports {
    internal = 9090
    external = 9090
    ip       = "127.0.0.1"
  }
  volumes {
    volume_name    = docker_volume.data["tsdb"].name
    container_path = "/prometheus"
  }
  upload {
    file    = "/etc/prometheus/prometheus.yml"
    content = file("${path.module}/files/prometheus.yml")
  }
  labels {
    label = "course"
    value = "devops"
  }
}

resource "docker_container" "grafana" {
  name     = "${local.prefix}-grafana"
  hostname = "grafana"
  image    = docker_image.img["grafana"].image_id
  memory   = 640
  restart  = "unless-stopped"
  networks_advanced {
    name         = data.docker_network.lab.name
    ipv4_address = "10.0.202.14"
  }
  ports {
    internal = 3000
    external = 3000
    ip       = "127.0.0.1"
  }
  env = [
    "GF_AUTH_ANONYMOUS_ENABLED=true",           # lab: read-only viewers without a login, for the drill screen
    "GF_AUTH_ANONYMOUS_ORG_ROLE=Viewer",
    "GF_SECURITY_ADMIN_PASSWORD=FAKE-lab-grafana-202",
    "GF_ANALYTICS_REPORTING_ENABLED=false",
    "GF_ANALYTICS_CHECK_FOR_UPDATES=false",
    "GF_PLUGINS_PREINSTALL_DISABLED=true",      # no plugin downloads at start: a restore must not need the internet
    "TZ=UTC",
  ]
  volumes {
    volume_name    = docker_volume.data["grafana"].name
    container_path = "/var/lib/grafana"
  }
  upload {
    file    = "/etc/grafana/provisioning/datasources/prometheus.yaml"
    content = file("${path.module}/files/grafana/datasource.yaml")
  }
  upload {
    file    = "/etc/grafana/provisioning/dashboards/allcs.yaml"
    content = file("${path.module}/files/grafana/dashboards.yaml")
  }
  upload {
    file    = "/etc/grafana/dashboards/dr.json"
    content = file("${path.module}/files/grafana/dashboards/dr.json")
  }
  labels {
    label = "course"
    value = "devops"
  }
}

output "endpoints" {
  value = {
    database   = "10.0.202.10:5432"
    vault      = "http://10.0.202.11:8200"
    prometheus = "http://127.0.0.1:9090"
    grafana    = "http://127.0.0.1:3000"
  }
}
