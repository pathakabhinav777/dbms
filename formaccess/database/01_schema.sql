-- =====================================================================
--  FormAccess – Authorized Information Collection System
--  File   : database/01_schema.sql
--  Purpose: Creates the database, an application user, and all tables.
--  Target : MySQL 8.0.16 or newer (CHECK constraints are enforced from 8.0.16)
--  Run as : root (or any account allowed to create databases/users)
--
--      mysql -u root -p < database/01_schema.sql
--
--  TIMEZONE CONVENTION (documented once, used everywhere):
--      All DATETIME values are stored in IST (Asia/Kolkata, UTC+05:30).
--      DATETIME has no timezone inside it, so the application (Phase 3)
--      forces the JVM and the JDBC connection to Asia/Kolkata.
--
--  WARNING: this script DROPS existing FormAccess tables. Re-running it
--  gives you a clean, empty database.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Database
--    utf8mb4 stores every Unicode character (Hindi names, emoji).
--    utf8mb4_0900_ai_ci is case-INsensitive, so 'Arjun@X.com' and
--    'arjun@x.com' count as the same email for the UNIQUE constraint.
-- ---------------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS formaccess
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------------
-- 2. Application user (principle of least privilege)
--    Spring Boot will log in as this user, NOT as root. It can read and
--    write rows but cannot DROP tables or create users.
--    Change the password here and in application.properties (Phase 3).
-- ---------------------------------------------------------------------
CREATE USER IF NOT EXISTS 'formaccess_app'@'localhost' IDENTIFIED BY 'FormAccess@2026';
GRANT SELECT, INSERT, UPDATE, DELETE ON formaccess.* TO 'formaccess_app'@'localhost';
FLUSH PRIVILEGES;

USE formaccess;

-- Drop in reverse dependency order (children before parents).
SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS event_audit_logs;
DROP TABLE IF EXISTS public_summaries;
DROP TABLE IF EXISTS reminders;
DROP TABLE IF EXISTS answer_selections;
DROP TABLE IF EXISTS answers;
DROP TABLE IF EXISTS submissions;
DROP TABLE IF EXISTS eligibility_rules;
DROP TABLE IF EXISTS question_options;
DROP TABLE IF EXISTS questions;
DROP TABLE IF EXISTS events;
DROP TABLE IF EXISTS users;
DROP TABLE IF EXISTS departments;
SET FOREIGN_KEY_CHECKS = 1;

-- =====================================================================
-- TABLE: departments  (lookup table)
-- One row per department. users.dept_id points here, so a department
-- name is stored once (normalization) and the rule builder can show a
-- dropdown of valid departments instead of free text.
-- =====================================================================
CREATE TABLE departments (
    dept_id     INT           NOT NULL AUTO_INCREMENT,
    code        VARCHAR(10)   NOT NULL,             -- e.g. CSE
    name        VARCHAR(100)  NOT NULL,             -- e.g. Computer Science and Engineering
    CONSTRAINT pk_departments      PRIMARY KEY (dept_id),
    CONSTRAINT uq_departments_code UNIQUE (code),
    CONSTRAINT uq_departments_name UNIQUE (name)
) ENGINE = InnoDB;

-- =====================================================================
-- TABLE: users
-- Every person on the platform. Role decides which dashboard they get.
-- dept_id / year_of_study are NULL for admins and faculty creators.
-- Text "enums" are VARCHAR + CHECK instead of MySQL ENUM because it maps
-- cleanly to Java enums with JPA (@Enumerated(EnumType.STRING)).
-- =====================================================================
CREATE TABLE users (
    user_id         BIGINT        NOT NULL AUTO_INCREMENT,
    full_name       VARCHAR(100)  NOT NULL,
    email           VARCHAR(150)  NOT NULL,
    password_hash   VARCHAR(100)  NOT NULL,         -- BCrypt hash (60 chars), never plain text
    dept_id         INT           NULL,
    year_of_study   TINYINT       NULL,
    role            VARCHAR(20)   NOT NULL DEFAULT 'PARTICIPANT',
    account_status  VARCHAR(20)   NOT NULL DEFAULT 'ACTIVE',
    registered_at   DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT pk_users        PRIMARY KEY (user_id),
    CONSTRAINT uq_users_email  UNIQUE (email),
    CONSTRAINT fk_users_dept   FOREIGN KEY (dept_id) REFERENCES departments (dept_id),
    CONSTRAINT ck_users_role   CHECK (role IN ('ADMIN', 'CREATOR', 'PARTICIPANT')),
    CONSTRAINT ck_users_status CHECK (account_status IN ('ACTIVE', 'INACTIVE')),
    CONSTRAINT ck_users_year   CHECK (year_of_study IS NULL OR year_of_study BETWEEN 1 AND 5),
    CONSTRAINT ck_users_email  CHECK (email LIKE '%_@_%._%')
) ENGINE = InnoDB;

