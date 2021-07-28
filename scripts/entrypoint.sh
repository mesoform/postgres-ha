#!/bin/bash

export POSTGRES_USER=$POSTGRES_USER
export POSTGRES_DB=$POSTGRES_DB
export PGPORT=${PGPORT:-5432}
export PG_MASTER=${PG_MASTER:false}
export PG_SLAVE=${PG_SLAVE:false}
export SYNC_REPLICATION=${SYNC_REPLICATION:true}
export PG_REP_USER=$PG_REP_USER
export PG_REP_PASSWORD_FILE=$PG_REP_PASSWORD_FILE
export HBA_ADDRESS=$HBA_ADDRESS
export PG_MASTER_HOST=$PG_MASTER_HOST
export BACKUPS=${BACKUPS:false}
export STORAGE_BUCKET=$STORAGE_BUCKET
export GCP_CREDENTIALS=$GCP_CREDENTIALS
export RESTORE_BACKUP=${RESTORE_BACKUP:false}
export BACKUP_NAME=$BACKUP_NAME


if [[ ${PG_MASTER^^} == TRUE && ${PG_SLAVE^^} == TRUE ]]; then
  echo "Both \$PG_MASTER and \$PG_SLAVE cannot be true"
  exit 1
fi

if [[ ${BACKUPS^^} == TRUE ]] && [[ -z ${STORAGE_BUCKET} || -z ${GCP_CREDENTIALS} ]]; then
  echo "GCS bucket and service account credentials are needed to store backups" && exit 1
elif [[ ${BACKUPS^^} == TRUE && -n ${STORAGE_BUCKET} && -n ${GCP_CREDENTIALS} ]]; then
  export ARCHIVE_COMMAND="/usr/local/scripts/walg_caller.sh wal-push %p"
else
  export ARCHIVE_COMMAND="echo \"archiving set to $PGDATA/pg_wal/%f\""
fi

if [[ ${RESTORE_BACKUP^^} == TRUE && -z ${BACKUP_NAME} ]]; then
  echo "To restore a backup from GCS a backup name is needed"
  exit 1
fi

function take_base_backup() {
    docker_setup_env
    echo "sleep 30" && sleep 30
    docker_temp_server_start
    echo "Running initial database base backup"
    /usr/local/scripts/walg_caller.sh backup-push "$PGDATA"
    docker_temp_server_stop
}

function init_postgres_conf() {
    if [[ -f $config_file ]]; then
      echo "Reinitialising config file"
      sed -i "s/wal_level =.*$//g" "$config_file"
      sed -i "s/archive_mode =.*$//g" "$config_file"
      sed -i "s/archive_command =.*$//g" "$config_file"
      sed -i "s/max_wal_senders =.*$//g" "$config_file"
      sed -i "s/wal_keep_size =.*$//g" "$config_file"
      sed -i "s/hot_standby =.*$//g" "$config_file"
      sed -i "s/synchronous_standby_names =.*$//g" "$config_file"
      sed -i "s/restore_command =.*$//g" "$config_file"
      sed -i "s/recovery_target_time =.*$//g" "$config_file"
    fi
}

function create_master_db() {
    echo "No existing database detected, proceed to initialisation"
    docker_create_db_directories
    docker_verify_minimum_env
    ls /docker-entrypoint-initdb.d/ > /dev/null
    docker_init_database_dir
    pg_setup_hba_conf
    export PGPASSWORD="${PGPASSWORD:-$POSTGRES_PASSWORD}"
    docker_temp_server_start
    docker_setup_db
}

function setup_master_db() {
    docker_setup_env
    #If config file does not exist then create and initialise database and replication
    if [[ ! -f $config_file ]]; then
      create_master_db
    else
      docker_temp_server_start
    fi
    init_postgres_conf
    if [[ ${PG_MASTER^^} == TRUE ]]; then
      echo "Setting up replication on master instance"
      docker_process_init_files /docker-entrypoint-initdb.d/*
    elif [[ ${BACKUPS^^} == TRUE ]]; then
      echo "Setting up standalone PostgreSQL instance with WAL archiving"
      {
        echo "wal_level = replica"
        echo "archive_mode = on"
        echo "archive_command = '${ARCHIVE_COMMAND}'"
      } >>"$PGDATA"/postgresql.conf
    else
      echo "Setting up standalone PostgreSQL instance"
    fi
    docker_temp_server_stop
    echo 'PostgreSQL init process complete; ready for start up'
}

function init_walg_conf() {
    echo "Initialising wal-g script variables"
    backup_file=/usr/local/scripts/walg_caller.sh

    sed -i 's@GCPCREDENTIALS@'"$GCP_CREDENTIALS"'@' $backup_file
    sed -i 's@STORAGEBUCKET@'"$STORAGE_BUCKET"'@' $backup_file
    sed -i 's@POSTGRESUSER@'"$POSTGRES_USER"'@' $backup_file
    sed -i 's@POSTGRESDB@'"$POSTGRES_DB"'@' $backup_file
    HOSTNAMEDATE="$(hostname)-$(date +"%d%m%Y")"
    sed -i 's@CONTAINERDATE@'"$HOSTNAMEDATE"'@' $backup_file
}

function restore_walg_conf() {
    echo "Initialising wal-g restore script variables"
    cp /usr/local/scripts/walg_caller.sh /usr/local/scripts/walg_restore.sh
    restore_file=/usr/local/scripts/walg_restore.sh

    sed -i 's@GCPCREDENTIALS@'"$GCP_CREDENTIALS"'@' $restore_file
    sed -i 's@STORAGEBUCKET@'"$STORAGE_BUCKET"'@' $restore_file
    sed -i 's@CONTAINERDATE@'"$BACKUP_NAME"'@' $restore_file
    sed -i 's@POSTGRESUSER@'"$POSTGRES_USER"'@' $restore_file
    sed -i 's@POSTGRESDB@'"$POSTGRES_DB"'@' $restore_file
}

function restore_backup() {
    docker_setup_env
    restore_walg_conf
    echo "Restoring backup $BACKUP_NAME"
    /usr/local/scripts/walg_restore.sh backup-fetch "$PGDATA" LATEST
    init_postgres_conf
    echo "Adding recovery config file"
    {
      echo "restore_command = '/usr/local/scripts/walg_restore.sh wal-fetch %f %p'"
    } >>"$PGDATA"/postgresql.conf

    touch "${PGDATA}"/recovery.signal

    docker_temp_server_start
    while [[ -f "${PGDATA}"/recovery.signal ]]; do sleep 2 && echo "."; done
    docker_temp_server_stop
}

if [[ $(id -u) == 0 ]]; then
  # then restart script as postgres user
  # shellcheck disable=SC2128
  echo "Detected running as root user, changing to postgres"
  exec su-exec postgres "$BASH_SOURCE" "$@"
fi

if [[ ${1:0:1} == - ]]; then
  set -- postgres "$@"
fi

source /usr/local/bin/docker-entrypoint.sh
config_file=$PGDATA/postgresql.conf

if [[ $1 == postgres ]]; then
  if [[ ${PG_SLAVE^^} == TRUE ]]; then
    echo "Update postgres slave configuration"
    /docker-entrypoint-initdb.d/setup-slave.sh
  else
    [[ ${RESTORE_BACKUP^^} == TRUE ]] && restore_backup
    [[ ${BACKUPS^^} == TRUE ]] && init_walg_conf
    setup_master_db
    [[ ${BACKUPS^^} == TRUE ]] && take_base_backup
    unset PGPASSWORD
  fi
  echo "Running main postgres entrypoint"
  bash /usr/local/bin/docker-entrypoint.sh postgres
fi
