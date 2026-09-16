--
-- @version 1.06
--
PRAGMA foreign_keys = off;
BEGIN TRANSACTION;

-- Table: jobs
DROP TABLE IF EXISTS jobs;

CREATE TABLE jobs (
    id_job        INTEGER PRIMARY KEY AUTOINCREMENT,
    id_stage      INTEGER REFERENCES stages (id_stage) ON DELETE CASCADE
                                                       ON UPDATE CASCADE
                          NOT NULL,
    symbol        TEXT    DEFAULT EURGBP,
    period        TEXT    DEFAULT H1,
    tester_inputs TEXT,
    status        TEXT    CHECK (status IN ('Queued', 'Process', 'Done') ) 
                          NOT NULL
                          DEFAULT Done
);


-- Table: passes
DROP TABLE IF EXISTS passes;

CREATE TABLE passes (
    id_pass               INTEGER  PRIMARY KEY AUTOINCREMENT,
    id_task               INTEGER  REFERENCES tasks (id_task) ON DELETE CASCADE,
    pass                  INTEGER,
    is_optimization       INTEGER  CHECK (is_optimization IN (0, 1) ),
    is_forward            INTEGER  CHECK (is_forward IN (0, 1) ),
    initial_deposit       REAL,
    withdrawal            REAL,
    profit                REAL,
    gross_profit          REAL,
    gross_loss            REAL,
    max_profittrade       REAL,
    max_losstrade         REAL,
    conprofitmax          REAL,
    conprofitmax_trades   REAL,
    max_conwins           REAL,
    max_conprofit_trades  REAL,
    conlossmax            REAL,
    conlossmax_trades     REAL,
    max_conlosses         REAL,
    max_conloss_trades    REAL,
    balancemin            REAL,
    balance_dd            REAL,
    balancedd_percent     REAL,
    balance_ddrel_percent REAL,
    balance_dd_relative   REAL,
    equitymin             REAL,
    equity_dd             REAL,
    equitydd_percent      REAL,
    equity_ddrel_percent  REAL,
    equity_dd_relative    REAL,
    expected_payoff       REAL,
    profit_factor         REAL,
    recovery_factor       REAL,
    sharpe_ratio          REAL,
    min_marginlevel       REAL,
    deals                 REAL,
    trades                REAL,
    profit_trades         REAL,
    loss_trades           REAL,
    short_trades          REAL,
    long_trades           REAL,
    profit_shorttrades    REAL,
    profit_longtrades     REAL,
    profittrades_avgcon   REAL,
    losstrades_avgcon     REAL,
    complex_criterion     REAL,
    custom_ontester       REAL,
    params                TEXT,
    inputs                TEXT,
    pass_date             DATETIME
);


-- Table: passes_clusters
DROP TABLE IF EXISTS passes_clusters;

CREATE TABLE passes_clusters (
    id_task INTEGER,
    id_pass INTEGER,
    cluster INTEGER
);


-- Table: projects
DROP TABLE IF EXISTS projects;

CREATE TABLE projects (
    id_project  INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT    NOT NULL,
    version     TEXT    NOT NULL,
    description TEXT,
    params      TEXT,
    status      TEXT    CHECK (status IN ('Queued', 'Process', 'Done') ) 
                        NOT NULL
                        DEFAULT Done
);


-- Table: stages
DROP TABLE IF EXISTS stages;

CREATE TABLE stages (
    id_stage               INTEGER PRIMARY KEY AUTOINCREMENT,
    id_project             INTEGER REFERENCES projects (id_project) ON DELETE CASCADE
                                                                    ON UPDATE CASCADE,
    id_parent_stage        INTEGER REFERENCES stages (id_stage) ON DELETE CASCADE
                                                                ON UPDATE CASCADE,
    name                   TEXT    NOT NULL
                                   DEFAULT (1),
    expert                 TEXT,
    symbol                 TEXT    NOT NULL
                                   DEFAULT EURGBP,
    period                 TEXT    NOT NULL
                                   DEFAULT H1,
    optimization           INTEGER NOT NULL
                                   DEFAULT (2),
    model                  INTEGER NOT NULL
                                   DEFAULT (2),
    from_date              DATE    NOT NULL
                                   DEFAULT ('2022.01.01'),
    to_date                DATE    NOT NULL
                                   DEFAULT ('2022.06.01'),
    forward_mode           INTEGER NOT NULL
                                   DEFAULT (0),
    forward_date           DATE,
    deposit                INTEGER NOT NULL
                                   DEFAULT (10000),
    currency               TEXT    NOT NULL
                                   DEFAULT USD,
    profit_in_pips         INTEGER NOT NULL
                                   DEFAULT (0),
    leverage               INTEGER NOT NULL
                                   DEFAULT (200),
    execution_mode         INTEGER NOT NULL
                                   DEFAULT (0),
    optimization_criterion INTEGER NOT NULL
                                   DEFAULT (7),
    status                 TEXT    CHECK (status IN ('Queued', 'Process', 'Done') ) 
                                   NOT NULL
                                   DEFAULT Done
);