-- Speeds up "find users in department X, year Y" (eligibility counts, reports).
CREATE INDEX idx_users_dept_year ON users (dept_id, year_of_study);
CREATE INDEX idx_users_role_status ON users (role, account_status);

-- =====================================================================
-- TABLE: events  (one information-collection event = one form)
--
-- public_token : random UUID used in the shareable link /e/{token}.
--                We do NOT use event_id in links, so people cannot guess
--                other events by changing 1 to 2. (Having the link still
--                does not grant access – eligibility is checked in Java.)
-- deadline_mode: AUTOMATIC -> closes itself at deadline_at
--                MANUAL    -> deadline_at is the announced target date;
--                             the event closes only when the creator
--                             clicks "Close Submissions".
-- status       : DRAFT -> SCHEDULED -> OPEN -> CLOSED
-- =====================================================================
CREATE TABLE events (
    event_id                    BIGINT        NOT NULL AUTO_INCREMENT,
    public_token                CHAR(36)      NOT NULL,
    title                       VARCHAR(200)  NOT NULL,
    description                 TEXT          NULL,
    creator_id                  BIGINT        NOT NULL,
    created_at                  DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                  DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    start_at                    DATETIME      NOT NULL,
    deadline_at                 DATETIME      NOT NULL,
    published_at                DATETIME      NULL,
    closed_at                   DATETIME      NULL,
    status                      VARCHAR(20)   NOT NULL DEFAULT 'DRAFT',
    deadline_mode               VARCHAR(20)   NOT NULL DEFAULT 'AUTOMATIC',
    allow_multiple_submissions  BOOLEAN       NOT NULL DEFAULT FALSE,
    auto_reminder_enabled       BOOLEAN       NOT NULL DEFAULT FALSE,
    reminder_hours_before       INT           NULL,     -- e.g. 24 = remind 24 h before deadline

    CONSTRAINT pk_events          PRIMARY KEY (event_id),
    CONSTRAINT uq_events_token    UNIQUE (public_token),
    CONSTRAINT fk_events_creator  FOREIGN KEY (creator_id) REFERENCES users (user_id),
    CONSTRAINT ck_events_status   CHECK (status IN ('DRAFT', 'SCHEDULED', 'OPEN', 'CLOSED')),
    CONSTRAINT ck_events_mode     CHECK (deadline_mode IN ('AUTOMATIC', 'MANUAL')),
    CONSTRAINT ck_events_dates    CHECK (deadline_at > start_at),
    CONSTRAINT ck_events_closed   CHECK (status <> 'CLOSED' OR closed_at IS NOT NULL),
    CONSTRAINT ck_events_reminder CHECK (
        (auto_reminder_enabled = FALSE)
        OR (reminder_hours_before IS NOT NULL AND reminder_hours_before BETWEEN 1 AND 720)
    )
) ENGINE = InnoDB;

-- The scheduler runs "find OPEN events whose deadline has passed" every
-- minute; this composite index makes that query fast.
CREATE INDEX idx_events_status_deadline ON events (status, deadline_at);
CREATE INDEX idx_events_status_start    ON events (status, start_at);

