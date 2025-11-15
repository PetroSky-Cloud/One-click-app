#!/bin/bash


MASTERKEY=`uuidgen`-`uuidgen`

apt-get -y install unzip wget curl uuid-runtime net-tools -y
useradd -r -s /bin/false -d /opt/meilisearch  meilisearch
mkdir -p /opt/meilisearch/{data,dumps,snapshots}
cd /opt/meilisearch

# curl -s https://raw.githubusercontent.com/meilisearch/meilisearch/refs/heads/main/config.toml > config.toml

curl -s https://raw.githubusercontent.com/meilisearch/meilisearch/refs/heads/main/download-latest.sh | bash
chown -R meilisearch:meilisearch /opt/meilisearch

cat > config.toml <<-EOF
db_path = "/opt/meilisearch/data"
env = "production"
http_addr = "0.0.0.0:7700"
master_key = "${MASTERKEY}"
http_payload_size_limit = "100 MB"
log_level = "INFO"
dump_dir = "/opt/meilisearch/"
ignore_missing_dump = false
ignore_dump_if_db_exists = false
schedule_snapshot = false
snapshot_dir = "/opt/meilisearch/snapshots"
ignore_missing_snapshot = false
ignore_snapshot_if_db_exists = false
ssl_require_auth = false
ssl_resumption = false
ssl_tickets = false
experimental_enable_metrics = false
experimental_reduce_indexing_memory_usage = false
EOF

# ./meilisearch superuser upsert  $USER $PASS

cat > /etc/systemd/system/meilisearch.service <<- EOF
[Unit]
Description=meilisearch
Documentation=https://github.com/meilisearch/meilisearch
Wants=network-online.target
After=network-online.target

[Service]
User=meilisearch
Group=meilisearch
WorkingDirectory = /opt/meilisearch/
ExecReload=/bin/kill -HUP $MAINPID
ExecStart=/opt/meilisearch/meilisearch
KillMode=process
KillSignal=SIGINT
LimitNOFILE=infinity
LimitNPROC=infinity
Restart=on-failure
RestartSec=2
StartLimitBurst=3
StartLimitIntervalSec=10
TasksMax=infinity

[Install]
WantedBy=multi-user.target
EOF

systemctl  daemon-reload
systemctl  enable meilisearch.service
systemctl  restart meilisearch.service
