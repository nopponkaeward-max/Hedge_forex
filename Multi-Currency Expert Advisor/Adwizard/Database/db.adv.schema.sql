--
-- @version 1.00
--

PRAGMA foreign_keys = off;
BEGIN TRANSACTION;

-- Table: storage
DROP TABLE IF EXISTS storage;

CREATE TABLE storage (
    key         TEXT,
    value       TEXT,
    last_update TEXT,
    PRIMARY KEY (
        key
    )
);


-- Table: storage_orders
DROP TABLE IF EXISTS storage_orders;

CREATE TABLE storage_orders (
    strategy_hash  TEXT,
    strategy_index INTEGER,
    ticket         INTEGER,
    symbol         TEXT,
    lot            REAL,
    type           INTEGER,
    open_time      TEXT,
    open_price     REAL,
    stop_loss      REAL,
    take_profit    REAL,
    close_time     TEXT,
    close_price    REAL,
    expiration     INTEGER,
    comment        TEXT,
    point          REAL,
    PRIMARY KEY (
        strategy_hash,
        strategy_index
    )
);


-- Table: strategies
DROP TABLE IF EXISTS strategies;

CREATE TABLE strategies (
    id_strategy INTEGER PRIMARY KEY AUTOINCREMENT
                        NOT NULL,
    id_group    INTEGER REFERENCES strategy_groups (id_group) ON DELETE CASCADE
                                                              ON UPDATE CASCADE,
    hash        TEXT    NOT NULL,
    params      TEXT    NOT NULL
);


-- Table: strategy_groups
DROP TABLE IF EXISTS strategy_groups;

CREATE TABLE strategy_groups (
    id_group    INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT,
    from_date   TEXT,
    to_date     TEXT,
    create_date TEXT
);


-- Trigger: ins_create_date_null
DROP TRIGGER IF EXISTS ins_create_date_null;
CREATE TRIGGER ins_create_date_null
         AFTER INSERT
            ON strategy_groups
          WHEN NEW.create_date IS NULL
BEGIN
    UPDATE strategy_groups
       SET create_date = DATETIME('NOW') 
     WHERE id_group = NEW.id_group;
END;


-- Trigger: ins_storage
DROP TRIGGER IF EXISTS ins_storage;
CREATE TRIGGER ins_storage
         AFTER INSERT
            ON storage
          WHEN NEW.last_update IS NULL
BEGIN
    UPDATE storage
       SET last_update = DATETIME('NOW') 
     WHERE key = NEW.key;
END;


-- Trigger: upd_storage
DROP TRIGGER IF EXISTS upd_storage;
CREATE TRIGGER upd_storage
        BEFORE UPDATE
            ON storage
          WHEN NEW.last_update IS NULL
BEGIN
    UPDATE storage
       SET last_update = DATETIME('NOW') 
     WHERE key = NEW.key;
END;


COMMIT TRANSACTION;
PRAGMA foreign_keys = on;
