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

-- update the employee_v1 view to include the birth_date field
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
    birth_date,
    version,
    UNIX_TIMESTAMP(last_updated) AS last_updated,
    last_updated_by
FROM
    employees;
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

-- update the employee_v1 view to remove the birth_date field
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