-- =====================================================================
-- TABLE: questions
-- One row per question in a form. Validation rules are columns because
-- each question has at most one min/max of each kind (keeps it simple).
--
-- answer storage convention (used by the answers table):
--   SHORT_TEXT, LONG_TEXT, EMAIL       -> answers.answer_text
--   DATE  (ISO 'YYYY-MM-DD')           -> answers.answer_text
--   TIME  (ISO 'HH:MM')                -> answers.answer_text
--   YES_NO ('YES' / 'NO')              -> answers.answer_text
--   INTEGER, DECIMAL, RATING           -> answers.answer_number
--   DROPDOWN, RADIO, CHECKBOX          -> answer_selections rows
-- =====================================================================
CREATE TABLE questions (
    question_id     BIGINT         NOT NULL AUTO_INCREMENT,
    event_id        BIGINT         NOT NULL,
    question_text   VARCHAR(500)   NOT NULL,
    help_text       VARCHAR(500)   NULL,
    question_type   VARCHAR(20)    NOT NULL,
    is_required     BOOLEAN        NOT NULL DEFAULT FALSE,
    default_value   VARCHAR(500)   NULL,
    display_order   INT            NOT NULL,
    min_length      INT            NULL,
    max_length      INT            NULL,
    min_value       DECIMAL(15,4)  NULL,
    max_value       DECIMAL(15,4)  NULL,
    min_date        DATE           NULL,
    max_date        DATE           NULL,
    rating_max      TINYINT        NULL,             -- 5 or 10, only for RATING

    CONSTRAINT pk_questions       PRIMARY KEY (question_id),
    CONSTRAINT fk_questions_event FOREIGN KEY (event_id) REFERENCES events (event_id)
        ON DELETE CASCADE,                           -- deleting an event deletes its questions
    CONSTRAINT ck_questions_type  CHECK (question_type IN (
        'SHORT_TEXT', 'LONG_TEXT', 'INTEGER', 'DECIMAL', 'EMAIL', 'DATE', 'TIME',
        'DROPDOWN', 'CHECKBOX', 'RADIO', 'RATING', 'YES_NO')),
    CONSTRAINT ck_questions_order  CHECK (display_order >= 1),
    CONSTRAINT ck_questions_len    CHECK (
        (min_length IS NULL OR min_length >= 0)
        AND (max_length IS NULL OR max_length >= 1)
        AND (min_length IS NULL OR max_length IS NULL OR min_length <= max_length)),
    CONSTRAINT ck_questions_value  CHECK (min_value IS NULL OR max_value IS NULL OR min_value <= max_value),
    CONSTRAINT ck_questions_date   CHECK (min_date  IS NULL OR max_date  IS NULL OR min_date  <= max_date),
    CONSTRAINT ck_questions_rating CHECK (
        (question_type =  'RATING' AND rating_max IN (5, 10))
        OR (question_type <> 'RATING' AND rating_max IS NULL))
) ENGINE = InnoDB;

-- Not UNIQUE on purpose: when the creator drags question 3 above question 2,
-- Hibernate updates the rows one at a time, and for a moment two questions
-- would share an order number, which a UNIQUE index would reject.
-- The service layer keeps the order numbers 1..N.
CREATE INDEX idx_questions_event_order ON questions (event_id, display_order);

-- =====================================================================
-- TABLE: question_options
-- Choices for DROPDOWN, RADIO and CHECKBOX questions.
-- =====================================================================
CREATE TABLE question_options (
    option_id       BIGINT        NOT NULL AUTO_INCREMENT,
    question_id     BIGINT        NOT NULL,
    option_text     VARCHAR(200)  NOT NULL,
    display_order   INT           NOT NULL,

    CONSTRAINT pk_question_options PRIMARY KEY (option_id),
    CONSTRAINT fk_options_question FOREIGN KEY (question_id) REFERENCES questions (question_id)
        ON DELETE CASCADE,
    CONSTRAINT uq_options_text     UNIQUE (question_id, option_text),   -- no duplicate choices
    CONSTRAINT ck_options_order    CHECK (display_order >= 1)
) ENGINE = InnoDB;

-- =====================================================================
-- TABLE: eligibility_rules
-- Structured rules – creators never type SQL.
--
-- Evaluation (done in Java, Phase 7):
--   * conditions with the SAME group_no are joined by AND
--   * different groups are joined by OR
--   * an event with no rules = every ACTIVE user is eligible
--   * INACTIVE users are never eligible, whatever the rules say
--
-- Example: (Department = CSE AND Year >= 2) OR (Department = IT)
--   group 1: DEPARTMENT EQUALS CSE
--   group 1: YEAR GREATER_OR_EQUAL 2
--   group 2: DEPARTMENT EQUALS IT
--
-- For the IN operator, rule_value holds a comma-separated list ("CSE,IT").
-- That is a single parameter of one rule (like a string literal), not a
-- repeating group of facts, so it is acceptable here.
-- =====================================================================
CREATE TABLE eligibility_rules (
    rule_id      BIGINT        NOT NULL AUTO_INCREMENT,
    event_id     BIGINT        NOT NULL,
    group_no     INT           NOT NULL DEFAULT 1,
    attribute    VARCHAR(30)   NOT NULL,
    operator     VARCHAR(30)   NOT NULL,
    rule_value   VARCHAR(255)  NOT NULL,

    CONSTRAINT pk_eligibility_rules PRIMARY KEY (rule_id),
    CONSTRAINT fk_rules_event       FOREIGN KEY (event_id) REFERENCES events (event_id)
        ON DELETE CASCADE,
    CONSTRAINT ck_rules_group       CHECK (group_no >= 1),
    -- WHITELISTS: only these attributes/operators can ever be evaluated.
    CONSTRAINT ck_rules_attribute   CHECK (attribute IN ('DEPARTMENT', 'YEAR', 'ROLE', 'ACCOUNT_STATUS')),
    CONSTRAINT ck_rules_operator    CHECK (operator IN (
        'EQUALS', 'NOT_EQUALS', 'GREATER_THAN', 'GREATER_OR_EQUAL',
        'LESS_THAN', 'LESS_OR_EQUAL', 'CONTAINS', 'IN'))
) ENGINE = InnoDB;

