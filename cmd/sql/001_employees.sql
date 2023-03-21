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
    last_updated_by VARCHAR(128) NOT NULL DEFAULT CURRENT_USER,
    UNIQUE(email_address),
    INDEX idx_aux_id (aux_id)
) ENGINE = InnoDB;

-- DROP TABLE IF EXISTS employees_audit;
CREATE TABLE IF NOT EXISTS employees_audit (
    employee_id VARCHAR(36) NOT NULL,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    email_address VARCHAR(50),
    version INT NOT NULL,
    last_updated DATETIME(6) NOT NULL,
    last_updated_by VARCHAR(128) NOT NULL,
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

-- DROP TABLE IF EXISTS employees_goose_db_version;
CREATE TABLE IF NOT EXISTS employees_goose_db_version (
    id BIGINT(20) UNSIGNED PRIMARY KEY AUTO_INCREMENT NOT NULL,
    version_id BIGINT(20) NOT NULL,
    is_applied TINYINT(1) NOT NULL,
    tstamp TIMESTAMP NULL DEFAULT current_timestamp() 
) ENGINE = InnoDB;

-- INSERT this for goose that hasn't been migrated at all
INSERT INTO employees_goose_db_version(id, version_id, is_applied, tstamp) VALUES
    ('1','0','1','2023-04-07 22:53:09');
