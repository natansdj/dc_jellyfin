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
