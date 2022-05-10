TROUBLESHOOTING
---------------
### Missing `PGUSER` variable causes `FATAL:  role "postgres" does not exist`

```shell
zab_database.1.7igtvb6pbnuh@lab1    | PGUSER: 
zab_database.1.7igtvb6pbnuh@lab1    | PGDATABASE: my-database
zab_database.1.7igtvb6pbnuh@lab1    | PGPORT: 5432
zab_database.1.7igtvb6pbnuh@lab1    | Running command /usr/local/bin/wal-g backup-push /var/lib/postgresql/data 
zab_database.1.7igtvb6pbnuh@lab1    | INFO: 2021/09/05 16:40:44.456857 Doing full backup.
zab_database.1.7igtvb6pbnuh@lab1    | 2021-09-05 16:40:44.467 UTC [85] FATAL:  role "postgres" does not exist
zab_database.1.7igtvb6pbnuh@lab1    | ERROR: 2021/09/05 16:40:44.467938 FATAL: role "postgres" does not exist (SQLSTATE 28000)
zab_database.1.7igtvb6pbnuh@lab1    | ERROR: 2021/09/05 16:40:44.468146 Failed to connect using provided PGHOST and PGPORT, trying localhost:5432
zab_database.1.7igtvb6pbnuh@lab1    | ERROR: 2021/09/05 16:40:44.483088 Connect: postgres connection failed: dial tcp 127.0.0.1:5432: connect: connection refused
```
#### Solution
Set `PGUSER=mydbuser`, or whaterver is appropriate for your database
