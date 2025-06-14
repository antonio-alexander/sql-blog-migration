#!/bin/ash

# execute any pre-init scripts
for i in /scripts/pre-init.d/*sh
do
	if [ -e "${i}" ]; then
		echo "[i] pre-init.d - processing $i"
		. "${i}"
	fi
done

if [ -d "/run/mysqld" ]; then
	echo "[i] mysqld already present, skipping creation"
	chown -R mysql:mysql /run/mysqld
else
	echo "[i] mysqld not found, creating...."
	mkdir -p /run/mysqld
	chown -R mysql:mysql /run/mysqld
fi

if [ -d /var/lib/mysql/mysql ]; then
	echo "[i] MySQL directory already present, skipping creation"
	chown -R mysql:mysql /var/lib/mysql
else
	echo "[i] MySQL data directory not found, creating initial DBs"

	chown -R mysql:mysql /var/lib/mysql

	mysql_install_db --user=mysql --ldata=/var/lib/mysql > /dev/null

	if [ "$MYSQL_ROOT_PASSWORD" = "" ]; then
		MYSQL_ROOT_PASSWORD=`pwgen 16 1`
		echo "[i] MySQL root Password: $MYSQL_ROOT_PASSWORD"
	fi

	MYSQL_DATABASE=${MYSQL_DATABASE:-""}
	MYSQL_USER=${MYSQL_USER:-""}
	MYSQL_PASSWORD=${MYSQL_PASSWORD:-""}

	tfile=`mktemp`
	if [ ! -f "$tfile" ]; then
	    return 1
	fi

	cat << EOF > $tfile
USE mysql;
FLUSH PRIVILEGES ;
GRANT ALL ON *.* TO 'root'@'%' identified by '$MYSQL_ROOT_PASSWORD' WITH GRANT OPTION ;
GRANT ALL ON *.* TO 'root'@'localhost' identified by '$MYSQL_ROOT_PASSWORD' WITH GRANT OPTION ;
SET PASSWORD FOR 'root'@'localhost'=PASSWORD('${MYSQL_ROOT_PASSWORD}') ;
DROP DATABASE IF EXISTS test ;
FLUSH PRIVILEGES ;
EOF

	if [ "$MYSQL_DATABASE" != "" ]; then
	    echo "[i] Creating database: $MYSQL_DATABASE"
		if [ "$MYSQL_CHARSET" != "" ] && [ "$MYSQL_COLLATION" != "" ]; then
			echo "[i] with character set [$MYSQL_CHARSET] and collation [$MYSQL_COLLATION]"
			echo "CREATE DATABASE IF NOT EXISTS \`$MYSQL_DATABASE\` CHARACTER SET $MYSQL_CHARSET COLLATE $MYSQL_COLLATION;" >> $tfile
		else
			echo "[i] with character set: 'utf8' and collation: 'utf8_general_ci'"
			echo "CREATE DATABASE IF NOT EXISTS \`$MYSQL_DATABASE\` CHARACTER SET utf8 COLLATE utf8_general_ci;" >> $tfile
		fi
	 	if [ "$MYSQL_USER" != "" ]; then
			echo "[i] Creating user: $MYSQL_USER with password $MYSQL_PASSWORD"
			echo "GRANT ALL ON \`$MYSQL_DATABASE\`.* to '$MYSQL_USER'@'%' IDENTIFIED BY '$MYSQL_PASSWORD';" >> $tfile
			echo "[i] Creating user: $MYSQL_USER with password $MYSQL_PASSWORD"
			echo "GRANT ALL ON \`$MYSQL_DATABASE\`.* to '$MYSQL_USER'@'localhost' IDENTIFIED BY '$MYSQL_PASSWORD';" >> $tfile
	    fi
	fi

	/usr/bin/mysqld --user=mysql --bootstrap --verbose=0 --skip-name-resolve --skip-networking=0 < $tfile
	rm -f $tfile

	echo
	echo 'MySQL init process done. Ready for start up.'
	echo

	echo "exec /usr/bin/mysqld --user=mysql --console --skip-name-resolve --skip-networking=0" "$@"
fi

# execute any pre-exec scripts
for i in /scripts/pre-exec.d/*sh
do
	if [ -e "${i}" ]; then
		echo "[i] pre-exec.d - processing $i"
		. ${i}
	fi
done

exec /usr/bin/mysqld --user=mysql --console --skip-name-resolve --skip-networking=0 $@ &
mysql_pid=$!

# Ping mysql until it's up and running after starting
until mysqladmin -uroot -p${MYSQL_ROOT_PASSWORD} ping >/dev/null 2>&1; do
    sleep 0.2
done

if [[ ! -z "`mysql -u$MYSQL_USER -p$MYSQL_PASSWORD -r -e "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='sql_blog_migration'"`" ]];
then
  mysql -u${MYSQL_USER} -p${MYSQL_PASSWORD} < /sql_blog_migration/$EMPLOYEES_SQL
else
  echo "[i] sql_blog_migration database already present, skipping creation"
fi

for f in /docker-entrypoint-initdb.d/*; do
	case "$f" in
		*.sql)    echo "$0: running $f"; mysql -u${MYSQL_USER} -p${MYSQL_PASSWORD} < "$f"; echo ;;
		*.sql.gz) echo "$0: running $f"; gunzip -c "$f" | mysql -u${MYSQL_USER} -p${MYSQL_PASSWORD} < "$f"; echo ;;
		*)        echo "$0: ignoring or entrypoint initdb empty $f" ;;
	esac
	echo
done

# execute any post-exec scripts
for i in /scripts/post-exec.d/*sh
do
	if [ -e "${i}" ]; then
		echo "[i] post-exec.d - processing $i"
		. ${i}
	fi
done

# migrate database
if [ "$AUTOMATIC_MIGRATION" == "true" ]
then
    cd /sql_blog_migration/migration
    echo ...automatic migration enabled, attempting to migrate
    goose mysql "$MYSQL_USER:$MYSQL_PASSWORD@/sql_blog_migration?parseTime=true&&multiStatements=true" --table employees_goose_db_version up
fi

wait $mysql_pid