CREATE INDEX idx_rules_event_group ON eligibility_rules (event_id, group_no);

-- =====================================================================
-- TABLE: submissions  (bridge between users and events: M:N)
--
-- DUPLICATE PREVENTION AT DATABASE LEVEL:
--   UNIQUE (event_id, user_id, attempt_no)
--   When multiple submissions are NOT allowed the service always uses
--   attempt_no = 1, so a second insert for the same user+event fails –
--   even if two requests arrive at the same millisecond.
--
-- ON DELETE RESTRICT on event_id: MySQL refuses to delete an event that
-- has submissions, which matches the rule "delete only if no submissions".
-- =====================================================================
CREATE TABLE submissions (
    submission_id  BIGINT       NOT NULL AUTO_INCREMENT,
    event_id       BIGINT       NOT NULL,
    user_id        BIGINT       NOT NULL,
    attempt_no     INT          NOT NULL DEFAULT 1,
    submitted_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status         VARCHAR(20)  NOT NULL DEFAULT 'SUBMITTED',

    CONSTRAINT pk_submissions          PRIMARY KEY (submission_id),
    CONSTRAINT fk_submissions_event    FOREIGN KEY (event_id) REFERENCES events (event_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_submissions_user     FOREIGN KEY (user_id)  REFERENCES users (user_id)
        ON DELETE RESTRICT,
    CONSTRAINT uq_submissions_attempt  UNIQUE (event_id, user_id, attempt_no),
    CONSTRAINT ck_submissions_attempt  CHECK (attempt_no >= 1),
    CONSTRAINT ck_submissions_status   CHECK (status IN ('SUBMITTED', 'WITHDRAWN'))
) ENGINE = InnoDB;

CREATE INDEX idx_submissions_user        ON submissions (user_id, submitted_at);   -- "my history"
CREATE INDEX idx_submissions_event_time  ON submissions (event_id, submitted_at);  -- timeline chart

-- =====================================================================
-- TABLE: answers
-- One row per (submission, question). A question can have many answers
-- (one from each submission). Choice answers keep their selected
-- options in answer_selections.
--
-- Note: the database cannot easily check that answers.question_id belongs
-- to the same event as the submission; SubmissionService checks this in Java.
-- =====================================================================
CREATE TABLE answers (
    answer_id      BIGINT         NOT NULL AUTO_INCREMENT,
    submission_id  BIGINT         NOT NULL,
    question_id    BIGINT         NOT NULL,
    answer_text    TEXT           NULL,
    answer_number  DECIMAL(15,4)  NULL,

    CONSTRAINT pk_answers            PRIMARY KEY (answer_id),
    CONSTRAINT fk_answers_submission FOREIGN KEY (submission_id) REFERENCES submissions (submission_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_answers_question   FOREIGN KEY (question_id) REFERENCES questions (question_id)
        ON DELETE RESTRICT,           -- cannot delete a question that already has answers
    CONSTRAINT uq_answers_once       UNIQUE (submission_id, question_id)
) ENGINE = InnoDB;

-- =====================================================================
-- TABLE: answer_selections  (bridge between answers and options: M:N)
-- A CHECKBOX answer "Java + SQL" becomes two rows here.
-- Storing "Java,SQL" in one column would break First Normal Form.
-- =====================================================================
CREATE TABLE answer_selections (
    answer_id   BIGINT  NOT NULL,
    option_id   BIGINT  NOT NULL,

    CONSTRAINT pk_answer_selections PRIMARY KEY (answer_id, option_id),
    CONSTRAINT fk_selections_answer FOREIGN KEY (answer_id) REFERENCES answers (answer_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_selections_option FOREIGN KEY (option_id) REFERENCES question_options (option_id)
        ON DELETE RESTRICT
) ENGINE = InnoDB;

CREATE INDEX idx_selections_option ON answer_selections (option_id);  -- "how many chose option X"

-- =====================================================================
-- TABLE: reminders  (history of every reminder sent)
-- Used to avoid spamming: before sending, ReminderService checks whether
-- this user already got a reminder for this event in the last N hours.
-- =====================================================================
CREATE TABLE reminders (
    reminder_id      BIGINT       NOT NULL AUTO_INCREMENT,
    event_id         BIGINT       NOT NULL,
    user_id          BIGINT       NOT NULL,              -- recipient
    sent_by          BIGINT       NULL,                  -- creator for MANUAL, NULL for AUTOMATIC
    reminder_type    VARCHAR(20)  NOT NULL,
    sent_at          DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    delivery_status  VARCHAR(20)  NOT NULL DEFAULT 'SENT',

    CONSTRAINT pk_reminders         PRIMARY KEY (reminder_id),
    CONSTRAINT fk_reminders_event   FOREIGN KEY (event_id) REFERENCES events (event_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_reminders_user    FOREIGN KEY (user_id)  REFERENCES users (user_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_reminders_sender  FOREIGN KEY (sent_by)  REFERENCES users (user_id)
        ON DELETE SET NULL,
    CONSTRAINT ck_reminders_type    CHECK (reminder_type IN ('MANUAL', 'AUTOMATIC')),
    CONSTRAINT ck_reminders_status  CHECK (delivery_status IN ('SENT', 'FAILED'))
) ENGINE = InnoDB;

CREATE INDEX idx_reminders_event_user_time ON reminders (event_id, user_id, sent_at);

-- =====================================================================
-- TABLE: public_summaries
-- Which statistics the creator has chosen to show, and when.
-- Event-level summaries (RESPONSE_COUNT, SUBMISSION_PERCENTAGE,
-- BY_DEPARTMENT) have question_id = NULL; the rest need a question.
-- That pairing is checked in Java because MySQL does not allow a CHECK
-- constraint on a column that also has ON DELETE CASCADE.
-- Only aggregated numbers are ever produced from this – never raw answers.
-- =====================================================================
CREATE TABLE public_summaries (
    summary_id    BIGINT       NOT NULL AUTO_INCREMENT,
    event_id      BIGINT       NOT NULL,
    question_id   BIGINT       NULL,
    summary_type  VARCHAR(30)  NOT NULL,
    visibility    VARCHAR(30)  NOT NULL DEFAULT 'PRIVATE',

    CONSTRAINT pk_public_summaries  PRIMARY KEY (summary_id),
    CONSTRAINT fk_summaries_event   FOREIGN KEY (event_id)    REFERENCES events (event_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_summaries_question FOREIGN KEY (question_id) REFERENCES questions (question_id)
        ON DELETE CASCADE,
    CONSTRAINT uq_summaries         UNIQUE (event_id, question_id, summary_type),
    CONSTRAINT ck_summaries_type    CHECK (summary_type IN (
        'RESPONSE_COUNT', 'SUBMISSION_PERCENTAGE', 'BY_DEPARTMENT',
        'AVERAGE', 'MINIMUM', 'MAXIMUM', 'OPTION_COUNT', 'OPTION_PERCENTAGE', 'YES_NO_COUNT')),
    CONSTRAINT ck_summaries_vis     CHECK (visibility IN ('PRIVATE', 'PUBLIC_ALWAYS', 'PUBLIC_AFTER_DEADLINE'))
) ENGINE = InnoDB;

-- =====================================================================
-- TABLE: event_audit_logs
-- Who did what to which event (created, published, closed, reminders…).
-- ON DELETE SET NULL keeps the log row even if the event is deleted,
-- so "Riya deleted event 7" is still on record.
-- =====================================================================
CREATE TABLE event_audit_logs (
    log_id      BIGINT         NOT NULL AUTO_INCREMENT,
    event_id    BIGINT         NULL,
    actor_id    BIGINT         NULL,          -- NULL = done by the system scheduler
    action      VARCHAR(30)    NOT NULL,
    details     VARCHAR(1000)  NULL,
    created_at  DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_event_audit_logs PRIMARY KEY (log_id),
    CONSTRAINT fk_audit_event FOREIGN KEY (event_id) REFERENCES events (event_id) ON DELETE SET NULL,
    CONSTRAINT fk_audit_actor FOREIGN KEY (actor_id) REFERENCES users (user_id)  ON DELETE SET NULL
) ENGINE = InnoDB;

CREATE INDEX idx_audit_event_time ON event_audit_logs (event_id, created_at);

-- Quick check: should list 12 tables.
SHOW TABLES;
