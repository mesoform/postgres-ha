# Postgres HA

## Summary
Postgres database image setup for HA replication with control over backups and WAL archiving to GCS and backup restoration functionality.

## Semantic versioning 
The way in which versioning is done in this repository and for the image labels which it creates is a little different to standard versioning format. The normal major and minor versions that you would expect are still major and minor versions but they are tracking the major and minor versions of Postgres upstream. The second part of the version system also is broken into two parts, again major and minor versions. These represent major and minor versions of the additional features added by Mesoform. You can expect them to behave in the normal way of major and minor versions, in that major versions could include breaking changes. For example `13.1-1.1` represents Postgres version 13.1 with Mesoform features version 1.1

## How to use
Variables usage:

To create a MASTER instance as part of a PostgreSQL HA setup set the following variables (set PG_MASTER to true):

      - PG_MASTER=true                                          # set to true if this is the master instance on a postgres HA cluster
      - POSTGRES_USER=testuser                                  # master database username              
      - POSTGRES_PASSWORD_FILE=/run/secrets/db_password         # docker secret with the postgres user password
      - POSTGRES_DB=testdb                                      # master database name
      - PGPORT=5432                                             # master database port; defaults to 5432 if not set
      - PG_REP_USER=testrep                                     # replication username
      - PG_REP_PASSWORD_FILE=/run/secrets/db_replica_password   # docker secret with the postgres replica user password
      - HBA_ADDRESS=10.0.0.0/8                                  # Host name or IP address range to allow replication connections from the slave (Replication Host-Based Authentication)
      - SYNC_REPLICATION=true                                   # to set synchronous replication to standby servers; defaults to true if not set 

To create a REPLICA instance as part of a PostgreSQL HA setup set the following variables (set PG_SLAVE to true):

      - PG_SLAVE=true                                           # set to true if this is the replica instance on a postgres HA cluster
      - POSTGRES_USER=testuser                                  # master database username
      - POSTGRES_PASSWORD_FILE=/run/secrets/db_password         # docker secret with the postgres user password
      - POSTGRES_DB=testdb                                      # master database name
      - PGPORT=5432                                             # master database port; defaults to 5432 if not set      
      - PG_REP_USER=testrep                                     # replication username
      - PG_REP_PASSWORD_FILE=/run/secrets/db_replica_password   # docker secret with the postgres replica user password
      - PG_MASTER_HOST=pg_master                                # pg_master service name or swarm node private IP where the pg_master service is running
      - HBA_ADDRESS=10.0.0.0/8                                  # Host name or IP address range to allow replication connections from the master (Replication Host-Based Authentication)

To create a standalone PostgreSQL instance set only the following variables (PG_MASTER or PG_SLAVE vars should not be set):

      - POSTGRES_USER=testuser                                  # database username
      - POSTGRES_PASSWORD_FILE=/run/secrets/db_password         # docker secret with the postgres user password
      - POSTGRES_DB=testdb                                      # database name
      - PGPORT=5432                                             # master database port; defaults to 5432 if not set

To run backups and WAL archiving to GCS (Google Cloud Storage) set the following variables (backups will be taken on a MASTER or STANDALONE instance):

      - BACKUPS=true                                            # switch to implement backups; defaults to false
      - STORAGE_BUCKET=gs://postgresql/backups                  # to specify the GCS bucket
      - GCP_CREDENTIALS=/run/secrets/gcp_credentials            # to specify the docker secret with the service account key that has access to the GCS bucket
      - FULL_BACKUP_SCHEDULE=* * * * *                          # to specify the cron schedule expression at which backups will run (if not set only the first initial base backup will be ran) \
                                                                # L-> check https://crontab.guru/ for schedule expression details. (e.g.: 00 00 * * * -> to run a daily backup at midnight)"
      - CRONITOR_KEY=1a2b3cd4e56789f1234gh5ijkl67m890           # to specify cronitor API key for cron job monitoring. check https://cronitor.io/cron-job-monitoring for details   

Note: HA MASTER instances with BACKUPS disabled will only store WAL logs locally on the `pg_wal` folder under the PGDATA directory path. 
Running a postgres HA cluster without implementing backups is not recommended and is intended only for testing purposes.

## How to create a PostgreSQL HA cluster

See the example in docker-compose-example.yml to create a PostgreSQL HA master/replica setup with synchronous replication and control over backups and WAL archiving to GCS:

