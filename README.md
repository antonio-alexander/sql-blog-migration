# sql-blog-migration (github.com/antonio-alexander/go-blog-data-consistency)

This is a companion repository that's meant to serve as a deep dive into the basics of migration (with my own spin). The goal of this repository is to show some solutions for database migration and describe lessons I learn along the way.

> DISCLAIMER: the sole database technology used by this repository is MySQL; different DBMSs have different rules, we're ONLY taking the rules of MySQL/MariaDB into account. In addition, this repository is from my perspective as a developer, rather than the perspective of a database administrator/architect

Migration is one (of three) administrative operations for databases that involves executing sql or commands that modify data, schemas and/or tables using DDL (data definition language). A migration is by definition NECCESSARY: something has occurred where the data HAS to change. The other two administrative operations are upgrades (e.g., upgrading the version of MySQL) or maintenance (e.g., vacuuming the database tables). One doesn't simply do a migration, not all migrations are painful, some (if done correctly) are just tedius. Here are some situations where migrations are required:

- adding new column (with default)
- increasing column size
- adding or removing a table index
- adding new table
- adding new constraints (with some caveats)

> For purposes of this repository, we'll assume that although a migration can be reverted, the idea is that in practice, you'll never revert a successful migration. As such, even if a migration is backwards compatible it shouldn't be a focus. It's one thing if you delay migration (maybe it's an offline database, or you want to migrate when you update the software), but migration is expected to be necessary and never undone upon successful verification

I also want to keep "offline" databases in mind; for purposes of this discussion an "offline" database is one that isn't being actively maintained. It could be a database used by an application that has to be migrated at an irregular cadence (e.g., when the user wants to update the application) or it's a database that generally runs without any Internet connectivity for extended periods of time and can only be updated when there is an opportune time to. Offline databases are a bit unique because the migration almost requires automation.

## Bibliography

These ar some links I found that helped me figure out how to do something or gave me context as to why something really mattered

- [https://github.com/pressly/goose](https://github.com/pressly/goose)
- [https://dev.mysql.com/doc/refman/8.0/en/lock-tables.html](https://dev.mysql.com/doc/refman/8.0/en/lock-tables.html)
- [Semantic Versioning](https://semver.org/)
- [https://dev.mysql.com/doc/refman/8.0/en/alter-table.html](https://dev.mysql.com/doc/refman/8.0/en/alter-table.html)
- [https://stackoverflow.com/questions/9783636/unlocking-tables-if-thread-is-lost](https://stackoverflow.com/questions/9783636/unlocking-tables-if-thread-is-lost)
- My DBA friend, you'll have to get your own DBA Caveman

## Getting Started

Unfortunately, this repository is NOT simple, BUT...a lot of the work has already been done for you. I've tried to simplify some of the common operations you'll want to do (so you don't have to figure it out). From the root of the repository, you can do the following to setup your environment (you'll need Docker and Go):

```sh
make check-goose
make build
make run
```

This will build and run the custom mysql image included in this repository; if you're curious about what the make commands are doing, you can look at the [Makefile](./Makefile). When the mysql image is running, you can try to execute one (or more) of the commands below.

If you'd like an interactive MySQL shell (find credentials in [.env](.env) and [docker-compose.yml](./docker-compose.yml)):

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

The connection strings used above are a bit complex/esoteric, but they are required.

To go about "testing" the repository, you can change the environmental variable 'EMPLOYEES_SQL' to one of the following:

- [001_employees.sql](./cmd/sql/001_employees.sql)
- [002_employees.sql](./cmd/sql/002_employees.sql)
- [003_employees.sql](./cmd/sql/003_employees.sql)
- [004_employees.sql](./cmd/sql/004_employees.sql)

Each of these successfully applies each migration with 001_employees.sql having performed _zero_ migrations.

## Data Architecture (Domain Analysis)

For any table that's going to get anything more than cursory use, a domain analysis must be made to determine how the schema/tables should be architected to meet the common use cases and survive along with the application. Although applications often go through major changes, databases with proper domain analysis generally don't. In a way, the same is true for an application: breaking contracts and changing the function of an application enough that your domain analysis becomes invalid is a big deal and should avoided at all costs.

> In my opinion, when you change the function of an application so much so that previous integrations break, it's more honest to call it a _new_ application than to say that we've simply introduced breaking changes

Domain analysis, can provide enough foresight such that as you __need__ to change your data, you can make forward compatible changes to it. Data is almost ALWAYS forward compatible such that you can transform the data itself, but once you modify the schema (how the data is organized) and add/change data you've created a change that you can't undo without destroying data; this is my underlying reason why changes to the schema/data are ONLY forward compatible.

> That isn't to say that you can't make a view that makes data backwards compatible or something, but this technique being used often is a red flag as opposed to a sign of compatibility (i.e., why does someone still exist that you can't convert to use the new schemas?)

I won't lie to you and tell you that you can mitigate data/schema changes such that you never have to migrate but in showing some examples of data and schema changes we can provide some context to help you better know and understand when a migration is required. Let's start with this contract; we'll start with JSON and then I'll show the same with SQL.

```json
{
    "employee" : {
        "id": "86fa2f09-d260-11ec-bd5d-0242c0a8e002",
        "first_name": "Mayuri",
        "last_name": "Kurotsuchi",
        "email_address": "Mayuri.Kurotsuchi@viz.com",
        "last_updated": 1749403404000,
        "last_updated_by": "sql-blog-migration",
        "version": 1
    }
}
```

This is an "employee" which in terms of domain analysis (from the womb to the tomb); should experience the following:

- an employee will be created
- that employee will be "unique" via their email address
- we may need to add more properties to the employee in the future, but are certain that the email address will be the natural key for an employee
- we want to avoid a situation where email addresses are used "on the wire" for applications involveding employees, so we want a unique id that will serve as a surrogate key and be safe to travel on the wire
- we have a desire to be able to audit when a given employee was last modified (and knowledge of what was modified); we've included the audit fields last_updated, last_updated_by and version to this effect
- we will start with the fields first name, last name and email address
- we expect to search for an employee via first name, last name and email address, but expect only email address to be the only field that will always return one or zero rows
- we expect that when an employee leaves the company, their employee record will be deleted (and ostensibly their email address can be re-used within the context of the database)
- we expect that we're at the mercy of HR, but will do our best to adhere to our initial domain analysis

With this in mind, we can put together the following sql:

```sql
-- DROP DATABASE IF EXISTS sql_blog_migration;
CREATE DATABASE IF NOT EXISTS sql_blog_migration;

-- use the database
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
    UNIQUE(email_address),
    INDEX idx_aux_id (aux_id)
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

The above sql implements the domain analysis we did earlier:

- the employees table provides an id, first/last name and email address (along with audit info) for a given employee
- id being a uuid/guid and a primary key ensures that this surrogate key is unique for every row
- the unique clause on email addresses ensures that no two employees can have the same email address
- the employees_audit table keeps track of individual mutations of every employee, it's primary key being a combination of the employee id and version
- the triggers ensure that every time an employee is inserted or updated, the employees_audit table has an updated row

You can "inject" some data by executing the following sql:

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

This will be our starting point for when we discuss manual and automatic migration.

## Migration Do's and Don'ts

As you (like me), may be very new to migrations, I wanted to go over some basic dos and don'ts for database migration. To provide some context or glue, all of the do's and don'ts are motivated by the idea that you:

- shouldn't perform any operations that _destroy_ data
- shouldn't perform any operations that can _potentially_ destroy relationships
- shouldn't perform any operations that put the database in an inconsistent state for an extended period of time

The kinds of operations that can destroy data are:

- column/table drops
- modification of a column type such that it truncates the data
- modification of a column type such that it's data is no longer compatible

The kinds of operations that can destroy relationships are:

- modification of any key or id (i.e., foreign/primary keys)
- moving a table to another database (MySQL) or schema (Postgres)

I'm not saying that it's impossible to do any of the above, i'm just saying that whenever you perform a migration that can _potentially_ destroy data or relationships, you create opportunities to be unsuccessful.

Things that are within the realm of reason when it comes to migrations are:

- adding new [nullable] column
- increasing column size
- adding/removing index
- adding constraints (with some caveats)

Again, these operations are safe(r) because they are less likely to destroy data and there's less opportunity for significant database downtime; certain operations can cause the database/table to be unavailable while the change is occurring.

Finally, one of the biggest don'ts for a migration is NOT to migrate down. Once you've performed the migration, verified that it works as expected and you've unlocked the table; you can't easily and __shouldn't__ revert the changes. This is an important "step" when doing the [domain analysis](#data-architecture-domain-analysis) that comes with performing a migration.

> Although I will mention this again, once you've completed a migration and unlocked the tables, it can be accessed and that "new" data may depend on the changes that you've made to the table/schema such that migrating down would require destroying data

## Backing up the Database

From my IT background, I know that it's VERY important to ALWAYS backup before doing anything...so you have a way to attempt to undo what you did; a backup will ensure that your data is "correct", but that doesn't always mean it's simple to restore/undo what you did. Sometimes it may take longer to perform a restore than to successfully complete the migration.

This command can be used to backup the sql_blog_migration database:

```sh
mysqldump -u root -p sql_blog_migration > /tmp/sql_blog_migration.sql
```

## Manual Migration

The purpose of this section is to show how we'd perform migration manually. I come from a background where there was only first/second-party support and in general, when you wanted a tool or functionality it was much faster to build your own then to look for someone else's solution and tweak it for your use case. As Golang is has MUUUCH better support than LabVIEW; I don't have the same problem, but it's evolution is that I always want to know how I'd go about doing it manually just in case.

This section is going to be use-case driven and will only go over the migrations that are practical/safe. I KNOW there are migrations that are unsafe or...just possible, but I don't want them to distract from the topic at hand and to avoid giving you bad habits, I won't.

### Manually: adding middle_name column

What if we wanted to add a new column to allow adding of a middle name. We can "manually" make this change to the employees table by executing a number of steps:

1. lock the table(s) to prevent modification while migrating
2. update the employees table to add middle_name column
3. update the employees_audit table to add middle_name column
4. drop the existing insert trigger since it won't include middle_name
5. re-create the trigger for insert
6. drop the existing update trigger since it won't include middle_name
7. re-create the trigger for update
8. perform verification that the change doesn't modify updates/inserts
9. and that you can select existing data
10. unlock the tables so they can be modified

One of the caveats to keep in mind is that we HAVE to lock the table otherwise you may get some inconsistency with the audit tables (any newly inserted/updated rows could be missed or not include the middle name if provided). This is what the SQL would look like:

```sql
-- lock the table to prevent modification while migrating
LOCK TABLES employees_audit WRITE, employees WRITE;

-- update the employees table to add middle_name column
ALTER TABLE employees ADD COLUMN middle_name VARCHAR(50) DEFAULT '';

-- update the employees_audit table to add middle_name column
ALTER TABLE employees_audit ADD COLUMN middle_name VARCHAR(50) DEFAULT '';

-- drop the existing insert trigger since it won't include middle_name
DROP TRIGGER employees_audit_insert;

-- re-create the trigger for insert
CREATE TRIGGER employees_audit_insert
AFTER INSERT ON employees FOR EACH ROW
    INSERT INTO employees_audit(employee_id, first_name, last_name, email_address, version, last_updated, last_updated_by, middle_name)
     VALUES (new.id, new.first_name, new.last_name, new.email_address, new.version, new.last_updated, new.last_updated_by, new.middle_name);

-- drop the existing update trigger since it won't include middle_name
DROP TRIGGER employees_audit_update;

-- re-create the trigger for update
CREATE TRIGGER employees_audit_update
AFTER UPDATE ON employees FOR EACH ROW
    INSERT INTO employees_audit(employee_id, first_name, last_name, email_address, version, last_updated, last_updated_by, middle_name)
     VALUES(new.id, new.first_name, new.last_name, new.email_address, new.version, new.last_updated, new.last_updated_by, new.middle_name);

-- perform verification that the change doesn't modify updates/inserts
-- and that you can select existing data

-- unlock the tables so they can be modified
UNLOCK TABLES;
```

The above solution is not the ONLY possible solution; there are a myriad of different ways, but one of the techniques you'll see employed often is the idea of ETL: Extract (Select), Transform (Change), Load (Insert) to reduce overall downtime and "automatically" do some of the background maintenance you have to do for tables. For certain changes to be "performant" you have to perform admin operations like vacuuming to "reclaim" the space on disk. Additionally, creating new tables and swapping the names of old tables is significantly faster and can reduce downtime significantly.

Below, we'll create a migration effort that uses the ETL technique:

1. lock the table so they can't be modified while we're making changes
2. create a "new" employees table with the additional column for middle-name
3. lock the "new" employee table so there are no hiccups
4. select the data from the current employees table and insert into the new employees table
5. create a "new" employees_audit table with the additional column for middle-name
6. lock the "new" employee_audit table so there are no hiccups
7. select the data from the current employees table and insert into the new employees table
8. drop the existing triggers
9. rename the tables
10. re-create the triggers
11. perform verification that the change doesn't modify updates/inserts and that you can select existing data
12. drop the tables if you no longer need them
13. unlock the tables so they can be used again

This is what the SQL would look like:

```sql
-- lock the tables so they can't be modified while we're
-- making changes
LOCK TABLES employees_audit WRITE, employees WRITE;

-- create a "new" employees table with the additional
-- column for middle-name
CREATE TABLE IF NOT EXISTS employees_new (
    id VARCHAR(36) PRIMARY KEY NOT NULL DEFAULT (UUID()),
    first_name VARCHAR(50) DEFAULT '',
    last_name VARCHAR(50) DEFAULT '',
    email_address VARCHAR(50) NOT NULL,
    aux_id BIGINT AUTO_INCREMENT,
    version INT NOT NULL DEFAULT 1,
    last_updated DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    last_updated_by VARCHAR(25) NOT NULL DEFAULT CURRENT_USER,
    middle_name VARCHAR(50) DEFAULT '',
    UNIQUE(email_address),
    INDEX idx_aux_id (aux_id)
) ENGINE = InnoDB;

-- lock the "new" table so there are no hiccups
LOCK TABLES employees_new WRITE;

-- select the data from the current employees table and insert into
-- the new employees table
INSERT INTO employees_new (id, first_name, last_name, email_address, aux_id, version, last_updated, last_updated_by) SELECT id, first_name, last_name, email_address, aux_id, version, last_updated, last_updated_by FROM employees;

-- create a "new" employees_audit table with the additional
-- column for middle-name
CREATE TABLE IF NOT EXISTS employees_audit_new (
    employee_id VARCHAR(36) NOT NULL,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    email_address VARCHAR(50),
    version INT NOT NULL,
    last_updated DATETIME(6) NOT NULL,
    last_updated_by VARCHAR(25) NOT NULL,
    middle_name VARCHAR(50),
    PRIMARY KEY (employee_id, version),
    FOREIGN KEY (employee_id) REFERENCES _employees(id) ON DELETE CASCADE
) ENGINE = InnoDB;

-- lock the "new" table so there are no hiccups
LOCK TABLES employees_audit_new WRITE;

-- select the data from the current employees table and insert into
-- the new employees table
INSERT INTO employees_audit_new (employee_id, first_name, last_name, email_address, version, last_updated, last_updated_by) SELECT employee_id, first_name, last_name, email_address, version, last_updated, last_updated_by FROM employees_audit;

-- drop the existing triggers
DROP TRIGGER employees_audit_insert;
DROP TRIGGER employees_audit_update;

-- rename the tables
rename table employees_audit to employees_audit_old
rename table employees_audit_new to employees_audit;
rename table employees to employees_old;
rename table employees_new to employees;

-- re-create the triggers
CREATE TRIGGER employees_audit_insert
AFTER INSERT ON employees FOR EACH ROW
    INSERT INTO employees_audit(employee_id, first_name, last_name, email_address, version, last_updated, last_updated_by, middle_name)
     VALUES (new.id, new.first_name, new.last_name, new.email_address, new.version, new.last_updated, new.last_updated_by, new.middle_name);
CREATE TRIGGER employees_audit_update
AFTER UPDATE ON employees FOR EACH ROW
    INSERT INTO employees_audit(employee_id, first_name, last_name, email_address, version, last_updated, last_updated_by, middle_name)
     VALUES(new.id, new.first_name, new.last_name, new.email_address, new.version, new.last_updated, new.last_updated_by, new.middle_name);

-- perform verification that the change doesn't modify updates/inserts
-- and that you can select existing data

-- drop the tables if you no longer need them
DROP TABLE employees_audit_old;
DROP TABLE employees_old;

-- unlock the tables so they can be used again
UNLOCK TABLE;
```

I can't stress how important verification is; once you've made your changes, you need to verify that they're successful; in this case if you did the following, you could feel fairly certain that you haven't broken anything:

1. insert into the employees table without middle_name
2. verify that the employess_audit table is updated with the version of the employee just inserted
3. update the employees table to update the middle_name
4. verify that the employees_audit table is updated with the version of the employee just updated
5. delete employee just updated (so we can re-use it)
6. verify that employee is no longer present in audit table (due to hard delete)
7. insert into the employees table with middle_name
8. verify that the employess_audit table is updated with the version of the employee just inserted
9. delete employee just inserted
10. verify that employee is no longer present in audit table (due to hard delete)

In SQL, this would look like:

```sql
-- insert into the employees table without middle_name
INSERT INTO employees(first_name, last_name, email_address) VALUES('Yasutora', 'Sado', 'Yasutora.Sado@viz.com');

-- verify that the employess_audit table is updated with the version of the employee just inserted
SELECT * FROM employees_audit WHERE email_address = 'Yasutora.Sado@viz.com';

-- update the employees table to update the middle_name
UPDATE employees SET middle_name = 'no_middle_name' WHERE email_address = 'Yasutora.Sado@viz.com';

-- verify that the employees_audit table is updated with the version of the employee just updated
SELECT * FROM employees_audit WHERE email_address = 'Yasutora.Sado@viz.com';

-- delete employee just updated (so we can re-use it)
DELETE FROM employees WHERE email_address = 'Yasutora.Sado@viz.com';

-- verify that employee is no longer present in audit table (due to hard delete)
SELECT * FROM employees_audit WHERE email_address = 'Yasutora.Sado@viz.com';

-- insert into the employees table with middle_name
INSERT INTO employees(first_name,middle_name, last_name, email_address) VALUES('Yasutora', 'no_middle_name', 'Sado', 'Yasutora.Sado@viz.com');

-- verify that the employess_audit table is updated with the version of the employee just inserted
SELECT * FROM employees_audit WHERE email_address = 'Yasutora.Sado@viz.com';

-- delete employee just inserted
DELETE FROM employees WHERE email_address = 'Yasutora.Sado@viz.com';

-- verify that employee is no longer present in audit table (due to hard delete)
SELECT * FROM employees_audit WHERE email_address = 'Yasutora.Sado@viz.com';
```

Remember the earlier conversation we had about NOT wanting to destroy data and a related conversation we had about the idea that migrations could go both ways, but generally they only went forward? Keep in mind that although this is a "forward compatible" migration to "undo" or revert this migration, you have to destroy data (and break a contract); so although you could revert this change, once you unlock the database, you can't do so without destroying data. I use this example to mostly make you aware of what's going on. MySQL won't always tell you that you're destroying data, it'll just do it, so you have to keep that in mind.

### Manually: adding new indexes

Indexes can increase the overall performance when reading data from a given table. Indexes have a "cost" in that they are pre-compiled and take disk space. From a domain analysis perspective, we could say that feedback from HR indicates that they expect to search by first name + last name and __NOT__ in terms of auditing. Currently our table has zero indexes, so we'll create an index for first name and last name.

This (by comparison) is probably the easiest thing to do; we accomplish it by doing the following:

1. lock the table(s) to prevent modification while doing the migration
2. alter the table to add the index
3. use explain to confirm that the index is being used in the expected queries
4. unlock the table

Note that I didn't mention a verification step; the expectation is that you did your due-diligence prior to and confirmed that the addition of the index will reduce the overall query time; this is a strong assumption (and beyond the scope of this repository...but if you're curious about what this looks like, take a look at: [https://github.com/antonio-alexander/sql-blog-indexing](https://github.com/antonio-alexander/sql-blog-indexing)).

In SQL, this migration would look like the following:

```sql
-- lock the tables so they can't be modified while we're modifying it
LOCK TABLES employees WRITE;

-- create a composite index with first_name and last_name
CREATE INDEX idx_first_last_name ON employees(first_name, last_name);

-- verify that the index has been created
SHOW INDEXES FROM employees;

-- use explain to confirm that the index is being used in the expected queries
EXPLAIN SELECT * FROM employees WHERE first_name='Ichigo' AND last_name='Kurosaki';

-- unlock the tables since we're finished
UNLOCK TABLES;
```

You don't have to explicitly lock the tables when doing this, but creating indexes may cause an automatic table lock to prevent modification of the table while adding the index, for sufficiently large tables, this could take a significant amount of time. This is something you can ballpark by doing a dump of the table and attempting to add the index on a machine with similar resources/load.

### Manually: adding new constraint

Let's say that hypothetically, we do some retro active domain analysis; departments have integrated with the database and we've found that for some reason (outside the scope of the database), data entry is error prone such that the first name is blank and the middle name is the _first name_. In practice, all three fields are concatenated together with a space so it _looks_ correct, but when they search (remember the [index](#manually-adding-new-indexes) we created earlier) using first name and last name, because the first name is blank not only does the query not work, but it also doesn't use the expected index.

We can solve both of these problems by adding one (or more) check constraints to ensure that the first (and last) name are never blank and that the first and middle name are not the same. This is at odds with the initial table setup for employees, so we can't JUST add the checks, we also have to modify the table to enforce this paradigm by doing the following:

- ensure that first name is not nullable (and doesn't default to empty)
- ensure that last name is not nullable (and doesn't default to empty)
- ensure that middle name is not nullable and defaults to empty

These have to be done to not conflict with the checks (logically). To make these modifications, we have to do the following:

1. lock the table so no-one else can modify it
2. verify that the situation for violating each check is possible
3. update the existing table to ensure no violations of the checks exist
4. alter the table to ensure that first name is not nullable and doesn't default to empty
5. alter the table to ensure that last name is not nullable and doesn't default to empty
6. alter the table to ensure that middle name is not nullable and defaults to empty
7. alter the table to add the checks to the table
8. verify that the situation for violating each check is no longer possible
9. unlock the table

> You might not know without trying, but MySQL doesn't like inconsistency (well...databases in general); so if you attempt to create a check and even one row violates that check, you have to fix it before creating the check (or you'll get an error). Additionally checks work on insert AND update

In SQL, this migration would look like the following:

```sql
-- lock the table so no-one else can modify it
LOCK TABLES employees WRITE;

-- verify that the situation for violating each check is possible
--  insert an employee with no first name/last name
--  insert an employee with an empty first name/last name
--  insert an employee with the same first and middle name
--  update an employee with no first name/last name
--  update an employee with an empty first name/last name
--  update an employee with the same first and middle name

-- alter the table to ensure that first name is not nullable and doesn't default to empty
ALTER TABLE employees MODIFY COLUMN first_name VARCHAR (50) NOT NULL;

-- alter the table to ensure that last name is not nullable and doesn't default to empty
ALTER TABLE employees MODIFY COLUMN last_name VARCHAR (50) NOT NULL;

-- alter the table to ensure that middle name is not nullable and defaults to empty
ALTER TABLE employees MODIFY COLUMN middle_name VARCHAR (50) NOT NULL DEFAULT '';

-- update the existing table to ensure no violations of the checks exist

-- alter the table to add the checks to the table
ALTER TABLE employees
    ADD CONSTRAINT chk_first_last_name CHECK (first_name != '' AND last_name != '');
ALTER TABLE employees
    ADD CONSTRAINT chk_first_middle_name CHECK (first_name != middle_name);

-- verify that the situation for violating each check is no longer possible
--  insert an employee with no first name/last name
--  insert an employee with an empty first name/last name
--  insert an employee with the same first and middle name
--  update an employee with no first name/last name
--  update an employee with an empty first name/last name
--  update an employee with the same first and middle name

-- unlock the table
UNLOCK TABLES;
```

## Automatic Migration Using Goose

Through those examples, you should have an idea of how you'd accomplish migration manually, but now you may want to automate the process so it's one click up and one click down; you may also realize that some of your offline installations may be MANY migrations behind where you are currently. Being able to automate those migrations (that have been thoroughly tested) may reduce your administrative overhead as you can schedule and plan those mass migrations to be done at the click of a button rather than having to log into each and every installation. In this section we'll be making some strong assumptions, but I think they'll push you in one direction to simplify/automate this process:

- we'll create a customer MySQL Docker image
- our Docker image will have the most recent schema on it
- our Docker image will have a startup script that will automatically migrate the database from whatever state it's in to the most recent schema

Our tool of choice will be [Goose](https://github.com/pressly/goose) because it does a lot of the work for us. Before we can start doing stuff, we'll need to install goose and then validate it's connection to the database:

```sh
make check-goose
goose version
goose mysql "root:mysql@/sql_blog_migration?parseTime=true&&multiStatements=true" status
```

Once we have goose installed we can start the processes of create migrations for Goose.

### Automatically: adding a middle_name column

We're going to automate our initial migration of changing the id field from a string to an integer. Once we've installed goose, we'll need to go into the migration folder and create a new migration (starting from the root of the repo):

```sh
goose create add_middle_name_column sql
```

This should create a file prefixed with a timestamp; the sql file is initially empty (see below):

```sql
-- +goose Up
-- +goose StatementBegin
-- lock the table to prevent modification while migrating
LOCK TABLES employees_audit WRITE, employees WRITE;

-- update the employees table to add middle_name column
ALTER TABLE employees ADD COLUMN middle_name VARCHAR(50) DEFAULT '';

-- update the employees_audit table to add middle_name column
ALTER TABLE employees_audit ADD COLUMN middle_name VARCHAR(50) DEFAULT '';

-- drop the existing insert trigger since it won't include middle_name
DROP TRIGGER employees_audit_insert;

-- re-create the trigger for insert
CREATE TRIGGER employees_audit_insert
AFTER INSERT ON employees FOR EACH ROW
    INSERT INTO employees_audit(employee_id, first_name, last_name, email_address, version, last_updated, last_updated_by, middle_name)
     VALUES (new.id, new.first_name, new.last_name, new.email_address, new.version, new.last_updated, new.last_updated_by, new.middle_name);

-- drop the existing update trigger since it won't include middle_name
DROP TRIGGER employees_audit_update;

-- re-create the trigger for update
CREATE TRIGGER employees_audit_update
AFTER UPDATE ON employees FOR EACH ROW
    INSERT INTO employees_audit(employee_id, first_name, last_name, email_address, version, last_updated, last_updated_by, middle_name)
     VALUES(new.id, new.first_name, new.last_name, new.email_address, new.version, new.last_updated, new.last_updated_by, new.middle_name);

-- unlock the tables so it can be modified
UNLOCK TABLES;
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot migrate down';
-- +goose StatementEnd
```

What we'll do from here is copy+paste the code we created above in the [Manual Migration](#manual-migration) section for goose up to migrate forward (from wherever it is currently to the most recent migration). It'll look like the following:

```sql
-- +goose Up
-- +goose StatementBegin
-- lock the table to prevent modification while migrating
LOCK TABLES employees_audit WRITE, employees WRITE;

-- update the employees table to add middle_name column
ALTER TABLE employees ADD COLUMN middle_name VARCHAR(50) DEFAULT '';

-- update the employees_audit table to add middle_name column
ALTER TABLE employees_audit ADD COLUMN middle_name VARCHAR(50) DEFAULT '';

-- drop the existing insert trigger since it won't include middle_name
DROP TRIGGER employees_audit_insert;

-- re-create the trigger for insert
CREATE TRIGGER employees_audit_insert
AFTER INSERT ON employees FOR EACH ROW
    INSERT INTO employees_audit(employee_id, first_name, last_name, email_address, version, last_updated, last_updated_by, middle_name)
     VALUES (new.id, new.first_name, new.last_name, new.email_address, new.version, new.last_updated, new.last_updated_by, new.middle_name);

-- drop the existing update trigger since it won't include middle_name
DROP TRIGGER employees_audit_update;

-- re-create the trigger for update
CREATE TRIGGER employees_audit_update
AFTER UPDATE ON employees FOR EACH ROW
    INSERT INTO employees_audit(employee_id, first_name, last_name, email_address, version, last_updated, last_updated_by, middle_name)
     VALUES(new.id, new.first_name, new.last_name, new.email_address, new.version, new.last_updated, new.last_updated_by, new.middle_name);

-- unlock the tables so they can be modified
UNLOCK TABLES;
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot migrate down';
-- +goose StatementEnd
```

Two things that are of note are: (1) that we're effectively disabling the ability to revert or migrate down by having the SIGNAL SQLSTATE; if you attempt to migrate down it'll execute an error and (2) there's no atomic way to verify between the steps (like we did during the manual migration).

To migrate up (forward) by one version, we can enter the following command:

```sh
goose mysql "root:mysql@/sql_blog_migration?parseTime=true&&multiStatements=true" up-by-one
```

It will have the following output:

```sh
2023/04/07 17:53:09 OK   20230407165454_add_middle_name_column.sql (1.12s)
```

Once the migration is done, you can also check the status of the migration with the following command:

```sh
goose mysql "root:mysql@/sql_blog_migration?parseTime=true&&multiStatements=true" status
```

```sh
2023/04/07 18:43:04     Applied At                  Migration
2023/04/07 18:43:04     =======================================
2023/04/07 18:43:04     Fri Apr  7 22:53:10 2023 -- 20230407165454_add_middle_name_column.sql
```

In case you wanted to know how Goose "works":

> Goose "knows" what version(s) of the database have been deployed by querying a goose specific table (the default is goose_db_version). It's possible to provide a specific table to goose with command arguments if you want to have different table versions within th same database.

### Automatically: adding new indexes

Similarly to how we did the previous migration, we'd go through the same steps to create a new migration file and populate it with the sql to perform the migration.

```sh
goose create add_new_index sql
```

The contents of the file will be as-such (from the [Manually: adding new indexes](#manually-adding-new-indexes)):

```sql
-- +goose Up
-- +goose StatementBegin
-- lock the tables so they can't be modified while we're modifying it
LOCK TABLES employees WRITE;

-- create a composite index with first_name and last_name
CREATE INDEX idx_first_last_name ON employees(first_name, last_name);

-- unlock the tables since we're finished
UNLOCK TABLES;
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot migrate down';
-- +goose StatementEnd
```

Similarly, you can execute the goose up-by-one and use goose status:

```sh
goose mysql "root:sql_blog_migration@tcp(localhost:3306)/sql_blog_migration?parseTime=true&&multiStatements=true" up-by-one
goose mysql "root:sql_blog_migration@tcp(localhost:3306)/sql_blog_migration?parseTime=true&&multiStatements=true" status
```

```sh
2023/04/07 19:42:57 OK   20230407185110_add_new_index.sql (60.57ms)
2023/04/07 19:43:01     Applied At                  Migration
2023/04/07 19:43:01     =======================================
2023/04/07 19:43:01     Fri Apr  7 22:53:10 2023 -- 20230407165454_add_middle_name_column.sql
2023/04/07 19:43:01     Sat Apr  8 00:42:57 2023 -- 20230407185110_add_new_index.sql
```

### Automatically: adding a new constraint

Again, we'd go through the same steps to create a new migration file and populate it with the sql to perform the migration.

```sh
goose create first_middle_last_name_constraints sql
```

The contents of the file will be as-such (from the [Manually: adding a new constraint](#manually-adding-new-constraint)):

```sql
-- lock the table so no-one else can modify it
LOCK TABLES employees WRITE;

-- alter the table to ensure that first name is not nullable and doesn't default to empty
ALTER TABLE employees MODIFY COLUMN first_name VARCHAR (50) NOT NULL;

-- alter the table to ensure that last name is not nullable and doesn't default to empty
ALTER TABLE employees MODIFY COLUMN last_name VARCHAR (50) NOT NULL;

-- alter the table to ensure that middle name is not nullable and defaults to empty
ALTER TABLE employees MODIFY COLUMN middle_name VARCHAR (50) NOT NULL DEFAULT '';

-- update the existing table to ensure no violations of the checks exist

-- alter the table to add the checks to the table
ALTER TABLE employees
    ADD CONSTRAINT chk_first_last_name CHECK (first_name != '' AND last_name != '');
ALTER TABLE employees
    CONSTRAINT chk_first_middle_name CHECK (first_name != middle_name),

-- unlock the table
UNLOCK TABLES;
```

Similarly, you can execute the goose up-by-one and use goose status:

```sh
make goose-status
make goose-up-by-one
make goose-status
```

```sh
antonio-alexander@penguin:~/src/github.com/antonio-alexander/sql-blog-migration$ make goose-status
2025/06/13 04:26:15     Applied At                  Migration
2025/06/13 04:26:15     =======================================
2025/06/13 04:26:15     Fri Apr  7 22:53:10 2023 -- 20230407165454_add_middle_name_column.sql
2025/06/13 04:26:15     Sat Apr  8 00:42:57 2023 -- 20230407185110_add_new_index.sql
2025/06/13 04:26:15     Pending                  -- 20250611170303_first_middle_last_name_constraints.sql
antonio-alexander@penguin:~/src/github.com/antonio-alexander/sql-blog-migration$ make goose-up-by-one
2025/06/13 04:26:20 OK   20250611170303_first_middle_last_name_constraints.sql (407.96ms)
antonio-alexander@penguin:~/src/github.com/antonio-alexander/sql-blog-migration$ make goose-status
2025/06/13 04:26:23     Applied At                  Migration
2025/06/13 04:26:23     =======================================
2025/06/13 04:26:23     Fri Apr  7 22:53:10 2023 -- 20230407165454_add_middle_name_column.sql
2025/06/13 04:26:23     Sat Apr  8 00:42:57 2023 -- 20230407185110_add_new_index.sql
2025/06/13 04:26:23     Fri Jun 13 04:26:20 2025 -- 20250611170303_first_middle_last_name_constraints.sql
antonio-alexander@penguin:~/src/github.com/antonio-alexander/sql-blog-migration$ 
```

## Integration (a complete solution)

This section won't be as interactive as the other sections, but I'll include the example code within this repository. You may be going through this entire repo and wonder to yourself, how would I put all of this together to create a solution that's maintainable, auditable and reasonable to allow other people to migrate "offline" databases?

TLDR; we use the following solutions to "solve" this problem:

- we use Docker to create a versioned image that will contain the database, starting sql AND migration scripts
- we use a two-stage docker build to build goose for the appropriate architecture and inject into the final image
- on start we run a script that will attempt to migrate the database as needed

This isn't a very complex solution (when you know what you're looking at) and borrows heavily from [https://github.com/antonio-alexander/go-bludgeon/tree/main/mysql](https://github.com/antonio-alexander/go-bludgeon/tree/main/mysql). Some of the things we've modified are:

1. installing goose to the Dockerfile when building
2. the docker-entrypoint script to create the initial database (if it doesn't already exist)
3. the auto_migration script to run goose up once the MySQL service is running

Although it's totally possible to load mysql from scratch, starting from yobasystems/alpine-mariadb is much easier and is a good starting point too.

[run.sh](./cmd/run.sh): this file replaces the startup script for the image, we've made some modifications from the [original](https://github.com/yobasystems/alpine-mariadb/blob/master/alpine-mariadb-armhf/files/run.sh) so that it executes our scripts and sql files in the appropriate context:

- on startup, if no database currently exists, it will create the MYSQL_DATABASE database
- on startup, if no database currently exists, it will create the sql_blog_employees database associated with the __configured__ version of the employees database
- the post install scripts are run AFTER mysql is up and running (and accessible via mysqladmin ping)
- if auto migration is enabled, it'll automatically execute goose up

The [Dockerfile](./cmd/Dockerfile) is a two stage build that will generate the executable for goose and then inject it into the mariadb image with our updated scripts. Some of the important aspects of this dDockerfile:

- we use sed to clean up the sql and shell scripts to fix the line endings
- we install goose in a separate stage so there's no go dependencies in the output image
- goose is installed using a slightly interesting trick, this should work for amd64 (intel) and arm images
- we copy over multiple copies of employees.sql with 003_employees.sql being the default

The [docker-compose.yml](./docker-compose.yml) puts everything together to both build and run the image with defaults:

- you can use this to build and run the mysql image

The sql files [001_employees.sql](./cmd/sql/001_employees.sql), [002_employees.sql](./cmd/sql/002_employees.sql), [003_employees.sql](./cmd/sql/003_employees.sql), and [004_employees.sql](./cmd/sql/004_employees.sql) are used to load a specific version of the employees database:

- 001_employees.sql will load the base table without ANY migrations
- 002_employees.sql will load the base table with [20230407165454_add_middle_name_column.sql](./cmd/sql/migration/20230407165454_add_middle_name_column.sql) migration applied
- 003_employees.sql will load the base table with [20230407165454_add_middle_name_column.sql](./cmd/sql/migration/20230407165454_add_middle_name_column.sql) and [20230407185110_add_new_index.sql](./cmd/sql/migration/20230407185110_add_new_index.sql) applied
- 004_employees.sql will load the base table with [20230407165454_add_middle_name_column.sql](./cmd/sql/migration/20230407165454_add_middle_name_column.sql), [20230407185110_add_new_index.sql](./cmd/sql/migration/20230407185110_add_new_index.sql) and [20250611170303_first_middle_last_name_constraints.sql](./cmd/sql/migration/20250611170303_first_middle_last_name_constraints.sql) applied.

With these solutions above, you should be able to run the make build command and have a local image you can use to interact with sql_blog_migration.

Something you may notice is that in practice, you can get inconsistent behavior with goose on new databases. I think in general, for "new" installations, you wouldn't want to apply a really old version of the database, and then migrate it through the steps (although this does work). It'd make more sense to simply apply the latest version of the database (since there's "nothing" to migrate). Something you may notice is that even though the database is up-to-date, when you run goose, it'll attempt to migrate as if you were running the older version of the database; goose assumes that no migrations have occurred, so it'll attempt to run all of the migrations.

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
INSERT INTO employees_goose_db_version(id, version_id, is_applied, tstamp) VALUES
    ('1','0','1','2023-04-07 22:53:09'),
    ('2','20230407165454','1','2023-04-07 22:53:10'),
    ('3','20230407185110','1','2023-04-08 00:42:57'),
    ('4','20250611170303','1','2025-06-12 00:49:04');
```

As a result, part of the workflow for updating your sql image/dependencies, must be to ALSO manage one or more tables associated with the goose db version. You may also ask yourself, "Do I need to organize my tables to be in their own databases?" the short answer is no, but you have to be a little more creative in how you organize things since you can add an argument to goose to set the table.

```sh
goose mysql "root:<PASSWORD>@tcp(localhost:3306)/sql_blog_migration?parseTime=true&&multiStatements=true" --table employees_goose_db_version status
```

This gives you a bit more flexibility in how you organize your migration files; you won't be limited to a single database or schema.

## Security Considerations

I think this comes with any kind of database how-to/opinion; in an ideal situation you'd migrate using a user with the specific permissions needed to do that migration with that database. This takes some significant effort (to figure out what permissions are needed). I took a shortcut in that I granted all access to the database to MYSQL_USER; in practice this may not be reasonable. Although I think you'll only have to do it once, if you care about security in your offline (and online/cloud) databases; this should be really high on your list of things to do.

As an aside (this is totally my opinion); it's __better__ to separate code that performs DDL (data definition langauge) from code that performs DML (data markup language). Its _TOTALLY_ possible...and easy to integrate goose into your application's executable and on startup have it perform the migration. This has a handful of problems:

- you _should_ provide your application with a set of credentials that can perform DML and DDL commands
- depending on your orchestration tool (e.g., Docker, Kubernetes); there may be situations (out of your control) that would abort the migration process and leave the database in a broken state (requiring manual intervention/recovery)
- if your orchestration tool generates multiple instances, you have to worry about multiple instances of the migration running simultaneously or you'll need some way to synchronize the goose process. Alter commands can be done within a lock, but it takes significantly more effort to make migrations idempotent

This opinion is rather inherent the [Integration (a complete solution)](#integration-a-complete-solution) section; I specifically integrated goose into the custom mysql image, rather than the application that would interact with the table. Although this solution is one specific to "offline" databases, the work to get there would provide the following benefits:

- you could migrate separately from deploying/updating the application (you uncouple the two activities)
- you can protect the elevated credentials required to perform DDL operations from those needed to perform DML
- you can avoid the synchronization issue that may result depending on your orchestration tool
- you have an opportunity to perform validation prior to making the database ready for public consumption

Your results may vary, but a "one-size-fits-all" solution doesn't scale well when you need it to.

## Issues Found Worth Mentioning

This is a list of issues I found while putting this together; it may give you more context or communicate an "a-ha" moment:

- the original run.sh script would execute sql using mysqld directly using skip-names, so the definer would be set to a user that didn't exist and the migration would fail unless you dropped the view, re-created it, and THEN ran the migration

> to resolve this issue, I modified the run.sh script to execute the sql scripts as a known user rather than using mysqld behind the scenes; it was an easy problem to resolve interactively by dropping the view and re-creating it, but was almost impossible to automate. I think in most online databases, this isn't an issue, but in an offline database, it's paramount to be able to automate first-time database creation.
