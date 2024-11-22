#!/bin/sh

cd /var/lib/jellyfin/data

### Recover library.db
echo "### Recover library.db"
sqlite3 library.db ".recover" | sqlite3 library-recovered.db

#2. We will now check the integrity of our recovered database (as above) using
echo "#2. We will now check the integrity of our recovered database (as above) using"
sqlite3 library-recovered.db "PRAGMA integrity_check"

#3. Make a copy of both library.db and library-recovered.db
echo "#3. Make a copy of both library.db and library-recovered.db"
cp library.db library.db.bak
cp library-recovered.db library-recovered.db.bak

#4. Rename library.db to library.old
echo "#4. Rename library.db to library.old"
mv library.db library.old

#5. Rename library-recovered.db to library.db
echo "#5. Rename library-recovered.db to library.db"
mv library-recovered.db library.db

#6. Restart Jellyfin Server
echo "#6. Restart Jellyfin Server"
docker restart jellyfin