```
version: "3.7"
secrets:
  db_replica_password:
    external: true
  db_password:
    external: true
  gcp_credentials:
    external: true

services:
  pg_master:
    image: mesoform/postgres-ha:13-latest
    volumes:
      - pg_data:/var/lib/postgresql/data
    environment:
      - PG_MASTER=true
      - POSTGRES_USER=testuser
      - POSTGRES_PASSWORD_FILE=/run/secrets/db_password
      - POSTGRES_DB=testdb
      - PGPORT=5432
      - PG_REP_USER=testrep
      - PG_REP_PASSWORD_FILE=/run/secrets/db_replica_password
      - HBA_ADDRESS=10.0.0.0/8
      - SYNC_REPLICATION=true
      - BACKUPS=true
      - STORAGE_BUCKET=gs://postgresql/backups
      - GCP_CREDENTIALS=/run/secrets/gcp_credentials
      - FULL_BACKUP_SCHEDULE:00 00 * * *
    ports:
      - "5432:5432"
    secrets:
      - source: db_replica_password
        uid: "70"
        gid: "70"
        mode: 0550
      - source: db_password
        uid: "70"
        gid: "70"
        mode: 0550
      - source: gcp_credentials
        uid: "70"
        gid: "70"
        mode: 0550
    networks:
      database:
        aliases:
          - pg_cluster
    deploy:
      placement:
        constraints:
        - node.labels.type == primary
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "zabbix"]
      interval: 3800s
      timeout: 60s
      retries: 3
      start_period: 60s        
  pg_replica:
    image: mesoform/postgres-ha:13-latest
    volumes:
      - pg_replica:/var/lib/postgresql/data
    environment:
      - PG_SLAVE=true
      - POSTGRES_USER=testuser
      - POSTGRES_PASSWORD_FILE=/run/secrets/db_password
      - POSTGRES_DB=testdb
      - PGPORT=5432
      - PG_REP_USER=testrep
      - PG_REP_PASSWORD_FILE=/run/secrets/db_replica_password
      - PG_MASTER_HOST=pg_master
      - HBA_ADDRESS=10.0.0.0/8
    secrets:
      - source: db_replica_password
        uid: "70"
        gid: "70"
        mode: 0550
      - source: db_password
        uid: "70"
        gid: "70"
        mode: 0550
    networks:
      database:
        aliases:
          - pg_cluster
    deploy:
      placement:
        constraints:
        - node.labels.type == secondary
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "zabbix"]
      interval: 3800s
      timeout: 60s
      retries: 3
      start_period: 60s 

networks:
  database: {}

volumes:
  pg_data: {}
  pg_replica: {}
```

Run with:

```shell script
docker stack deploy -c docker-compose-example.yml test_pg13ha
```

Note: Healthchecks can be added as in the example to avoid processes like backup restoration or database replication from being terminated too early before they complete

## How to restore from a backup

To restore a backup from GCS (Google Cloud Storage) also set the following variables on the docker compose file along with the backups ones (backups can be restored on a MASTER or STANDALONE instance):

      - RESTORE_BACKUP=true                                     # set to true
      - BACKUP_NAME=20220512154510-12abc3d4e5f                  # to specify the name of the GCS backup to be restored (the name corresponds to the <date>-<container-id> -i.e: when/where- the backup was taken)
      - STORAGE_BUCKET=gs://postgresql/backups                  # to specify the GCS bucket backup location
      - GCP_CREDENTIALS=/run/secrets/gcp_credentials            # to specify the docker secret with the service account key that has access to the GCS bucket

The LATEST base backup available from the specified BACKUP_NAME will be restored and all existing WAL archives will be applied to it.

Note: A restore won't be performed unless the database data directory $PGDATA (common location being /var/lib/pgsql/data) is empty, otherwise RESTORE_BACKUP will be set to false.

####Case example:

A database container `12abc3d4e5` was created on `20220512154510` (date format "%Y%m%d%H%M%S") and backups were pushed to GCS bucket `gs://postgresql/backups`
The created backup named `20220512154510-12abc3d4e5` can be restored from the specified GCS bucket name.

See the example below where the restore parameters RESTORE_BACKUP and BACKUP_NAME have been added to the master database on the `docker-compose-example.yml` file:

