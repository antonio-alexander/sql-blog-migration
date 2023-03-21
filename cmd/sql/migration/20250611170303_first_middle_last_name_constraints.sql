-- +goose Up
-- +goose StatementBegin

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
    ADD CONSTRAINT chk_first_middle_name CHECK (first_name != middle_name);

-- unlock the table
UNLOCK TABLES;

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot migrate down';
-- +goose StatementEnd
