#!/bin/bash

echo "$(date +%Y-%m-%d\ %H:%M:%S) Taking database base backup and uploading it to cloud storage"
/usr/local/scripts/walg_caller.sh backup-push $PGDATA
