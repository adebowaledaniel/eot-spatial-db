# eot-spatial-db

CDE Spatial Database <br />
End of Term Project<br />
<br />
To restore database <br />
psql -U username -f backup.sql<br />
or <br />
CREATE DATABASE newdb;<br />
pg_restore --dbname=newdb --verbose c:\pgbackup\dvdrental.tar // in CMD<br />
Extensions<br />
PostGIS<br />
PostGIS Topology<br />
PgRouting<br />
