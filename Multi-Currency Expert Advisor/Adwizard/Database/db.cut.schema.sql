--
-- @version 1.00
--
PRAGMA foreign_keys = off;
BEGIN TRANSACTION;

-- Table: passes
DROP TABLE IF EXISTS passes;

CREATE TABLE passes (
    id_pass               INTEGER  PRIMARY KEY AUTOINCREMENT,
    params                TEXT
);

COMMIT TRANSACTION;
PRAGMA foreign_keys = on;
