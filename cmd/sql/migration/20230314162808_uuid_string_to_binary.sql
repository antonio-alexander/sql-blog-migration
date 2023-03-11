-- +goose Up
-- +goose StatementBegin
-- lock the table to prevent modification while migrating
LOCK TABLES employees_audit WRITE, employees WRITE;

-- remove the foreign key so you can modify the foreign key in the employees table
ALTER TABLE employees_audit DROP FOREIGN KEY fk_employee_id;

-- edit and replace employees id with its binary representation
ALTER TABLE employees ADD COLUMN _id BINARY(16);
ALTER TABLE employees DROP PRIMARY KEY;
UPDATE employees SET employees._id = (UNHEX(REPLACE(employees.id, "-",""))) WHERE employees.id=employees.id;
ALTER TABLE employees DROP COLUMN id;
ALTER TABLE employees CHANGE COLUMN _id id BINARY(16);
ALTER TABLE employees MODIFY COLUMN id BINARY(16) PRIMARY KEY NOT NULL DEFAULT (unhex(replace(uuid(),'-','')));

-- edit and replace employees_audit id with its binary representation
ALTER TABLE employees_audit ADD COLUMN _id BINARY(16);
ALTER TABLE employees_audit DROP PRIMARY KEY;
UPDATE employees_audit SET employees_audit._id = (UNHEX(REPLACE(employees_audit.employee_id, "-",""))) WHERE employees_audit.employee_id=employees_audit.employee_id;
ALTER TABLE employees_audit DROP COLUMN employee_id;
ALTER TABLE employees_audit CHANGE COLUMN _id employee_id BINARY(16);
ALTER TABLE employees_audit MODIFY COLUMN employee_id BINARY(16) NOT NULL;
ALTER TABLE employees_audit ADD PRIMARY KEY (employee_id,version);
ALTER TABLE employees_audit ADD FOREIGN KEY fk_employee_id (employee_id) REFERENCES employees(id) ON DELETE CASCADE;

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
ALTER TABLE employees_audit DROP FOREIGN KEY fk_employee_id;

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
ALTER TABLE employees CHANGE COLUMN _id id VARCHAR(36);
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
ALTER TABLE employees_audit CHANGE COLUMN _id employee_id VARCHAR(36);
ALTER TABLE employees_audit MODIFY COLUMN employee_id VARCHAR(36) NOT NULL;
ALTER TABLE employees_audit ADD PRIMARY KEY (employee_id,version);
ALTER TABLE employees_audit ADD FOREIGN KEY fk_employee_id (employee_id) REFERENCES employees(id) ON DELETE CASCADE;

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
