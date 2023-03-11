#!/bin/ash

# Migrate database
if [ "$AUTOMATIC_MIGRATION" == "true" ]
then
    cd /sql_blog_migration
    echo ...automatic migration enabled, attempting to migrate
    goose mysql "root:$MYSQL_ROOT_PASSWORD@/sql_blog_migration?parseTime=true&&multiStatements=true" up
fi