-- Table: strategy_groups
DROP TABLE IF EXISTS strategy_groups;

CREATE TABLE strategy_groups (
    id_pass INTEGER REFERENCES passes (id_pass) ON DELETE CASCADE
                                                ON UPDATE CASCADE
                    PRIMARY KEY,
    name    TEXT
);


-- Table: tasks
DROP TABLE IF EXISTS tasks;

CREATE TABLE tasks (
    id_task                INTEGER  PRIMARY KEY AUTOINCREMENT,
    id_job                 INTEGER  NOT NULL
                                    REFERENCES jobs (id_job) ON DELETE CASCADE
                                                             ON UPDATE CASCADE,
    optimization_criterion INTEGER  DEFAULT (7) 
                                    NOT NULL,
    start_date             DATETIME,
    finish_date            DATETIME,
    max_duration           INTEGER  NOT NULL
                                    DEFAULT 0,
    status                 TEXT     NOT NULL
                                    DEFAULT Queued
                                    CHECK (status IN ('Queued', 'Process', 'Done') ) 
);


-- Trigger: insert_empty_job
DROP TRIGGER IF EXISTS insert_empty_job;
CREATE TRIGGER insert_empty_job
         AFTER INSERT
            ON stages
          WHEN NEW.name = 'Single tester pass'
BEGIN
    INSERT INTO jobs VALUES (
                         NULL,
                         NEW.id_stage,
                         NULL,
                         NULL,
                         NULL,
                         'Done'
                     );
    INSERT INTO tasks (
                          id_job,
                          optimization_criterion,
                          status
                      )
                      VALUES (
                          (
                              SELECT id_job
                                FROM jobs
                               WHERE id_stage = NEW.id_stage
                          ),
-                         1,
                          'Done'
                      );
END;


-- Trigger: insert_empty_stage
DROP TRIGGER IF EXISTS insert_empty_stage;
CREATE TRIGGER insert_empty_stage
         AFTER INSERT
            ON projects
BEGIN
    INSERT INTO stages (
                           id_project,
                           name,
                           optimization,
                           status
                       )
                       VALUES (
                           NEW.id_project,
                           'Single tester pass',
                           0,
                           'Done'
                       );
END;


-- Trigger: upd_job_status_done
DROP TRIGGER IF EXISTS upd_job_status_done;
CREATE TRIGGER upd_job_status_done
         AFTER UPDATE OF status
            ON jobs
          WHEN NEW.status = 'Done'
BEGIN
    UPDATE stages
       SET status = (
               SELECT CASE WHEN (
                                    SELECT COUNT( * ) 
                                      FROM jobs j
                                     WHERE (j.status = 'Queued' OR 
                                            j.status = 'Process') AND 
                                           j.id_stage = NEW.id_stage
                                )
=                         0 THEN 'Done' ELSE 'Process' END
           )
     WHERE id_stage = NEW.id_stage;
END;


-- Trigger: upd_job_status_process
DROP TRIGGER IF EXISTS upd_job_status_process;
CREATE TRIGGER upd_job_status_process
         AFTER UPDATE OF status
            ON jobs
          WHEN NEW.status = 'Process'
BEGIN
    UPDATE stages
       SET status = 'Process'
     WHERE id_stage = NEW.id_stage;
END;


-- Trigger: upd_job_status_queued
DROP TRIGGER IF EXISTS upd_job_status_queued;
CREATE TRIGGER upd_job_status_queued
         AFTER UPDATE OF status
            ON jobs
          WHEN NEW.status = 'Queued'
BEGIN
    UPDATE tasks
       SET status = 'Queued'
     WHERE id_job = NEW.id_job;
END;


-- Trigger: upd_pass_date
DROP TRIGGER IF EXISTS upd_pass_date;
CREATE TRIGGER upd_pass_date
         AFTER INSERT
            ON passes
BEGIN
    UPDATE passes
       SET pass_date = DATETIME('NOW') 
     WHERE id_pass = NEW.id_pass;
