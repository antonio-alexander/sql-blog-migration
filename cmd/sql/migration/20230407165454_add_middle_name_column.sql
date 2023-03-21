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
