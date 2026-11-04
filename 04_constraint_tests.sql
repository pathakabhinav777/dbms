-- =====================================================================
--  FormAccess – constraint & transaction tests
--  File : database/04_constraint_tests.sql
--  Run  : mysql -u root -p -t --force formaccess < database/04_constraint_tests.sql
--
--  Almost every statement here is SUPPOSED TO FAIL. --force tells the
--  mysql client to print the error and carry on with the next statement.
--  A failure here is proof that the database protects itself even if the
--  Java code has a bug. Nothing in this file changes the sample data.
--
--  Error codes you will see:
--    1062  duplicate entry (UNIQUE / PRIMARY KEY)
--    3819  check constraint violated
--    1451  cannot delete parent row (foreign key)
--    1452  cannot add child row (foreign key)
-- =====================================================================
USE formaccess;

-- T1. Duplicate submission: Arjun submits event 1 a second time.
-- EXPECTED: ERROR 1062 Duplicate entry '1-4-1' for key 'submissions.uq_submissions_attempt'
INSERT INTO submissions (event_id, user_id, attempt_no) VALUES (1, 4, 1);

-- T2. Same question answered twice inside one submission.
-- EXPECTED: ERROR 1062 ... 'answers.uq_answers_once'
INSERT INTO answers (submission_id, question_id, answer_text) VALUES (1, 1, 'Another name');

-- T3. Same email in different letter case (case-insensitive collation).
-- EXPECTED: ERROR 1062 ... 'users.uq_users_email'
INSERT INTO users (full_name, email, password_hash, role)
VALUES ('Fake Arjun', 'ARJUN.MEHTA@college.edu', 'x', 'PARTICIPANT');

-- T4. A role that does not exist.
-- EXPECTED: ERROR 3819 Check constraint 'ck_users_role' is violated.
INSERT INTO users (full_name, email, password_hash, role)
VALUES ('Hacker', 'hacker@college.edu', 'x', 'SUPERADMIN');

-- T5. Deadline before start date.
-- EXPECTED: ERROR 3819 Check constraint 'ck_events_dates' is violated.
INSERT INTO events (public_token, title, creator_id, start_at, deadline_at)
VALUES (UUID(), 'Broken event', 2, NOW(), NOW() - INTERVAL 1 DAY);

-- T6. Rating question without a scale.
-- EXPECTED: ERROR 3819 Check constraint 'ck_questions_rating' is violated.
INSERT INTO questions (event_id, question_text, question_type, display_order)
VALUES (3, 'Rate us', 'RATING', 3);

-- T7. Eligibility rule on an attribute that is not on the whitelist.
-- EXPECTED: ERROR 3819 Check constraint 'ck_rules_attribute' is violated.
INSERT INTO eligibility_rules (event_id, group_no, attribute, operator, rule_value)
VALUES (1, 1, 'PASSWORD_HASH', 'CONTAINS', 'a');

-- T8. Delete an event that already has submissions.
-- EXPECTED: ERROR 1451 Cannot delete or update a parent row ... fk_submissions_event
DELETE FROM events WHERE event_id = 1;

-- T9. Answer pointing to a question that does not exist.
-- EXPECTED: ERROR 1452 Cannot add or update a child row ... fk_answers_question
INSERT INTO answers (submission_id, question_id, answer_text) VALUES (1, 9999, 'x');

-- ---------------------------------------------------------------------
-- T10. Deleting a DRAFT event with no submissions works, and CASCADE
-- removes its questions and options too. We ROLLBACK so the data stays.
-- EXPECTED: first SELECT -> 2 questions; after DELETE -> 0; after ROLLBACK -> 2
-- ---------------------------------------------------------------------
SELECT COUNT(*) AS q_before FROM questions WHERE event_id = 3;
START TRANSACTION;
DELETE FROM events WHERE event_id = 3;
SELECT COUNT(*) AS q_after_delete FROM questions WHERE event_id = 3;
ROLLBACK;
SELECT COUNT(*) AS q_after_rollback FROM questions WHERE event_id = 3;

-- ---------------------------------------------------------------------
-- T11. TRANSACTION = all or nothing.
-- Sneha starts a submission, but one answer is invalid. In Java,
-- @Transactional does exactly this: on any error it rolls back, so we
-- never end up with a submission that has half its answers.
-- EXPECTED: one ERROR 1452 in the middle; the final count is still 3.
-- ---------------------------------------------------------------------
START TRANSACTION;
INSERT INTO submissions (event_id, user_id, attempt_no) VALUES (1, 5, 1);
SET @sub = LAST_INSERT_ID();                       -- id of the row just inserted
INSERT INTO answers (submission_id, question_id, answer_text) VALUES (@sub, 1, 'Team Sneha');
INSERT INTO answers (submission_id, question_id, answer_text) VALUES (@sub, 9999, 'bad');  -- fails
ROLLBACK;                                          -- undo everything since START TRANSACTION
SELECT COUNT(*) AS event1_submissions FROM submissions WHERE event_id = 1;   -- 3