END;


-- Trigger: upd_project_status_done
DROP TRIGGER IF EXISTS upd_project_status_done;
CREATE TRIGGER upd_project_status_done
         AFTER UPDATE OF status
            ON projects
          WHEN NEW.status = 'Done'
BEGIN
    UPDATE tasks
       SET status = 'Done'
     WHERE id_task IN (
        SELECT t.id_task
          FROM tasks t
               JOIN
               jobs j ON j.id_job = t.id_job
               JOIN
               stages s ON s.id_stage = j.id_stage
               JOIN
               projects p ON p.id_project = s.id_project
         WHERE p.id_project = NEW.id_project AND 
               t.status <> 'Done'
    );
END;


-- Trigger: upd_project_status_queued
DROP TRIGGER IF EXISTS upd_project_status_queued;
CREATE TRIGGER upd_project_status_queued
         AFTER UPDATE OF status
            ON projects
          WHEN NEW.status = 'Queued'
BEGIN
    UPDATE stages
       SET status = 'Queued'
     WHERE id_project = NEW.id_project AND
           name <> 'Single tester pass';
END;


-- Trigger: upd_stage_status_done
DROP TRIGGER IF EXISTS upd_stage_status_done;
CREATE TRIGGER upd_stage_status_done
         AFTER UPDATE OF status
            ON stages
          WHEN NEW.status = 'Done'
BEGIN
    UPDATE projects
       SET status = (
               SELECT CASE WHEN (
                                    SELECT COUNT( * ) 
                                      FROM stages s
                                     WHERE (s.status = 'Queued' OR 
                                            s.status = 'Process') AND 
                                           s.name <> 'Single tester pass' AND 
                                           s.id_project = NEW.id_project
                                )
=                         0 THEN 'Done' ELSE 'Process' END
           )
     WHERE id_project = NEW.id_project;
END;


-- Trigger: upd_stage_status_process
DROP TRIGGER IF EXISTS upd_stage_status_process;
CREATE TRIGGER upd_stage_status_process
         AFTER UPDATE OF status
            ON stages
          WHEN NEW.status = 'Process'
BEGIN
    UPDATE projects
       SET status = 'Process'
     WHERE id_project = NEW.id_project;
END;


-- Trigger: upd_stage_status_queued
DROP TRIGGER IF EXISTS upd_stage_status_queued;
CREATE TRIGGER upd_stage_status_queued
         AFTER UPDATE
            ON stages
          WHEN NEW.status = 'Queued' AND 
               OLD.status <> NEW.status
BEGIN
    UPDATE jobs
       SET status = 'Queued'
     WHERE id_stage = NEW.id_stage;
END;


-- Trigger: upd_task_status_done
DROP TRIGGER IF EXISTS upd_task_status_done;
CREATE TRIGGER upd_task_status_done
         AFTER UPDATE OF status
            ON tasks
          WHEN NEW.status = 'Done'
BEGIN
    UPDATE tasks
       SET finish_date = DATETIME('NOW') 
     WHERE id_task = NEW.id_task;
    UPDATE jobs
       SET status = (
               SELECT CASE WHEN (
                                    SELECT COUNT( * ) 
                                      FROM tasks t
                                     WHERE (t.status = 'Queued' OR 
                                            t.status = 'Process') AND 
                                           t.id_job = NEW.id_job
                                )
=                         0 THEN 'Done' ELSE 'Process' END
           )
     WHERE id_job = NEW.id_job;
END;


-- Trigger: upd_task_status_process
DROP TRIGGER IF EXISTS upd_task_status_process;
CREATE TRIGGER upd_task_status_process
         AFTER UPDATE OF status
            ON tasks
          WHEN NEW.status = 'Process'
BEGIN
    UPDATE tasks
       SET start_date = DATETIME('NOW') 
     WHERE id_task = NEW.id_task;
    DELETE FROM passes
          WHERE id_task = NEW.id_task;
    UPDATE jobs
       SET status = 'Process'
     WHERE id_job = NEW.id_job;
END;


-- Trigger: upd_task_status_queued
DROP TRIGGER IF EXISTS upd_task_status_queued;
CREATE TRIGGER upd_task_status_queued
         AFTER UPDATE OF status
            ON tasks
          WHEN NEW.status = 'Queued'
BEGIN
    UPDATE tasks
       SET start_date = NULL,
           finish_date = NULL
     WHERE id_task = NEW.id_task;
END;


COMMIT TRANSACTION;
PRAGMA foreign_keys = on;
