# sql-blog-migration (github.com/antonio-alexander/go-blog-data-consistency)

This is a companion repository for an article I'll eventually write, the goal of this repository is to try to show some solutions for database migration and any lessons I learn along the way.

> DISCLAIMER: this is focused on MySQL; there may be caveats for other database technologies

Migration is this strange process where your application that's using the database, or the database itself needs to undergo changes to ensure it's maintain-ability. A migration is by definition NECCESSARY: something has occured where the data HAS to change. One doesn't simply do a migration, not all migrations are painful, some (if done correctly) are just tedius. Here are some situations where migrations are required:

> For purposes of this discussion, we'll assume that although a migration can be reverted, the idea is that in practice, you'll never revert a successful migration. As such, even if a migration is backwards compatible it's not a focus. It's one thing if you delay migration (maybe it's an offline database, or you want to migrate when you update the software), but migration is expected to be neccessary and never undone (if successful).

- You've added new data to a given table
- You've updated the data type of a given column
- You've modified a data type used as a foreign key
- You've added new indexes to a given table
- You've created new unique constraints for a given table

I also want to keep "offline" databases in mind; for purposes of this discussion an "offline" database is one that isn't being actively mainained. It could be a database used by an application that's updated at an irregular cadence (e.g., when the user wants to upgrade) or its a database that generally runs without any internet connectivity for extended periods of time and can only be updated when DBAs (database administrators) can get enough time to do the migration. Offline databases are a bit unique because the migration almost HAS to be automated because you have to do it over and over again.

## Bibliography

- [https://github.com/pressly/goose](https://github.com/pressly/goose)
- [https://dev.mysql.com/doc/refman/8.0/en/lock-tables.html](https://dev.mysql.com/doc/refman/8.0/en/lock-tables.html)
- [Semantic Versioning](https://semver.org/)
- [https://dev.mysql.com/doc/refman/8.0/en/alter-table.html](https://dev.mysql.com/doc/refman/8.0/en/alter-table.html)
- [https://stackoverflow.com/questions/9783636/unlocking-tables-if-thread-is-lost](https://stackoverflow.com/questions/9783636/unlocking-tables-if-thread-is-lost)

## Getting Started

Unfortunately, this respository is NOT simple, BUT a lot of the work has already been done for you. I've tried to simplify some of the common operations you'll want to do (so you don't have to figure it out). From the root of the repository, you can do the following to setup your environment (it's a strong assumption that you have docker installed):

```sh
make check-goose
make build
make run
```

This will build and run the customer mysql image included in this repository; if you're curious about what the make commands are doing, you can look at the [Makefile](./Makefile). When the mysql image is running, you can execute one of the following commands to:

Interactive MySQL shell (find credentials in [.env](.env) and [docker-compose.yml](./docker-compose.yml)):

```sh
docker exec -it mysql mysql -u<USERNAME> -p<PASSWORD>
```

If you'd like to attempt to use goose to perform migration, you can enter one (or a combination of) these commands. To get the migration status you can run:

```sh
make goose-status
```

or

```sh
docker exec -it mysql goose mysql "root:<PASSWORD>@tcp(localhost:3306)/sql_blog_migration?parseTime=true&&multiStatements=true" status
```

The connection strings used above are a bit complex/esoteric (and required), just copy+paste them.

## Data Architecture

This is a much longer conversation, but we can attempt to paraphrase it here; without a conversastion about data architecture the motivations, mitigations and overall choices that cause migration. In general, you want to have enough forsight such that as you __need__ to change your data, you can make forward compatible changes to it. Data, unlike API/contracts, is almost ALWAYS forward compatible. Once you modify the schema (how the data is organized) and add/change data (not necessarily delete data under some circumstances) you've created a change that you can't undo without making a destructive change; this is my underlying reason why changes to the schema/data are ONLY forward compatible.

I won't lie to you and tell you that you can mitigate data/schema changes such that you never have to migrate but in showing some examples of data and schema changes we can provide some context to help you better know and understand when a migration is required. Let's start with this contract; we'll start with JSON and then I'll show the same with SQL.

```json
{
    "employee" : {
        "id": "86fa2f09-d260-11ec-bd5d-0242c0a8e002",
        "first_name": "John",
        "last_name": "Connor",
        "email_address": "John.Connor@sky.net",
        "last_updated": 1652417242000,
        "last_updated_by": "sql-blog-migration",
        "version": 1
    }
}
```

What if you changed the id field from a string to an int64?
> This is a change that completely breaks the contract (meaning you need a code change or some facade-like functionality). An int64 is fundamentally a different data type than a string. Even though a uuid/guid CAN be represented as a string OR an int64; generally that data change is a big deal (even though the values are the same).

What if you added a birth date field?

> Added a birthdate field is generally forward-compatible, you can add it without having to break the contract, you simply can't revert the changes once new data has been added or existing data has been mutated without destroying data. It's also important to note that even though you've added a new field it's default value (0) may break any logic you've designed around it. So even though it's a forward-compatible change, you have to ensure that the logic behind it can handle the default value.

What if you changed the last_updated field from an int64 to a datetime?

> This is an interesting change because it really depends on how it's being used. If you had a finite number of consumers and you knew that all of the consumers were either using ORM or were ignoring the data altogether, you could just modify it and its consumers would be none-the-wiser, or they'd simply have to change their configuration. It's not that it's NOT a breaking change, only that the effects of the change can be mititgated without code changes; you'll need synchronous deployment of the configuration changes, but reversion is simple.

What if you wanted to remove the first and last name fields and replace it with a first_last_name field?

> This is a proof of concept/idea; it's incredibly impractical and reduces the functionality of your integration (you can't refer to anyone by their first name and you have to split by spaces and hope they haven't included three names etc). It's interesting because it's very clear how you'd "migrate" the data: you'd have to create a name field, concatenate the first_name and last_name fields with a space and inject that into the new field and then delete the first_name and last_name fields.

There are some tricks...err...strategies we can use to mitigate some of the above changes; especially when it comes to databases (e.g., views can provide a high-level of abstraction to mitigate fallout for breaking data changes), but before we get into those strategies, it's important to qualify if it makes sense to go through all this effort. [Semantic Versioning](https://semver.org/) dictates that when you introduce a breaking change you increment the major version number (communicating that this version is NOT the same as another version); incrementing a major version number has three main implications:

- You have to support two major versions (e.g., v1 and v2)
- You have to deploy two major versions (e.g., v1 and v2)
- You have to modify your git strategy to use trunking or have a LTS release branch for v1 (as v1 and v2 would most likely diverge)

Maybe your release is early enough that the fallout of implementing a breaking change but not incrementing the major version isn't that big a deal (i.e., it affects mostly testers or a few consumers who are ok with the change) or maybe having to use twice the resources and pay twice the money isn't an option or maybe you simply don't have the bandwidth for the additional overhead. Sometimes being incredibly orthodox about versioning and breaking contracts IS NOT PRACTICAL.

Alternatively, you have the option of deprecation: saying that this "feature" or "version" will no longer be supported and will eventually be removed. This option is reasonable (sometimes):

- instead of "changing" the id field, you could create a new field called "id_int64", migrate everyone over to using it, then deprecate the "id" field, and then rename the "id_int64" field the "id" field and then you can deprecate all versions that referenced the "id" field as a string.
- the last_updated field is an audit field and shouldn't be used by anything that a user interacts with, you could say that it's changes are not covered under versioning
- adding a birthdate could have a default birth date which is an established magic number which doesn't generate logic errors

With that out of the way, how would this look in MySQL?

```sql
-- DROP DATABASE IF EXISTS sql_blog_migration;
CREATE DATABASE IF NOT EXISTS sql_blog_migration;

USE sql_blog_migration;

-- DROP TABLE IF EXISTS employees;
CREATE TABLE IF NOT EXISTS employees (
    id VARCHAR(36) PRIMARY KEY NOT NULL DEFAULT (UUID()),
    first_name VARCHAR(50) DEFAULT '',
    last_name VARCHAR(50) DEFAULT '',
    email_address VARCHAR(50) NOT NULL,
    aux_id BIGINT AUTO_INCREMENT,
    version INT NOT NULL DEFAULT 1,
    last_updated DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    last_updated_by VARCHAR(25) NOT NULL DEFAULT CURRENT_USER,
    INDEX(aux_id),
    UNIQUE(email_address)
) ENGINE = InnoDB;
```

What if you changed the id field from a string to an int64?
> This would involve a schema change (if you're curious about uuids you can look into [https://github.com/antonio-alexander/sql-blog-uuid](https://github.com/antonio-alexander/sql-blog-uuid)) We'd have to do a funamental change in the table and migrate the data; this could probably be done in a few commands, the new schema is below:

```sql
CREATE TABLE IF NOT EXISTS employees (
    -- KIM: if you're not running at least MYSQL 8.0 you may not be able to have a default
    -- REFERENCE: https://dev.mysql.com/doc/refman/8.0/en/data-type-defaults.html
    id BINARY(16) PRIMARY KEY NOT NULL DEFAULT (unhex(replace(uuid(),'-',''))),
    last_name TEXT DEFAULT '',
    email_address TEXT NOT NULL,
    aux_id BIGINT AUTO_INCREMENT,
    version INT NOT NULL DEFAULT 1,
    last_updated DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    last_updated_by TEXT NOT NULL DEFAULT CURRENT_USER,
    INDEX(aux_id),
    UNIQUE(email_address)
) ENGINE = InnoDB;
```

What if you added a birth date field?

> Adding a birthdate field is again, fairly straighforward and can be done without any disruption of data; just keep in mind what I've said about breaking the existing data contracts:

```sql
CREATE TABLE IF NOT EXISTS employees (
    id VARCHAR(36) PRIMARY KEY NOT NULL DEFAULT (UUID()),
    first_name VARCHAR(50) DEFAULT '',
    last_name VARCHAR(50) DEFAULT '',
    email_address VARCHAR(50) NOT NULL,
    -- KIM: birth_date can be null to represent that it hasn't been set
    birth_date DATETIME,
    aux_id BIGINT AUTO_INCREMENT,
    version INT NOT NULL DEFAULT 1,
    last_updated DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    last_updated_by VARCHAR(25) NOT NULL DEFAULT CURRENT_USER,
    INDEX(aux_id),
    UNIQUE(email_address)
) ENGINE = InnoDB;
```

What if you wanted to remove the first and last name fields and replace it with a first_last_name field?

> This kind of change isn't super complicated, you'd just remove the first_name and last_name fields and replace them with a new field; this is mainly for proof-of-concept (again) and is completely impractical by any stretch of the imagination. A single field for name is significantly less flexible; it robs any integration of your API the ability to refer to an employee by their first name and there are also so performance implications regarding the size of the column in general. Also having a single field refer to TWO pieces of data also breaks the table's [normalization](https://en.wikipedia.org/wiki/Database_normalization)

```sql
CREATE TABLE IF NOT EXISTS employees (
    id VARCHAR(36) PRIMARY KEY NOT NULL DEFAULT (UUID()),
    -- REMOVED:  first_name VARCHAR(50) DEFAULT '',
    -- REMOVED:  last_name VARCHAR(50) DEFAULT '',
    first_last_name VARCHAR(100) DEFAULT '',
    email_address VARCHAR(50) NOT NULL,
    aux_id BIGINT AUTO_INCREMENT,
    version INT NOT NULL DEFAULT 1,
    last_updated DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    last_updated_by VARCHAR(25) NOT NULL DEFAULT CURRENT_USER,
    INDEX(aux_id),
    UNIQUE(email_address)
) ENGINE = InnoDB;
```

In regards to data architecture, I'll show one strategy that can be used in MySQL (or any other database that supports views) to create a kind of data facade to shield your consumers from certain changes in data:

```sql
-- DROP DATABASE IF EXISTS sql_blog_migration;
CREATE DATABASE IF NOT EXISTS sql_blog_migration;

USE sql_blog_migration;

-- DROP TABLE IF EXISTS employees;
CREATE TABLE IF NOT EXISTS employees (
    id VARCHAR(36) PRIMARY KEY NOT NULL DEFAULT (UUID()),
    first_name VARCHAR(50) DEFAULT '',
    last_name VARCHAR(50) DEFAULT '',
    email_address VARCHAR(50) NOT NULL,
    aux_id BIGINT AUTO_INCREMENT,
    version INT NOT NULL DEFAULT 1,
    last_updated DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    last_updated_by VARCHAR(25) NOT NULL DEFAULT CURRENT_USER,
    INDEX(aux_id),
    UNIQUE(email_address)
) ENGINE = InnoDB;

-- DROP VIEW IF EXISTS employees_v1;
CREATE VIEW employees_v1 AS
SELECT
    id AS employee_id,
    first_name,
    last_name,
    email_address,
    version,
    UNIX_TIMESTAMP(last_updated) AS last_updated,
    last_updated_by
FROM
    employees;
```

In this case, a view is used to abstract the underlying data (employees) from the contract of v1 of the employees table. Such that if there are changes to the underlying data, we can maintain the existing contracts by changing the underlying table (employees) and modifying the view to convert that data as needed to maintain the contract (employees_v1). We also have the ability to create a new view (employees_v2) for a new version of employees with the same backing data. This solution can take advantage of good data architecture by having consumers depend on the view rather than the backing data table and insulate them from changes to the backing data. You still have to take the database down for migration, but you reduce the number of code/query changes. If you review some of the existing use cases, you may notice that now some changes are no longer breaking changes from the perspective of the contract/api.

In the next section will cover manual migration for each of the use cases above and provide some context to the commands we're using etc.

## Manual Migration

The purpose of this section is to show how we'd perform migration manually. I come from a background where there was only first/second-party support and in general, when you wanted a tool or functionality it was much faster to build your own then to look for someone else's solution and tweak it for your use case. As Golang is has MUUUCH better support than LabVIEW; I don't have the same problem, but it's evolution is that I always want to know how I'd go about doing it manually just in case.

This section is going to be use case driven and will try to create some basic data sets too. This will be the initial starting point for the migration; feel free to copy+paste this or to use the included sql image:

### Data/Schema Setup

```sql
-- DROP DATABASE IF EXISTS sql_blog_migration;
CREATE DATABASE IF NOT EXISTS sql_blog_migration;

USE sql_blog_migration;

-- DROP TABLE IF EXISTS employees;
CREATE TABLE IF NOT EXISTS employees (
    id VARCHAR(36) PRIMARY KEY NOT NULL DEFAULT (UUID()),
    first_name VARCHAR(50) DEFAULT '',
    last_name VARCHAR(50) DEFAULT '',
    email_address VARCHAR(50) NOT NULL,
    aux_id BIGINT AUTO_INCREMENT,
    version INT NOT NULL DEFAULT 1,
    last_updated DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    last_updated_by VARCHAR(25) NOT NULL DEFAULT CURRENT_USER,
    INDEX(aux_id),
    UNIQUE(email_address)
) ENGINE = InnoDB;

-- DROP TABLE IF EXISTS employees_audit;
CREATE TABLE IF NOT EXISTS employees_audit (
    employee_id VARCHAR(36) NOT NULL,
    first_name TEXT,
    last_name TEXT,
    email_address TEXT,
    version INT NOT NULL,
    last_updated DATETIME(6) NOT NULL,
    last_updated_by TEXT NOT NULL,
    PRIMARY KEY (employee_id, version),
    FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE
) ENGINE = InnoDB;

-- DROP VIEW IF EXISTS employees_v1;
CREATE VIEW employees_v1 AS
SELECT
    id AS employee_id,
    first_name,
    last_name,
    email_address,
    version,
    UNIX_TIMESTAMP(last_updated) AS last_updated,
    last_updated_by
FROM
    employees;

-- DROP TRIGGER IF EXISTS employees_audit_info_update;
CREATE TRIGGER employees_audit_info_update
BEFORE UPDATE ON employees FOR EACH ROW
    SET new.id = old.id, new.aux_id = old.aux_id, new.version = old.version+1, new.last_updated = CURRENT_TIMESTAMP(6), new.last_updated_by = CURRENT_USER;

-- DROP TRIGGER IF EXISTS employees_audit_insert;
CREATE TRIGGER employees_audit_insert
AFTER INSERT ON employees FOR EACH ROW
    INSERT INTO employees_audit(employee_id, first_name, last_name, email_address, version, last_updated, last_updated_by)
     VALUES (new.id, new.first_name,  new.last_name, new.email_address, new.version, new.last_updated, new.last_updated_by);

-- DROP TRIGGER IF EXISTS employees_audit_update;
CREATE TRIGGER employees_audit_update
AFTER UPDATE ON employees FOR EACH ROW
    INSERT INTO employees_audit(employee_id, first_name, last_name, email_address, version, last_updated, last_updated_by)
     VALUES(new.id, new.first_name,  new.last_name, new.email_address, new.version, new.last_updated, new.last_updated_by);
```

```sql
INSERT INTO
    employees(first_name, last_name, email_address)
VALUES
    ('Isshin', 'Kurosaki', 'Isshin.Kurosaki@viz.com'),
    ('Masaki', 'Kurosaki', 'Masaki.Kurosaki@viz.com'),
    ('Ichigo', 'Kurosaki', 'Ichigo.Kurosaki@viz.com'),
    ('Karin', 'Kurosaki', 'Karin.Kurosaki@viz.com'),
    ('Yuzu', 'Kurosaki', 'Yuzu.Kurosaki@viz.com'),
    ('Orihime', 'Inoue', 'Orihime.Inoue@viz.com'),
    ('Kazui', 'Kurosaki', 'Kazui.Kurosaki@viz.com');
```

After entering the two items above, you should see the following (from a clean/empty database, keep in mind the ids should be different):

```sh
MariaDB [sql_blog_migration]> SELECT * from employees;
+--------------------------------------+------------+-----------+-------------------------+--------+---------+----------------------------+-----------------+
| id                                   | first_name | last_name | email_address           | aux_id | version | last_updated               | last_updated_by |
+--------------------------------------+------------+-----------+-------------------------+--------+---------+----------------------------+-----------------+
| 121ac05b-c1bf-11ed-8414-0242ac130002 | Isshin     | Kurosaki  | Isshin.Kurosaki@viz.com |      1 |       1 | 2023-03-13 16:49:50.492451 | root@localhost  |
| 121ac573-c1bf-11ed-8414-0242ac130002 | Masaki     | Kurosaki  | Masaki.Kurosaki@viz.com |      2 |       1 | 2023-03-13 16:49:50.492451 | root@localhost  |
| 121acf30-c1bf-11ed-8414-0242ac130002 | Ichigo     | Kurosaki  | Ichigo.Kurosaki@viz.com |      3 |       1 | 2023-03-13 16:49:50.492451 | root@localhost  |
| 121ad1d4-c1bf-11ed-8414-0242ac130002 | Karin      | Kurosaki  | Karin.Kurosaki@viz.com  |      4 |       1 | 2023-03-13 16:49:50.492451 | root@localhost  |
| 121ad520-c1bf-11ed-8414-0242ac130002 | Yuzu       | Kurosaki  | Yuzu.Kurosaki@viz.com   |      5 |       1 | 2023-03-13 16:49:50.492451 | root@localhost  |
| 121ad6ae-c1bf-11ed-8414-0242ac130002 | Orihime    | Inoue     | Orihime.Inoue@viz.com   |      6 |       1 | 2023-03-13 16:49:50.492451 | root@localhost  |
| 121ad7fa-c1bf-11ed-8414-0242ac130002 | Kazui      | Kurosaki  | Kazui.Kurosaki@viz.com  |      7 |       1 | 2023-03-13 16:49:50.492451 | root@localhost  |
+--------------------------------------+------------+-----------+-------------------------+--------+---------+----------------------------+-----------------+
MariaDB [sql_blog_migration]> SELECT * from employees_audit;
+--------------------------------------+------------+-----------+-------------------------+---------+----------------------------+-----------------+
| employee_id                          | first_name | last_name | email_address           | version | last_updated               | last_updated_by |
+--------------------------------------+------------+-----------+-------------------------+---------+----------------------------+-----------------+
| 121ac05b-c1bf-11ed-8414-0242ac130002 | Isshin     | Kurosaki  | Isshin.Kurosaki@viz.com |       1 | 2023-03-13 16:49:50.492451 | root@localhost  |
| 121ac573-c1bf-11ed-8414-0242ac130002 | Masaki     | Kurosaki  | Masaki.Kurosaki@viz.com |       1 | 2023-03-13 16:49:50.492451 | root@localhost  |
| 121acf30-c1bf-11ed-8414-0242ac130002 | Ichigo     | Kurosaki  | Ichigo.Kurosaki@viz.com |       1 | 2023-03-13 16:49:50.492451 | root@localhost  |
| 121ad1d4-c1bf-11ed-8414-0242ac130002 | Karin      | Kurosaki  | Karin.Kurosaki@viz.com  |       1 | 2023-03-13 16:49:50.492451 | root@localhost  |
| 121ad520-c1bf-11ed-8414-0242ac130002 | Yuzu       | Kurosaki  | Yuzu.Kurosaki@viz.com   |       1 | 2023-03-13 16:49:50.492451 | root@localhost  |
| 121ad6ae-c1bf-11ed-8414-0242ac130002 | Orihime    | Inoue     | Orihime.Inoue@viz.com   |       1 | 2023-03-13 16:49:50.492451 | root@localhost  |
| 121ad7fa-c1bf-11ed-8414-0242ac130002 | Kazui      | Kurosaki  | Kazui.Kurosaki@viz.com  |       1 | 2023-03-13 16:49:50.492451 | root@localhost  |
+--------------------------------------+------------+-----------+-------------------------+---------+----------------------------+-----------------+
MariaDB [sql_blog_migration]> SELECT * from employees_v1;
+--------------------------------------+------------+-----------+-------------------------+---------+-------------------+-----------------+
| employee_id                          | first_name | last_name | email_address           | version | last_updated      | last_updated_by |
+--------------------------------------+------------+-----------+-------------------------+---------+-------------------+-----------------+
| 121ac05b-c1bf-11ed-8414-0242ac130002 | Isshin     | Kurosaki  | Isshin.Kurosaki@viz.com |       1 | 1678726190.492451 | root@localhost  |
| 121ac573-c1bf-11ed-8414-0242ac130002 | Masaki     | Kurosaki  | Masaki.Kurosaki@viz.com |       1 | 1678726190.492451 | root@localhost  |
| 121acf30-c1bf-11ed-8414-0242ac130002 | Ichigo     | Kurosaki  | Ichigo.Kurosaki@viz.com |       1 | 1678726190.492451 | root@localhost  |
| 121ad1d4-c1bf-11ed-8414-0242ac130002 | Karin      | Kurosaki  | Karin.Kurosaki@viz.com  |       1 | 1678726190.492451 | root@localhost  |
| 121ad520-c1bf-11ed-8414-0242ac130002 | Yuzu       | Kurosaki  | Yuzu.Kurosaki@viz.com   |       1 | 1678726190.492451 | root@localhost  |
| 121ad6ae-c1bf-11ed-8414-0242ac130002 | Orihime    | Inoue     | Orihime.Inoue@viz.com   |       1 | 1678726190.492451 | root@localhost  |
| 121ad7fa-c1bf-11ed-8414-0242ac130002 | Kazui      | Kurosaki  | Kazui.Kurosaki@viz.com  |       1 | 1678726190.492451 | root@localhost  |
+--------------------------------------+------------+-----------+-------------------------+---------+-------------------+-----------------+
```

### Manually: changing the id field from string (varchar) to an int (binary)

The proposed change for this is to update the table to make the id field an int field that can hold the underlying value for a uuid; let’s assume this is for "performance" purposes (a 36 character string takes more disk space per row than a 2-byte integer).  To do this, we'd have to update the employees schema to this:

```sql
-- DROP DATABASE IF EXISTS sql_blog_migration;
CREATE DATABASE IF NOT EXISTS sql_blog_migration;

USE sql_blog_migration;

-- DROP TABLE IF EXISTS employees;
CREATE TABLE IF NOT EXISTS employees (
    id BINARY(16) PRIMARY KEY NOT NULL DEFAULT (unhex(replace(uuid(),'-',''))),
    id_text varchar(36) generated always as
     (insert(
        insert(
          insert(
            insert(hex(id),9,0,'-'),
            14,0,'-'),
          19,0,'-'),
        24,0,'-')
     ) virtual,
    first_name VARCHAR(50) DEFAULT '',
    last_name VARCHAR(50) DEFAULT '',
    email_address VARCHAR(50) NOT NULL,
    aux_id BIGINT AUTO_INCREMENT,
    version INT NOT NULL DEFAULT 1,
    last_updated DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    last_updated_by VARCHAR(25) NOT NULL DEFAULT CURRENT_USER,
    INDEX(aux_id),
    UNIQUE(email_address)
) ENGINE = InnoDB;

-- DROP TABLE IF EXISTS employees_audit;
CREATE TABLE IF NOT EXISTS employees_audit (
    employee_id BINARY(16) NOT NULL,
    employee_id_text varchar(36) generated always as
     (insert(
        insert(
          insert(
            insert(hex(id),9,0,'-'),
            14,0,'-'),
          19,0,'-'),
        24,0,'-')
     ) virtual,
    first_name TEXT,
    last_name TEXT,
    email_address TEXT,
    version INT NOT NULL,
    last_updated DATETIME(6) NOT NULL,
    last_updated_by TEXT NOT NULL,
    PRIMARY KEY (employee_id, version),
    FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE
) ENGINE = InnoDB;

-- DROP VIEW IF EXISTS employees_v1;
CREATE VIEW employees_v1 AS
SELECT
    id AS employee_id_text,
    first_name,
    last_name,
    email_address,
    version,
    UNIX_TIMESTAMP(last_updated) AS last_updated,
    last_updated_by
FROM
    employees;

-- DROP TRIGGER IF EXISTS employees_audit_info_update;
CREATE TRIGGER employees_audit_info_update
BEFORE UPDATE ON employees FOR EACH ROW
    SET new.id = old.id, new.aux_id = old.aux_id, new.version = old.version+1, new.last_updated = CURRENT_TIMESTAMP(6), new.last_updated_by = CURRENT_USER;

-- DROP TRIGGER IF EXISTS employees_audit_insert;
CREATE TRIGGER employees_audit_insert
AFTER INSERT ON employees FOR EACH ROW
    INSERT INTO employees_audit(employee_id, first_name, last_name, email_address, version, last_updated, last_updated_by)
     VALUES (new.id, new.first_name,  new.last_name, new.email_address, new.version, new.last_updated, new.last_updated_by);

-- DROP TRIGGER IF EXISTS employees_audit_update;
CREATE TRIGGER employees_audit_update
AFTER UPDATE ON employees FOR EACH ROW
    INSERT INTO employees_audit(employee_id, first_name, last_name, email_address, version, last_updated, last_updated_by)
     VALUES(new.id, new.first_name,  new.last_name, new.email_address, new.version, new.last_updated, new.last_updated_by);
```

You may think that we just need to do a couple of [alter](https://dev.mysql.com/doc/refman/8.0/en/alter-table.html) statements, but that couldn't be further from the truth. One of the biggest issues is that we're modifying a primary key that's used in a number of locations as a foreign key constraint. So even if the table were empty, we'd have trouble making these modifications. These are the high-level steps we need to execute in order to make these changes (keep in mind that the term 'manual' also assumes you're doing this interactively):

0. Backup database
1. Lock the tables for write: employees, employee_audit
2. Remove foreign key constraints from employee_audit
3. Add a new column to employees for the migrated id column (ensure it's not the primary key and doesn't have a default clause)
4. Migrate employees data from current id column to new column created
5. Remove primary key from old employees id
6. Drop column for old employees id
7. Add primary key to new employees id
8. Add a new column to employees_audit for the migrated id column
9. Migrate employees_audit data from current id column to new column created
10. Drop column for old employees_audit id
11. Add foreign key constraint for employees id to employees_audit
12. Unlock the tables: employees, employee_audit
13. Alter the view to generate the text uuid from the binary
14. Smoke test the change by reading existing data, updating existing data and inserting new data

> Keep in mind that because we lock the table, this is considered an outage, no-one should be able to read/write to these tables while you're doing these edits

Start a new session as a user with appropriate rights (I'm being lazy and using root):

```sh
mysqldump -u root -p sql_blog_migration > /tmp/sql_blog_migration.sql
```

```sql
USE sql_blog_migration;

-- select the id/email_address so you can compare at the end
SELECT employee_id, email_address from employees_v1;

-- lock the table to prevent modification while migrating
LOCK TABLES employees_audit WRITE, employees WRITE;
-- SHOW OPEN TABLES WHERE In_Use > 0;

-- remove the foreign key so you can modify the foreign key in the employees table
ALTER TABLE employees_audit DROP FOREIGN KEY employees_audit_ibfk_1;

-- edit and replace employees id with its binary representation
ALTER TABLE employees ADD COLUMN _id BINARY(16);
ALTER TABLE employees DROP PRIMARY KEY;
UPDATE employees SET employees._id = (UNHEX(REPLACE(employees.id, "-",""))) WHERE employees.id=employees.id;
ALTER TABLE employees DROP COLUMN id;
ALTER TABLE employees RENAME COLUMN _id TO id;
ALTER TABLE employees MODIFY COLUMN id BINARY(16) PRIMARY KEY NOT NULL DEFAULT (unhex(replace(uuid(),'-','')));

-- edit and replace employees_audit id with its binary representation
ALTER TABLE employees_audit ADD COLUMN _id BINARY(16);
ALTER TABLE employees_audit DROP PRIMARY KEY;
UPDATE employees_audit SET employees_audit._id = (UNHEX(REPLACE(employees_audit.employee_id, "-",""))) WHERE employees_audit.employee_id=employees_audit.employee_id;
ALTER TABLE employees_audit DROP COLUMN employee_id;
ALTER TABLE employees_audit RENAME COLUMN _id TO employee_id;
ALTER TABLE employees_audit MODIFY COLUMN employee_id BINARY(16) NOT NULL;
ALTER TABLE employees_audit ADD PRIMARY KEY (employee_id,version);
ALTER TABLE employees_audit ADD FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE;

-- unlock tables for read
UNLOCK TABLES;
-- SHOW OPEN TABLES WHERE In_Use > 0;

-- update the employee_v1 view to unhex the binary
ALTER VIEW employees_v1 AS
SELECT
     (LOWER(INSERT(
        INSERT(
          INSERT(
            INSERT(HEX(id),9,0,'-'),
            14,0,'-'),
          19,0,'-'),
        24,0,'-'))
     ) AS employee_id,
    first_name,
    last_name,
    email_address,
    version,
    UNIX_TIMESTAMP(last_updated) AS last_updated,
    last_updated_by
FROM
    employees;

-- select the id/email_address for comparison purposes
SELECT employee_id, email_address from employees_v1;
```

In comparing the employee_ids and email_address, we can see that we've migrated from VARCHAR(36) to BINARY(16) while not breaking the contract (data types) by using the view as the go-between. This migration is interesting because it's 100% possible to revert the change by doing the opposite EVEN if the data is mutated; this is not always possible. The code to "revert" this change would be the following:

```sql
USE sql_blog_migration;

-- select the id/email_address so you can compare at the end
SELECT employee_id, email_address from employees_v1;

-- lock the table to prevent modification while migrating
LOCK TABLES employees_audit WRITE, employees WRITE;
-- SHOW OPEN TABLES WHERE In_Use > 0;

-- remove the foreign key so you can modify the foreign key in the employees table
ALTER TABLE employees_audit DROP FOREIGN KEY employees_audit_ibfk_1;

-- edit and replace employees id with its binary representation
ALTER TABLE employees ADD COLUMN _id VARCHAR(36);
ALTER TABLE employees DROP PRIMARY KEY;
UPDATE employees SET employees._id = ((LOWER(INSERT(
        INSERT(
          INSERT(
            INSERT(HEX(id),9,0,'-'),
            14,0,'-'),
          19,0,'-'),
        24,0,'-')
        ))) WHERE employees.id=employees.id;
ALTER TABLE employees DROP COLUMN id;
ALTER TABLE employees RENAME COLUMN _id TO id;
ALTER TABLE employees MODIFY COLUMN id VARCHAR(36) PRIMARY KEY NOT NULL DEFAULT uuid();

-- edit and replace employees_audit id with its binary representation
ALTER TABLE employees_audit ADD COLUMN _id VARCHAR(36);
ALTER TABLE employees_audit DROP PRIMARY KEY;
UPDATE employees_audit SET employees_audit._id = ((LOWER(INSERT(
        INSERT(
          INSERT(
            INSERT(HEX(employee_id),9,0,'-'),
            14,0,'-'),
          19,0,'-'),
        24,0,'-')
        ))) WHERE employees_audit.employee_id=employees_audit.employee_id;
ALTER TABLE employees_audit DROP COLUMN employee_id;
ALTER TABLE employees_audit RENAME COLUMN _id TO employee_id;
ALTER TABLE employees_audit MODIFY COLUMN employee_id VARCHAR(36) NOT NULL;
ALTER TABLE employees_audit ADD PRIMARY KEY (employee_id,version);
ALTER TABLE employees_audit ADD FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE;

-- unlock tables for read
UNLOCK TABLES;
-- SHOW OPEN TABLES WHERE In_Use > 0;

-- update the employee_v1 view to unhex the binary
ALTER VIEW employees_v1 AS
SELECT
    id AS employee_id,
    first_name,
    last_name,
    email_address,
    version,
    UNIX_TIMESTAMP(last_updated) AS last_updated,
    last_updated_by
FROM
    employees;

-- select the id/email_address for comparison purposes
SELECT employee_id, email_address from employees_v1;
```

### Manually: adding birthdate field

If you wanted to add a birthdate field, the effort would be straight forward, you'd lock the tables and then you'd add the column. From a migration perspective it’s VERY easy to go forward, but difficult to go back once data has been mutated. The "crux" of this migration is not doing it, but that you may not be able to easily undo it. This is what the sql would look like:

```sh
# backup database
mysqldump -u root -p sql_blog_migration > /tmp/sql_blog_migration.sql
```

```sql
USE sql_blog_migration

-- lock tables
LOCK TABLES employees WRITE, employees_audit WRITE;

-- describe tables
DESCRIBE employees;
DESCRIBE employees_audit;

--perform DDL to add column
ALTER TABLE employees ADD COLUMN birth_date DATETIME;
ALTER TABLE employees_audit ADD COLUMN birth_date DATETIME;

--update the triggers
DROP TRIGGER IF EXISTS employees_audit_insert;
CREATE TRIGGER employees_audit_insert
AFTER INSERT ON employees FOR EACH ROW
    INSERT INTO employees_audit(employee_id, first_name, last_name, email_address, birth_date, version, last_updated, last_updated_by)
     VALUES (new.id, new.first_name,  new.last_name, new.email_address, new.birth_date, new.version, new.last_updated, new.last_updated_by);
DROP TRIGGER IF EXISTS employees_audit_update;
CREATE TRIGGER employees_audit_update
AFTER UPDATE ON employees FOR EACH ROW
    INSERT INTO employees_audit(employee_id, first_name, last_name, email_address, birth_date, version, last_updated, last_updated_by)
     VALUES(new.id, new.first_name,  new.last_name, new.email_address, new.birth_date, new.version, new.last_updated, new.last_updated_by);

-- unlock tables
UNLOCK TABLES;

-- describe tables
DESCRIBE employees;
DESCRIBE employees_audit;

-- smoke test
UPDATE employees set birth_date='1985-07-15' where id=(SELECT id from employees WHERE first_name='Ichigo');
```

Unfortunately, to "undo" or revert this migration, you have to destroy data (and break a contract); so although you could revert this change, once you unlock the database, you can't do so without destroying data. I use this example to mostly make you aware of what's going on. MySQL won't tell you that you're destroying data, it'll just do it, so you have to keep that in mind.

## Automatic Migration Using Goose

With those examples out of the way and clearly how complicated the process is, you may want to automate the process so it's one click up and one click down; you may also realize that some of your offline installations may be MANY migrations behind where you are currently. Being able to automate those migrations (that have been thoroughly tested) may reduce your administrative overhead as you can schedule and plan those mass migrations to be done at the click of a button rather than having to log into each and every installation. In this section we'll be making some strong assumptions, but I think they'll push you in one direction to simplify/automate this process:

- We'll create a customer MySQL Docker image
- Our Docker image will have the most recent schema on it
- Our Docker image will have a startup script that will automatically migrate the database from whatever state it's in to the most recent schema

Our tool of choice will be [Goose](https://github.com/pressly/goose) because it does a lot of the work for us. Before we can start doing stuff, we'll need to install goose and then validate it's connection to the database:

```sh
make check-goose
goose version
goose mysql "root:mysql@/sql_blog_migration?parseTime=true&&multiStatements=true" status
```

Once we have goose installed we can start the processes of create migrations for Goose.

### Automatically: changing the id field from a string (varchar) to a int (binary)

We're going to automate our initial migration of changing the id field from a string to an integer. Once we've installed goose, we'll need to go into the migration folder and create a new migration (starting from the root of the repo):

```sh
cd sql/migration
goose create uuid_string_to_binary sql
```

This should create a file prefixed with a timestamp; the sql file is initially empty (see below):

```sql
-- +goose Up
-- +goose StatementBegin
SELECT 'up SQL query';
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
SELECT 'down SQL query';
-- +goose StatementEnd
```

What we'll do from here is copy+paste the code we created above in the [Manual Migration](#manual-migration) section for goose up (to migrate forward) and goose down (to migrate backward/revert). It should look like the following if we copy+paste:

```sql
-- +goose Up
-- +goose StatementBegin
-- lock the table to prevent modification while migrating
LOCK TABLES employees_audit WRITE, employees WRITE;

-- remove the foreign key so you can modify the foreign key in the employees table
ALTER TABLE employees_audit DROP FOREIGN KEY employees_audit_ibfk_1;

-- edit and replace employees id with its binary representation
ALTER TABLE employees ADD COLUMN _id BINARY(16);
ALTER TABLE employees DROP PRIMARY KEY;
UPDATE employees SET employees._id = (UNHEX(REPLACE(employees.id, "-",""))) WHERE employees.id=employees.id;
ALTER TABLE employees DROP COLUMN id;
ALTER TABLE employees RENAME COLUMN _id TO id;
ALTER TABLE employees MODIFY COLUMN id BINARY(16) PRIMARY KEY NOT NULL DEFAULT (unhex(replace(uuid(),'-','')));

-- edit and replace employees_audit id with its binary representation
ALTER TABLE employees_audit ADD COLUMN _id BINARY(16);
ALTER TABLE employees_audit DROP PRIMARY KEY;
UPDATE employees_audit SET employees_audit._id = (UNHEX(REPLACE(employees_audit.employee_id, "-",""))) WHERE employees_audit.employee_id=employees_audit.employee_id;
ALTER TABLE employees_audit DROP COLUMN employee_id;
ALTER TABLE employees_audit RENAME COLUMN _id TO employee_id;
ALTER TABLE employees_audit MODIFY COLUMN employee_id BINARY(16) NOT NULL;
ALTER TABLE employees_audit ADD PRIMARY KEY (employee_id,version);
ALTER TABLE employees_audit ADD FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE;

-- unlock tables for read
UNLOCK TABLES;

-- update the employee_v1 view to unhex the binary
ALTER VIEW employees_v1 AS
SELECT
     (LOWER(INSERT(
        INSERT(
          INSERT(
            INSERT(HEX(id),9,0,'-'),
            14,0,'-'),
          19,0,'-'),
        24,0,'-'))
     ) AS employee_id,
    first_name,
    last_name,
    email_address,
    version,
    UNIX_TIMESTAMP(last_updated) AS last_updated,
    last_updated_by
FROM
    employees;
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
-- lock the table to prevent modification while migrating
LOCK TABLES employees_audit WRITE, employees WRITE;

-- remove the foreign key so you can modify the foreign key in the employees table
ALTER TABLE employees_audit DROP FOREIGN KEY employees_audit_ibfk_1;

-- edit and replace employees id with its binary representation
ALTER TABLE employees ADD COLUMN _id VARCHAR(36);
ALTER TABLE employees DROP PRIMARY KEY;
UPDATE employees SET employees._id = ((LOWER(INSERT(
        INSERT(
          INSERT(
            INSERT(HEX(id),9,0,'-'),
            14,0,'-'),
          19,0,'-'),
        24,0,'-')
        ))) WHERE employees.id=employees.id;
ALTER TABLE employees DROP COLUMN id;
ALTER TABLE employees RENAME COLUMN _id TO id;
ALTER TABLE employees MODIFY COLUMN id VARCHAR(36) PRIMARY KEY NOT NULL DEFAULT uuid();

-- edit and replace employees_audit id with its binary representation
ALTER TABLE employees_audit ADD COLUMN _id VARCHAR(36);
ALTER TABLE employees_audit DROP PRIMARY KEY;
UPDATE employees_audit SET employees_audit._id = ((LOWER(INSERT(
        INSERT(
          INSERT(
            INSERT(HEX(employee_id),9,0,'-'),
            14,0,'-'),
          19,0,'-'),
        24,0,'-')
        ))) WHERE employees_audit.employee_id=employees_audit.employee_id;
ALTER TABLE employees_audit DROP COLUMN employee_id;
ALTER TABLE employees_audit RENAME COLUMN _id TO employee_id;
ALTER TABLE employees_audit MODIFY COLUMN employee_id VARCHAR(36) NOT NULL;
ALTER TABLE employees_audit ADD PRIMARY KEY (employee_id,version);
ALTER TABLE employees_audit ADD FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE;

-- unlock tables for read
UNLOCK TABLES;

-- update the employee_v1 view to unhex the binary
ALTER VIEW employees_v1 AS
SELECT
    id AS employee_id,
    first_name,
    last_name,
    email_address,
    version,
    UNIX_TIMESTAMP(last_updated) AS last_updated,
    last_updated_by
FROM
    employees;
-- +goose StatementEnd
```

To "simulate" migrating forward, we can enter the following commands:

```sh
goose mysql "root:mysql@/sql_blog_migration?parseTime=true&&multiStatements=true" up
```

They have the following output:

```sh
2023/03/14 16:59:59 OK   20230314162808_uuid_string_to_binary.sql (502.2ms)
2023/03/14 16:59:59 goose: no migrations to run. current version: 20230314162808
```

We can also simulate reversion/rollback by entering the following commands:

```sh
goose mysql "root:mysql@/sql_blog_migration?parseTime=true&&multiStatements=true" down
```

They have the following output:

```sh
2023/03/14 17:00:13 OK   20230314162808_uuid_string_to_binary.sql (483.02ms)
```

### Automatically: adding birthdate field

To create a migration script, we'll need to run the following command:

```sh
cd ./sql/migration
goose create birth_date_column sql
```

We'll then populate this file with the sql from [Manually: adding birthdate field](#manually-adding-birthdate-field):

```sql
-- +goose Up
-- +goose StatementBegin
-- lock tables
LOCK TABLES employees WRITE, employees_audit WRITE;

-- perform DDL to add column
ALTER TABLE employees ADD COLUMN birth_date DATETIME;
ALTER TABLE employees_audit ADD COLUMN birth_date DATETIME;

-- update the triggers
DROP TRIGGER IF EXISTS employees_audit_insert;
CREATE TRIGGER employees_audit_insert
AFTER INSERT ON employees FOR EACH ROW
    INSERT INTO employees_audit(employee_id, first_name, last_name, email_address, birth_date, version, last_updated, last_updated_by)
     VALUES (new.id, new.first_name,  new.last_name, new.email_address, new.birth_date, new.version, new.last_updated, new.last_updated_by);
DROP TRIGGER IF EXISTS employees_audit_update;
CREATE TRIGGER employees_audit_update
AFTER UPDATE ON employees FOR EACH ROW
    INSERT INTO employees_audit(employee_id, first_name, last_name, email_address, birth_date, version, last_updated, last_updated_by)
     VALUES(new.id, new.first_name,  new.last_name, new.email_address, new.birth_date, new.version, new.last_updated, new.last_updated_by);

-- unlock tables
UNLOCK TABLES;
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
-- lock tables
LOCK TABLES employees WRITE, employees_audit WRITE;

-- perform DDL to add column
ALTER TABLE employees DROP COLUMN birth_date;
ALTER TABLE employees_audit DROP COLUMN birth_date;

-- revert the triggers
DROP TRIGGER IF EXISTS employees_audit_insert;
CREATE TRIGGER employees_audit_insert
AFTER INSERT ON employees FOR EACH ROW
    INSERT INTO employees_audit(employee_id, first_name, last_name, email_address, version, last_updated, last_updated_by)
     VALUES (new.id, new.first_name,  new.last_name, new.email_address, new.version, new.last_updated, new.last_updated_by);
DROP TRIGGER IF EXISTS employees_audit_update;
CREATE TRIGGER employees_audit_update
AFTER UPDATE ON employees FOR EACH ROW
    INSERT INTO employees_audit(employee_id, first_name, last_name, email_address, version, last_updated, last_updated_by)
     VALUES(new.id, new.first_name,  new.last_name, new.email_address, new.version, new.last_updated, new.last_updated_by);

-- unlock tables
UNLOCK TABLES;
-- +goose StatementEnd
```

Once added, we can perform migration with the following commands:

```sh
cd ./sql/migration
goose mysql "root:mysql@/sql_blog_migration?parseTime=true&&multiStatements=true" status
goose mysql "root:mysql@/sql_blog_migration?parseTime=true&&multiStatements=true" up-by-one
```

It should have the following output:

```sh
2023/03/15 10:29:51     Applied At                  Migration
2023/03/15 10:29:51     =======================================
2023/03/15 10:29:51     Wed Mar 15 15:21:35 2023 -- 20230314162808_uuid_string_to_binary.sql
2023/03/15 10:29:51     Pending                  -- 20230315093400_birth_date_column.sql    

2023/03/15 10:29:53 OK   20230315093400_birth_date_column.sql (125.57ms)
```

At this point, you should be able to describe the table to confirm the change and add a birthdate without issue (this is done via the mysql client):

```sh
MariaDB [sql_blog_migration]> describe employees;
+-----------------+-------------+------+-----+-------------------------------+----------------+
| Field           | Type        | Null | Key | Default                       | Extra          |
+-----------------+-------------+------+-----+-------------------------------+----------------+
| first_name      | varchar(50) | YES  |     |                               |                |
| last_name       | varchar(50) | YES  |     |                               |                |
| email_address   | varchar(50) | NO   | UNI | NULL                          |                |
| aux_id          | bigint(20)  | NO   | MUL | NULL                          | auto_increment |
| version         | int(11)     | NO   |     | 1                             |                |
| last_updated    | datetime(6) | NO   |     | current_timestamp(6)          |                |
| last_updated_by | varchar(25) | NO   |     | current_user()                |                |
| id              | binary(16)  | NO   | PRI | unhex(replace(uuid(),'-','')) |                |
| birth_date      | datetime    | YES  |     | NULL                          |                |
+-----------------+-------------+------+-----+-------------------------------+----------------+
9 rows in set (0.001 sec)

MariaDB [sql_blog_migration]> describe employees_audit;
+-----------------+-------------+------+-----+---------+-------+
| Field           | Type        | Null | Key | Default | Extra |
+-----------------+-------------+------+-----+---------+-------+
| first_name      | text        | YES  |     | NULL    |       |
| last_name       | text        | YES  |     | NULL    |       |
| email_address   | text        | YES  |     | NULL    |       |
| version         | int(11)     | NO   | PRI | NULL    |       |
| last_updated    | datetime(6) | NO   |     | NULL    |       |
| last_updated_by | text        | NO   |     | NULL    |       |
| employee_id     | binary(16)  | NO   | PRI | NULL    |       |
| birth_date      | datetime    | YES  |     | NULL    |       |
+-----------------+-------------+------+-----+---------+-------+
8 rows in set (0.001 sec)

MariaDB [sql_blog_migration]> describe employees_v1;                                                                                               
+-----------------+---------------+------+-----+----------------+-------+
| Field           | Type          | Null | Key | Default        | Extra |
+-----------------+---------------+------+-----+----------------+-------+
| employee_id     | varchar(36)   | YES  |     | NULL           |       |
| first_name      | varchar(50)   | YES  |     |                |       |
| last_name       | varchar(50)   | YES  |     |                |       |
| email_address   | varchar(50)   | NO   |     | NULL           |       |
| birth_date      | datetime      | YES  |     | NULL           |       |
| version         | int(11)       | NO   |     | 1              |       |
| last_updated    | decimal(22,6) | YES  |     | NULL           |       |
| last_updated_by | varchar(25)   | NO   |     | current_user() |       |
+-----------------+---------------+------+-----+----------------+-------+
8 rows in set (0.001 sec)

MariaDB [sql_blog_migration]> select employee_id, first_name, last_name, birth_date from employees_v1 where first_name='Ichigo';
+--------------------------------------+------------+-----------+------------+
| employee_id                          | first_name | last_name | birth_date |
+--------------------------------------+------------+-----------+------------+
| efb005e2-c346-11ed-9e2e-0242ac170002 | Ichigo     | Kurosaki  | NULL       |
+--------------------------------------+------------+-----------+------------+
1 row in set (0.001 sec)

MariaDB [sql_blog_migration]> UPDATE employees set birth_date='1985-07-15' where id=(SELECT id from employees WHERE first_name='Ichigo');
Query OK, 1 row affected (0.003 sec)
Rows matched: 1  Changed: 1  Warnings: 0

MariaDB [sql_blog_migration]> select employee_id, first_name, last_name, birth_date from employees_v1 where first_name='Ichigo';
+--------------------------------------+------------+-----------+---------------------+
| employee_id                          | first_name | last_name | birth_date          |
+--------------------------------------+------------+-----------+---------------------+
| efb005e2-c346-11ed-9e2e-0242ac170002 | Ichigo     | Kurosaki  | 1985-07-15 00:00:00 |
+--------------------------------------+------------+-----------+---------------------+
1 row in set (0.000 sec)

MariaDB [sql_blog_migration]> select first_name, last_name, birth_date, version from employees_audit where first_name='Ichigo';                    
+------------+-----------+---------------------+---------+
| first_name | last_name | birth_date          | version |
+------------+-----------+---------------------+---------+
| Ichigo     | Kurosaki  | NULL                |       1 |
| Ichigo     | Kurosaki  | NULL                |       2 |
| Ichigo     | Kurosaki  | 1985-07-15 00:00:00 |       3 |
+------------+-----------+---------------------+---------+
```

## Integration: how to put it all together

This section won't be as interactive as the other sections, but I'll include the example code within this repository. You may be going through this entire repo and wonder to yourself, how would I put all of this together to create a solution that's maintainable, auditable and reasonable to allow other people to migrate "offline" databases?

TLDR; we use the following solutions to "solve" this problem:

- We use Docker to create a versioned image that will contain the database, starting sql AND migration scripts
- We use a two-stage docker build to build goose for the appropriate architecture and inject into the final image
- On start we run a script that will attempt to migrate the database (once)

This isn't a very complex solution (when you know what you're looking at) and borrows heavily from [https://github.com/antonio-alexander/go-bludgeon/tree/main/mysql](https://github.com/antonio-alexander/go-bludgeon/tree/main/mysql). Some of the things we've modified are adding goose to the Dockerfile when building, and the docker-entrypoint script to run goose up once the MySQL service is running.

[run.sh](./cmd/run.sh): this file replaces the startup script for the image, we've made some modifications from the [original](https://github.com/yobasystems/alpine-mariadb/blob/master/alpine-mariadb-armhf/files/run.sh) so that it executes our scripts and sql files in the appropriate context:

```sh
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

for f in /docker-entrypoint-initdb.d/*; do
 case "$f" in
  *.sql)    echo "$0: running $f"; mysql -uroot -p${MYSQL_ROOT_PASSWORD} < "$f"; echo ;;
  *.sql.gz) echo "$0: running $f"; gunzip -c "$f" | mysql -uroot -p${MYSQL_ROOT_PASSWORD} < "$f"; echo ;;
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

wait $mysql_pid
```

[auto_migration.sh](./cmd/auto_migration.sh) is a script that allows us to automatically migrate using goose if an environmental variable is set:

```sh
#!/bin/ash

# Migrate database
if [ "$AUTOMATIC_MIGRATION" == "true" ]
then
    cd /sql_blog_migration
    echo ...automatic migration enabled, attempting to migrate
    goose mysql "root:$MYSQL_ROOT_PASSWORD@/sql_blog_migration?parseTime=true&&multiStatements=true" up
fi
```

The [Dockerfile](./cmd/Dockerfile) is a two stage build that will generate the executable for goose and then inject it into the mariadb image with our updated scripts:

```Dockerfile
#---------------------------------------------------------------------------------------------------
# sql-blog-migration [Dockerfile]
# 
# Reference: https://stackoverflow.com/questions/63178036/how-to-find-commit-hash-from-within-a-running-docker-image
# commit: git rev-parse HEAD
# 
# https://stackoverflow.com/questions/6245570/how-to-get-the-current-branch-name-in-git
# branch: git rev-parse --abbrev-ref HEAD
# 
# Sample docker build commands:
#  docker build -f ./cmd/Dockerfile . -t ghcr.io/antonio-alexander/sql-blog-migration:amd64_latest \
#   --build-arg GIT_COMMIT=$GITHUB_SHA --build-arg GIT_BRANCH=$GITHUB_REF --build-arg PLATFORM=linux/amd64
#
#---------------------------------------------------------------------------------------------------

ARG PLATFORM=linux/amd64
ARG GOOSE_VERSION=v3.5.3
ARG MYSQL_DATABASE=sql_blog_migration
ARG MYSQL_ROOT_PASSWORD=sql_blog_migration
ARG MYSQL_USER=sql_blog_migration
ARG MYSQL_PASSWORD=sql_blog_migration

FROM --platform=${PLATFORM} golang:alpine AS builder

ARG GO_ARCH
ARG GO_ARM
ARG GOOSE_VERSION

ENV GOPROXY=https://proxy.golang.org,direct

RUN env GOARCH=${GO_ARCH} GOARM=${GO_ARM} GOOS=linux go install github.com/pressly/goose/v3/cmd/goose@${GOOSE_VERSION} \
    && mv /go/bin/linux_arm/goose /go/bin/goose 2>/dev/null || : \
    && which goose

FROM --platform=${PLATFORM} yobasystems/alpine-mariadb:latest

ARG MYSQL_ROOT_PASSWORD
ARG MYSQL_USER
ARG MYSQL_PASSWORD
ARG MYSQL_DATABASE

ENV MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
ENV MYSQL_DATABASE=${MYSQL_DATABASE}
ENV MYSQL_USER=${MYSQL_USER}
ENV MYSQL_PASSWORD=${MYSQL_PASSWORD}
ENV AUTOMATIC_MIGRATION=false

COPY --from=builder /go/bin/goose /bin/goose

WORKDIR /sql_blog_migration

COPY ./cmd/run.sh /scripts/run.sh 
COPY ./cmd/auto_migration.sh /scripts/post-exec.d/auto_migration.sh 
COPY ./cmd/sql/employees.sql /docker-entrypoint-initdb.d/employees.sql
COPY ./cmd/sql/migration /sql_blog_migration

RUN chmod +x /scripts/post-exec.d/auto_migration.sh \
    && sed -i 's/\r$//' /scripts/run.sh \
    && sed -i 's/\r$//' /scripts/post-exec.d/auto_migration.sh \
    && sed -i 's/\r$//' /docker-entrypoint-initdb.d/employees.sql \
    && sed -i 's/\r$//' /sql_blog_migration/20230314162808_uuid_string_to_binary.sql \
    && sed -i 's/\r$//' /sql_blog_migration/20230315093400_birth_date_column.sql

HEALTHCHECK --start-period=10s --interval=5s --timeout=5s --retries=5 CMD mysqladmin ping -h localhost -u root -p$MYSQL_ROOT_PASSWORD || exit 1

ENTRYPOINT ["/scripts/run.sh"]
```

The [docker-compose.yml](./docker-compose.yml) puts everything together to both build and run the image with defaults:

```yaml
version: "3"

services:

  mysql:
    container_name: "mysql"
    hostname: "mysql"
    image: ghcr.io/antonio-alexander/sql-blog-migration:latest
    restart: "always"
    ports:
      - "3306:3306"
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD:-sql_blog_migration}
      MYSQL_DATABASE: ${MYSQL_DATABASE:-sql_blog_migration}
      MYSQL_USER: ${MYSQL_USER:-sql_blog_migration}
      MYSQL_PASSWORD: ${MYSQL_PASSWORD:-sql_blog_migration}
      AUTOMATIC_MIGRATION: ${AUTOMATIC_MIGRATION:-false}
    build:
      context: ./
      dockerfile: ./cmd/Dockerfile
      args:
        PLATFORM: ${PLATFORM:-linux/amd64}
        GO_ARCH: ${GO_ARCH:-amd64}
        GO_ARM: ${GO_ARM:-7}
    volumes:
      - ./tmp:/tmp
```

With these solutions above, you should be able to run the make build command and have a local image you can use to interact with sql_blog_migration.

Something you may notice is that in practice, you can get inconsistent behavior with goose on new databases. I think in general, for "new" installations, you wouldn't want to apply a really old version of the database, and then migrate it through the steps (although this does work). It'd make more sense to simply apply the latest version of the database (since there's "nothing" to migrate). Something you may notice is that even though the database is up-to-date, when you run goose, it'll attempt to migrate as if you were running the older version of the database; goose assumes that no migrations have occured, so it'll attempt to run all of the migrations.

To resolve this issue, you have to manually create the goose migration table for the database so that it knows NOT to run those goose migrations. For example, if you wanted to indicate that the database had never been migrated, you could do nothing (goose will automatically create this table) or create an empty table:

```sql
CREATE TABLE IF NOT EXISTS goose_db_version (
    id BIGINT(20) UNSIGNED PRIMARY KEY AUTO_INCREMENT NOT NULL,
    version_id BIGINT(20) NOT NULL,
    is_applied TINYINT(1) NOT NULL,
    tstamp TIMESTAMP NULL DEFAULT current_timestamp() 
) ENGINE = InnoDB;
```

Alternatively, if this were a much more recent version that had already been migrated, you could do the following:

```sql
-- create the goose table
CREATE TABLE IF NOT EXISTS goose_db_version (
    id BIGINT(20) UNSIGNED PRIMARY KEY AUTO_INCREMENT NOT NULL,
    version_id BIGINT(20) NOT NULL,
    is_applied TINYINT(1) NOT NULL,
    tstamp TIMESTAMP NULL DEFAULT current_timestamp() 
) ENGINE = InnoDB;

-- insert data communicating that the database has been migrated with these versions
INSERT INTO goose_db_version(id, version_id, is_applied, tstamp) VALUES
    ('1','0','1','2023-03-20 18:16:15'),
    ('2','20230314162808','1','2023-03-20 18:29:07'),
    ('3','20230315093400','1','2023-03-20 18:29:07');
```

As a result, part of the workflow for updating your sql image/dependencies, must be to ALSO manage one or more tables associated with the goose db version.

## Security Considerations

I think this comes with any kind of database how-to/opinion; in an ideal situation you'd migrate using a user with the specific permissions needed to do that migration with that database. This takes some significant effort (to figure out what permissions are needed) and I took a shortcut in using root; even using the MYSQL_USER wouldn't have worked in this case. Although I think you'll only have to do it once, if you care about security in your offline (and online/cloud) databases; this should be really high on your list of things to do.

## Issues Found Worth Mentioning

This is a list of issues I found while putting this together; it may give you more context or communicate an "a-ha" moment:

- the original run.sh script would execute sql using mysqld directly using skip-names, so the definer would be set to a user that didn't exist and the migration would fail unless you dropped the view, re-created it, and THEN ran the migration

> to resolve this issue, I modified the run.sh script to execute the sql scripts as a known user rather than using mysqld behind the scenes; it was an easy problem to resolve interactively by dropping the view and re-creating it, but was almost impossible to automate. I think in most online databases, this isn't an issue, but in an offline database, it's paramount to be able to automate first-time database creation.

Thanks for reading.