```
version: "3.7"
secrets:
  db_replica_password:
    external: true
  db_password:
    external: true
  gcp_credentials:
    external: true

services:
  pg_master:
    image: mesoform/postgres-ha:13-latest
    volumes:
      - pg_data:/var/lib/postgresql/data
    environment:
      - PG_MASTER=true
      - POSTGRES_USER=testuser
      - POSTGRES_PASSWORD_FILE=/run/secrets/db_password
      - POSTGRES_DB=testdb
      - PGPORT=5432
      - PG_REP_USER=testrep
      - PG_REP_PASSWORD_FILE=/run/secrets/db_replica_password
      - HBA_ADDRESS=10.0.0.0/8
      - BACKUPS=true
      - STORAGE_BUCKET=gs://postgresql/backups
      - GCP_CREDENTIALS=/run/secrets/gcp_credentials
      - RESTORE_BACKUP=true
      - BACKUP_NAME=20220512154510-12abc3d4e5
    ports:
      - "5432:5432"
    secrets:
      - source: db_replica_password
        uid: "70"
        gid: "70"
        mode: 0550
      - source: db_password
        uid: "70"
        gid: "70"
        mode: 0550
      - source: gcp_credentials
        uid: "70"
        gid: "70"
        mode: 0550
    networks:
      database:
        aliases:
          - pg_cluster
    deploy:
      placement:
        constraints:
        - node.labels.type == primary
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "zabbix"]
      interval: 3800s
      timeout: 60s
      retries: 3
      start_period: 60s        
  pg_replica:
    image: mesoform/postgres-ha:13-latest
    volumes:
      - pg_replica:/var/lib/postgresql/data
    environment:
      - PG_SLAVE=true
      - POSTGRES_USER=testuser
      - POSTGRES_PASSWORD_FILE=/run/secrets/db_password
      - POSTGRES_DB=testdb
      - PGPORT=5432
      - PG_REP_USER=testrep
      - PG_REP_PASSWORD_FILE=/run/secrets/db_replica_password
      - PG_MASTER_HOST=pg_master  # This needs to be the swarm node private IP instead of the service name (pg_master) which resolves to the service IP
      - HBA_ADDRESS=10.0.0.0/8
    secrets:
      - source: db_replica_password
        uid: "70"
        gid: "70"
        mode: 0550
      - source: db_password
        uid: "70"
        gid: "70"
        mode: 0550
    networks:
      database:
        aliases:
          - pg_cluster
    deploy:
      placement:
        constraints:
        - node.labels.type == secondary
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "zabbix"]
      interval: 3800s
      timeout: 60s
      retries: 3
      start_period: 60s

networks:
  database: {}

volumes:
  pg_data: {}
  pg_replica: {}

```

Run with:

```shell script
docker stack deploy -c docker-compose-restore.yml restore_pg13
```
Master database container logs:
```
root@restore:~$ sudo docker logs 9034a5c761g3
Using password file
Detected running as root user, changing to postgres
Using password file
Initialising wal-g restore script variables
Restoring backup 20220512154510-12abc3d4e5
GOOGLE_APPLICATION_CREDENTIALS: /run/secrets/gcp_credentials
WALG_GS_PREFIX: gs://postgresql/backups/20220512154510-12abc3d4e5
PGUSER: testuser
PGDATABASE: testdb
PGPORT: 5432
Running command /usr/local/bin/wal-g backup-fetch /var/lib/postgresql/data LATEST
...
```
**Important:** This is as a one-off process to restore a database backup. If restore parameters RESTORE_BACKUP and BACKUP_NAME are kept in a compose file the restore process will be performed on each restart.

When restoring a backup the database environment parameters and database instance type (MASTER/SLAVE or STANDALONE instance) should be the same as the one from which the backup was taken. I.e: A backup taken on a master/slave setup can't be restored on a standalone instance.

## How to upgrade to latest PostgreSQL version

The process consists of running `pg_dumpall` on the current database to get a SQL file containing all data and then importing the dump to an empty standalone postgresql  database running the latest version. Once the import completes stop the database to be upgraded and switch the database volume data and image on the `docker-compose` file with the upgraded one before bringing it back up.

#### Pre-upgrade process

Stop the database to be upgraded and take a consistent copy of the data volume which will later be erased.

#### Upgrade process

1) Run `pg_dumpall` on the database to be upgraded to get a SQL file containing all database data:

```
root@testapp:~# docker exec -it ab1cdef23g4h pg_dumpall -U testuser > /backups/dump-testapp_db_data.sql
```

2) Deploy a new PostgreSQL v13 database (with the same database name and username) on an empty volume which will be used to import the data dump taken on the database to be upgraded:

```
root@testapp:~/testapp$ cat docker-compose.pg13.yml 
version: "3.7"

volumes:
  pg13_data:
    name: zones/volumes/pg13_data
    driver: zfs
secrets:
  db_password:
    external: true
  gcp_credentials:
    external: true
networks:
  database: {}

services:
  pg13:
    image: mesoform/postgres-ha:13-latest
    volumes:
      - pg13_data:/var/lib/postgresql/data
    environment:
      - POSTGRES_DB=testdb
      - POSTGRES_USER=testuser
      - PGPORT: 5432
      - POSTGRES_PASSWORD_FILE=/run/secrets/db_password 
      - HBA_ADDRESS=10.0.0.0/8
      - BACKUPS=true
      - STORAGE_BUCKET=gs://backups/postgres/testdb
      - GCP_CREDENTIALS=/run/secrets/gcp_credentials
    secrets:    
      - source: db_password
      - source: gcp_credentials
    deploy:
      placement:
        constraints:
          - node.labels.storage == primary
```
```
root@testapp:~# docker stack deploy -c docker-compose.pg13.yml pg13db
```

