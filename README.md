jellyfin configuration for local

###Bugfix for malformed database/database corrupt part1

For future reference of anyone who lands here after searching for how to fix the "database disk image is malformed" error.

One way to fix this is to (manually) rescan the indexes with missing or invalid entries.

My log file:
Corrupt: SQLitePCL.pretty.SQLiteException: database disk image is malformed
at SQLitePCL.pretty.SQLiteException.Throw(Int32 rc, Int32 extended, String msg)
... etc ...

Shut down Jellyfin!

Navigate to database dir and make a copy of the library.db to a temp location.
C:...\jellyfin\data>copy library.db C:\Temp
1 file(s) copied.
C:...\jellyfin\data>cd \Temp

Assuming sqlite3.exe is in your %PATH%, run an integrity check:
C:\Temp>sqlite3 library.db "PRAGMA integrity_check;"
row 237908 missing from index idx_ItemValues7
row 237908 missing from index idx_ItemValues6
row 6653 missing from index idx_TypeTopParentId9
row 56115 missing from index idx_TypeTopParentIdStartDate

If the only problem is missing entries from indexes, just drop & rebuild them (reindex):
C:\Temp>sqlite3 library.db "reindex idx_ItemValues7;"
C:\Temp>sqlite3 library.db "reindex idx_ItemValues6;"
C:\Temp>sqlite3 library.db "reindex idx_TypeTopParentId9;"
C:\Temp>sqlite3 library.db "reindex idx_TypeTopParentIdStartDate;"

Check the integrity again:
C:\Temp>sqlite3 library.db "PRAGMA integrity_check;"
ok

If it says "ok", make another backup of the original library.db in the jellyfin/data directory then copy in the repaired one from the /Temp location.

Start jellyfin and run a scan or whatever was erroring out, and if you're lucky, you've fixed it!

###Bugfix for malformed database/database corrupt part2
Clone database library.db, if there are other issues during integrity check from part1

connect to SQLite and specify a database to use:

sqlite3 library.db
Once connected, run the following code to clone that database:

.clone library2.db
finish cloned the library.db database to a file called library2.db.

## Production-Safe Backup and Restore Runbook

This repo includes scripted manual backup and restore for the NUC14 Jellyfin Docker deployment.

Scripts:
- `backup/backup_jellyfin.sh`
- `backup/restore_jellyfin.sh`

### 1) Pre-Flight (before backup or restore)

1. Ensure Docker is healthy and the Jellyfin container name is `jellyfin`.
2. Ensure host mount paths are available:
	- `/mnt/lxc/jellyfin_data/etc`
	- `/mnt/lxc/jellyfin_data/lib`
	- `/mnt/lxc/jellyfin_data/cache`
	- `/mnt/lxc/jellyfin_data/log`
3. Ensure free disk space in backup destination.

### 2) Backup (production-safe)

Run from repo root:

```bash
./backup/backup_jellyfin.sh
```

Optional:

```bash
# Label backup name with version tag
./backup/backup_jellyfin.sh 10.10.7

# Store backups on NAS or alternate disk
BACKUP_ROOT=/media/nuc14/NTH_NAS_1/jellyfin_backups ./backup/backup_jellyfin.sh
```

What the script does:
1. Stops Jellyfin container.
2. Copies data/config/cache/log from host bind paths.
3. Writes metadata (`BACKUP_INFO.txt`).
4. Creates `.tar.gz` archive and `.sha256` checksum.
5. Starts Jellyfin again (unless `KEEP_STOPPED=1`).

### 3) Restore (official manual flow automation)

Restore from snapshot folder:

```bash
./backup/restore_jellyfin.sh backup/snapshots/jellyfin.YYYYMMDDHHMMSS_VERSION
```

Restore from archive:

```bash
./backup/restore_jellyfin.sh backup/snapshots/jellyfin.YYYYMMDDHHMMSS_VERSION.tar.gz
```

Optional:

```bash
# Leave Jellyfin stopped after restore for inspection
KEEP_STOPPED=1 ./backup/restore_jellyfin.sh <backup-path>

# Skip cache and log restore
RESTORE_CACHE=0 RESTORE_LOG=0 ./backup/restore_jellyfin.sh <backup-path>
```

What the restore script does:
1. Stops Jellyfin container.
2. Moves current directories to timestamped `.bak` paths.
3. Copies backup `data` and `config` to active paths.
4. Restores `cache` and `log` if available (optional).
5. Starts Jellyfin again (unless `KEEP_STOPPED=1`).

### 4) Post-Restore Verification

1. Confirm container is running:

```bash
docker ps --filter name=jellyfin
```

2. Check recent logs for database or migration errors:

```bash
docker logs --tail 200 jellyfin
```

3. Validate from web UI:
	- Login works
	- Libraries and users are present
	- Playback test succeeds
	- Dashboard has no active fatal errors

### 5) Rollback Checklist

Use this if restore result is bad or incompatible:

1. Stop Jellyfin:

```bash
docker stop jellyfin
```

2. Identify `.bak` folders created during restore in:
	- `/mnt/lxc/jellyfin_data/lib.bak.<timestamp>`
	- `/mnt/lxc/jellyfin_data/etc.bak.<timestamp>`
	- (optional) cache/log `.bak` folders

3. Move restored active directories out of the way.
4. Move chosen `.bak` directories back to active names:
	- `lib.bak.<timestamp>` -> `lib`
	- `etc.bak.<timestamp>` -> `etc`
5. If needed, run the same Jellyfin version as the backup source.
6. Start Jellyfin and validate:

```bash
docker start jellyfin
docker logs --tail 200 jellyfin
```

Operational note:
- Keep at least one known-good backup before upgrades.
- Test restore flow on a maintenance window before major version jumps.

### 6) Nightly Automation (Cron or systemd timer)

Retention is built into the backup script via `RETENTION_COUNT` (default `14`).

Healthcheck script for actionable alerts:
- `backup/healthcheck_backup.sh`
- Returns non-zero if latest backup artifacts are missing or checksum validation fails.

Cron example (run nightly at 02:30, keep 14 backups):

```cron
30 2 * * * cd /home/nuc14/Documents/jellyfin && RETENTION_COUNT=14 ./backup/backup_jellyfin.sh >> /home/nuc14/Documents/jellyfin/backup/cron-backup.log 2>&1
```

Cron with immediate healthcheck:

```cron
40 2 * * * cd /home/nuc14/Documents/jellyfin && ./backup/healthcheck_backup.sh >> /home/nuc14/Documents/jellyfin/backup/cron-backup.log 2>&1
```

systemd example:

`/etc/systemd/system/jellyfin-backup.service`

```ini
[Unit]
Description=Nightly Jellyfin backup
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
User=nuc14
WorkingDirectory=/home/nuc14/Documents/jellyfin
Environment=RETENTION_COUNT=14
ExecStart=/home/nuc14/Documents/jellyfin/backup/backup_jellyfin.sh
ExecStartPost=/home/nuc14/Documents/jellyfin/backup/healthcheck_backup.sh
```

`/etc/systemd/system/jellyfin-backup.timer`

```ini
[Unit]
Description=Run Jellyfin backup nightly

[Timer]
OnCalendar=*-*-* 02:30:00
Persistent=true

[Install]
WantedBy=timers.target
```

Enable and start timer:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now jellyfin-backup.timer
sudo systemctl list-timers jellyfin-backup.timer
```
