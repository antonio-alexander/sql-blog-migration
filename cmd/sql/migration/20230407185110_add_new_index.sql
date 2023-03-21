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