3) Import the data dump taken on the first step to the new database:

```
root@testapp:~/testapp$ sudo docker exec -i bc2defg34h5i psql -U testuser -d testdb < /backups/dump-testapp_db_data.sql
```

4) Verify that the tables of `testuser` have been imported:

E.g:
```
testapp-# \dt
               List of relations
 Schema |         Name         | Type  | Owner  
--------+----------------------+-------+---------
 public | users                | table | testuser
 public | roles                | table | testuser
 public | status               | table | testuser
 public | systems              | table | testuser
(4 rows)

testapp-# \q
```

5) Stop database to be upgraded and remove data volume with old data structure (we still have a backup copy in case something goes wrong):

```
root@testapp:~# docker stack rm testapp
```
```
root@testapp:~# rm -rf /volumes/testapp_db_data
```

6) Move upgraded data volume from the PostgreSQL v13 database to the old database data volume:

```
root@testapp:~# mv -v /volumes/testapp_db13_data /volumes/testapp_db_data/
```

7) Edit the original `docker-compose` file to update the database postgres image to v13 and gcp parameters to backup to cloud storage:

```
root@testapp:~/testapp$ cat docker-compose.yml
version: "3.7"

volumes:
  app_data:
    name: zones/volumes/testapp_data
    driver: zfs
  db_data:
    name: zones/volumes/testapp_db_data
    driver: zfs
  db_replica_data:
    name: zones/volumes/testapp_db_replica_data
    driver: zfs
secrets:
  testapp_db_password:
    external: true
  testapp_db_replica_password:
    external: true
  gcp_credentials:
    external: true
networks:
  default:

services:
  app:
    image: testapp/testapp-prod:1.0.0
    volumes:
      - app_data:/testapp
    ports:
      - "1234:1234"
    environment:
      - DB_HOST=db
      - DB_PORT_NUMBER=5432
      - DB_NAME=testdb
      - DB_USERNAME=testuser
    deploy:
      placement:
        constraints:
          - node.labels.storage == primary
  db:
    image: mesoform/postgres-ha:13-latest
    volumes:
      - db_data:/var/lib/postgresql/data
    environment:
      - PG_MASTER=true
      - POSTGRES_DB=testdb
      - PGPORT=5432
      - POSTGRES_USER=testuser
      - POSTGRES_PASSWORD_FILE=/run/secrets/testapp_db_password
      - PG_REP_USER=testrep
      - PG_REP_PASSWORD_FILE=/run/secrets/testapp_db_replica_password
      - HBA_ADDRESS=10.0.0.0/8
      - BACKUPS=true
      - STORAGE_BUCKET=gs://backups/postgres/testapp
      - GCP_CREDENTIALS=/run/secrets/gcp_credentials
    secrets:
      - testapp_db_password
      - testapp_replica_password
      - gcp_credentials
    deploy:
      placement:
        constraints:
          - node.labels.storage == primary
  db_replica:
    image: mesoform/postgres-ha:13-latest
    volumes:
      - db_replica_data:/var/lib/postgresql/data
    environment:
      - PG_SLAVE=true
      - POSTGRES_DB=testdb
      - PGPORT=5432
      - POSTGRES_USER=testuser
      - POSTGRES_PASSWORD_FILE=/run/secrets/testapp_db_password
      - PG_REP_USER=testrep
      - PG_REP_PASSWORD_FILE=/run/secrets/testapp_db_replica_password
      - HBA_ADDRESS=10.0.0.0/8
      - PG_MASTER_HOST=db
    secrets:
      - testapp_db_password
      - testapp_db_replica_password
    deploy:
      placement:
        constraints:
          - node.labels.storage == secondary
```

8) Deploy application using the edited compose configuration, check status and verify the application is working as expected.

```
docker stack deploy -c docker-compose.yml testapp
```
```
root@testapp:~$ sudo docker stack ps testapp
ID                  NAME                   IMAGE                                                          NODE                DESIRED STATE       CURRENT STATE          ERROR               PORTS                       
wklerj2344jd        testapp_db_replica.1   mesoform/postgres-ha:13-latest                                 secondary           Running             Running 2 minutes ago                       
lclkerk34kl3        testapp_db.1           mesoform/postgres-ha:13-latest                                 primary             Running             Running 2 minutes ago                       
mfdk34jll34k        testapp_app.1          testapp/testapp-prod:1.0.0                                     primary             Running             Running 2 minutes ago  
```

## Official stuff

- [Contributing](https://github.com/mesoform/documentation/blob/main/CONTRIBUTING.md)
- [Code of Conduct](https://github.com/mesoform/documentation/blob/main/CODE_OF_CONDUCT.md)
- [Licence](https://github.com/mesoform/postgres-ha/blob/main/LICENSE)
- [Contact](https://mesoform.com/contact)