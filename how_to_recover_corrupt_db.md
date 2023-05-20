## Shutdown Jellyfin
navigate to library path /var/lib/jellfin


## Recover library.db
What we need to do is dump all data from the database to a text file and then reload this back to another freshly created database. This can be done via a single command using the SQLite command line editor.

Run the following command line:



1. sqlite3 library.db ".recover" | sqlite3 library-recovered.db
(this may take a while to run so please wait for it to finish)



2. We will now check the integrity of our recovered database (as above) using



sqlite3 library-recovered.db "PRAGMA integrity_check"



This should return an integrity_check back of "OK" with no errors reported. If errors are reported please report this in the forum before proceeding to Reset the Library Database. If OK and no errors are reported continue with step 3.



3. Make a copy of both library.db and library-recovered.db

4. Rename library.db to library.old

5. Rename library-recoved.db to library.db

6. Restart Emby Server

Check you server log for SQLite errors and only continue to the next step if needed
