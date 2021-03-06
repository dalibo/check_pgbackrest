#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

PGVER="$1"
PGDATA="$2"
PGUSER="$3"
PGPORT="$4"
PGSVC="$5"
ENCRYPTED="$6"

CIPHER=
# pgbackrest.conf setup
if [ $ENCRYPTED = "true" ]; then
    CIPHER='repo1-cipher-type=aes-256-cbc
repo1-cipher-pass=acbd'
fi

cat<<EOC > "/etc/pgbackrest.conf"
[global]
repo1-path=/var/lib/pgbackrest
repo1-retention-full=1
process-max=2
log-level-console=warn
log-level-file=info
delta=y
start-fast=y
$CIPHER

[my_stanza]
pg1-host=pgsql-srv
pg1-host-user=${PGUSER}
pg1-path=${PGDATA}
recovery-option=primary_conninfo=host=pgsql-srv user=${PGUSER} port=${PGPORT}
EOC

# force proper permissions on repo1-path
chmod 755 /var/lib/pgbackrest

sudo -iu ${PGUSER} pgbackrest --stanza=my_stanza stanza-create
sudo -iu ${PGUSER} pgbackrest --stanza=my_stanza check
sudo -iu ${PGUSER} pgbackrest --stanza=my_stanza backup --type=full --repo1-retention-full=1

# build streaming replication
systemctl stop ${PGSVC}
sudo -iu ${PGUSER} pgbackrest --stanza=my_stanza --type=standby --target-timeline=latest --reset-pg1-host restore
systemctl start ${PGSVC}

# test the backup-standby option
sudo -iu ${PGUSER} pgbackrest --stanza=my_stanza --backup-standby --pg2-path=${PGDATA} --pg2-user=${PGUSER} --pg2-port=${PGPORT} --type=incr backup