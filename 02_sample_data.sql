-- =====================================================================
--  FormAccess – sample data
--  File   : database/02_sample_data.sql
--  Run    : mysql -u root -p formaccess < database/02_sample_data.sql
--           (run 01_schema.sql first)
--
--  Every account's password is:  Password@123
--  The hash below is a real BCrypt hash (cost 10) of that password, so
--  these accounts will log in once Spring Security is added in Phase 4.
--
--  Dates are relative to NOW(), so the data stays meaningful whenever you
--  run it: event 1 is always open, event 2 always closed, etc.
--  Explicit IDs are used so the test queries can refer to them.
-- =====================================================================
USE formaccess;

SET @pwd = '$2a$10$cC15arMMUk/e.VjQWYAGcuMDu1rHAXuhSa7JC/cqJprYMpNGcT4.O';

START TRANSACTION;

-- ---------------------------------------------------------------------
-- Departments
-- ---------------------------------------------------------------------
INSERT INTO departments (dept_id, code, name) VALUES
    (1, 'CSE',   'Computer Science and Engineering'),
    (2, 'IT',    'Information Technology'),
    (3, 'ECE',   'Electronics and Communication Engineering'),
    (4, 'MECH',  'Mechanical Engineering'),
    (5, 'CIVIL', 'Civil Engineering');

-- ---------------------------------------------------------------------
-- Users
--   1      admin
--   2, 3   creators (faculty – no year of study)
--   4–13   participants; 12 is INACTIVE on purpose
-- ---------------------------------------------------------------------
INSERT INTO users (user_id, full_name, email, password_hash, dept_id, year_of_study, role, account_status, registered_at) VALUES
    ( 1, 'System Admin',  'admin@formaccess.edu',   @pwd, NULL, NULL, 'ADMIN',       'ACTIVE',   NOW() - INTERVAL 60 DAY),
    ( 2, 'Riya Sharma',   'riya.sharma@college.edu', @pwd, 1,   NULL, 'CREATOR',     'ACTIVE',   NOW() - INTERVAL 50 DAY),
    ( 3, 'Anil Kumar',    'anil.kumar@college.edu',  @pwd, 2,   NULL, 'CREATOR',     'ACTIVE',   NOW() - INTERVAL 50 DAY),
    ( 4, 'Arjun Mehta',   'arjun.mehta@college.edu', @pwd, 1,   2,    'PARTICIPANT', 'ACTIVE',   NOW() - INTERVAL 40 DAY),
    ( 5, 'Sneha Iyer',    'sneha.iyer@college.edu',  @pwd, 1,   2,    'PARTICIPANT', 'ACTIVE',   NOW() - INTERVAL 40 DAY),
    ( 6, 'Priya Nair',    'priya.nair@college.edu',  @pwd, 1,   3,    'PARTICIPANT', 'ACTIVE',   NOW() - INTERVAL 39 DAY),
    ( 7, 'Vikram Singh',  'vikram.singh@college.edu',@pwd, 1,   1,    'PARTICIPANT', 'ACTIVE',   NOW() - INTERVAL 38 DAY),
    ( 8, 'Karan Patel',   'karan.patel@college.edu', @pwd, 2,   1,    'PARTICIPANT', 'ACTIVE',   NOW() - INTERVAL 37 DAY),
    ( 9, 'Rahul Verma',   'rahul.verma@college.edu', @pwd, 2,   3,    'PARTICIPANT', 'ACTIVE',   NOW() - INTERVAL 36 DAY),
    (10, 'Meera Joshi',   'meera.joshi@college.edu', @pwd, 4,   3,    'PARTICIPANT', 'ACTIVE',   NOW() - INTERVAL 35 DAY),
    (11, 'Aisha Khan',    'aisha.khan@college.edu',  @pwd, 3,   2,    'PARTICIPANT', 'ACTIVE',   NOW() - INTERVAL 34 DAY),
    (12, 'Dev Malhotra',  'dev.malhotra@college.edu',@pwd, 1,   2,    'PARTICIPANT', 'INACTIVE', NOW() - INTERVAL 33 DAY),
    (13, 'Rohan Das',     'rohan.das@college.edu',   @pwd, 5,   4,    'PARTICIPANT', 'ACTIVE',   NOW() - INTERVAL 32 DAY);

-- ---------------------------------------------------------------------
-- Events
--   1  Hackathon Registration  – OPEN,      AUTOMATIC deadline in 20 days
--   2  DBMS Course Feedback    – CLOSED,    deadline 2 days ago
--   3  Sports Day Volunteers   – DRAFT
--   4  Placement Survey        – SCHEDULED, starts in 3 days, MANUAL mode
-- ---------------------------------------------------------------------
INSERT INTO events (event_id, public_token, title, description, creator_id, created_at,
                    start_at, deadline_at, published_at, closed_at, status, deadline_mode,
                    allow_multiple_submissions, auto_reminder_enabled, reminder_hours_before) VALUES
    (1, '3f2b8c1e-6a4d-4e2f-9b1a-7c5d8e9f0a11', 'Hackathon Registration 2026',
        'Register your team for the 24-hour inter-department hackathon.',
        2, NOW() - INTERVAL 6 DAY,
        NOW() - INTERVAL 5 DAY, NOW() + INTERVAL 20 DAY, NOW() - INTERVAL 5 DAY, NULL,
        'OPEN', 'AUTOMATIC', FALSE, TRUE, 48),
    (2, '9a7e4d2c-1b3f-4c5a-8d6e-2f1a0b9c8d22', 'DBMS Course Feedback',
        'Anonymous-style feedback on the Database Management Systems course.',
        2, NOW() - INTERVAL 16 DAY,
        NOW() - INTERVAL 15 DAY, NOW() - INTERVAL 2 DAY, NOW() - INTERVAL 15 DAY, NOW() - INTERVAL 2 DAY,
        'CLOSED', 'AUTOMATIC', FALSE, FALSE, NULL),
    (3, '5c1d9e8f-7a6b-4d3c-a2e1-0f9e8d7c6b33', 'Sports Day Volunteers',
        'Sign up to volunteer at the annual sports day.',
        3, NOW() - INTERVAL 1 DAY,
        NOW() + INTERVAL 7 DAY, NOW() + INTERVAL 14 DAY, NULL, NULL,
        'DRAFT', 'AUTOMATIC', FALSE, FALSE, NULL),
    (4, 'b8e2f1a0-3c4d-4e5f-9a8b-1c2d3e4f5a44', 'Placement Readiness Survey',
        'Help the placement cell schedule mock interviews.',
        3, NOW() - INTERVAL 1 DAY,
        NOW() + INTERVAL 3 DAY, NOW() + INTERVAL 10 DAY, NOW() - INTERVAL 1 DAY, NULL,
        'SCHEDULED', 'MANUAL', FALSE, FALSE, NULL);

-- ---------------------------------------------------------------------
-- Questions (between them the four events use all 12 question types)
-- ---------------------------------------------------------------------
INSERT INTO questions (question_id, event_id, question_text, question_type, is_required, default_value,
                       display_order, min_length, max_length, min_value, max_value, min_date, max_date, rating_max) VALUES
    -- Event 1: Hackathon
    ( 1, 1, 'Team name',                          'SHORT_TEXT', TRUE,  NULL, 1, 3,    50,   NULL, NULL, NULL, NULL, NULL),
    ( 2, 1, 'Team size',                          'INTEGER',    TRUE,  '2',  2, NULL, NULL, 1,    4,    NULL, NULL, NULL),
    ( 3, 1, 'Contact email',                      'EMAIL',      TRUE,  NULL, 3, NULL, 150,  NULL, NULL, NULL, NULL, NULL),
    ( 4, 1, 'Preferred track',                    'DROPDOWN',   TRUE,  NULL, 4, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
    ( 5, 1, 'Skills in your team',                'CHECKBOX',   FALSE, NULL, 5, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
    ( 6, 1, 'How excited are you?',               'RATING',     TRUE,  NULL, 6, NULL, NULL, NULL, NULL, NULL, NULL, 5),
    ( 7, 1, 'Do you need hostel accommodation?',  'YES_NO',     TRUE,  'NO', 7, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
    -- Event 2: DBMS feedback
    ( 8, 2, 'Rate the quality of teaching',       'RATING',     TRUE,  NULL, 1, NULL, NULL, NULL, NULL, NULL, NULL, 5),
    ( 9, 2, 'How was the pace of the course?',    'RADIO',      TRUE,  NULL, 2, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
    (10, 2, 'Which topics did you enjoy?',        'CHECKBOX',   FALSE, NULL, 3, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
    (11, 2, 'Would you recommend this course?',   'YES_NO',     TRUE,  NULL, 4, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
    (12, 2, 'Any other comments?',                'LONG_TEXT',  FALSE, NULL, 5, NULL, 1000, NULL, NULL, NULL, NULL, NULL),
    -- Event 3: Sports day (draft)
    (13, 3, 'Which desk do you want to help at?', 'DROPDOWN',   TRUE,  NULL, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
    (14, 3, 'Phone number',                       'SHORT_TEXT', TRUE,  NULL, 2, 10,   10,   NULL, NULL, NULL, NULL, NULL),
    -- Event 4: Placement survey
    (15, 4, 'Current CGPA',                       'DECIMAL',    TRUE,  NULL, 1, NULL, NULL, 0,    10,   NULL, NULL, NULL),
    (16, 4, 'Preferred mock-interview date',      'DATE',       TRUE,  NULL, 2, NULL, NULL, NULL, NULL,
                                                  DATE(NOW() + INTERVAL 3 DAY), DATE(NOW() + INTERVAL 10 DAY), NULL),
    (17, 4, 'Preferred time slot',                'TIME',       TRUE,  NULL, 3, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
    (18, 4, 'Personal email for the invite',      'EMAIL',      TRUE,  NULL, 4, NULL, 150,  NULL, NULL, NULL, NULL, NULL);

-- ---------------------------------------------------------------------
-- Options for DROPDOWN / RADIO / CHECKBOX questions
-- ---------------------------------------------------------------------
INSERT INTO question_options (option_id, question_id, option_text, display_order) VALUES
    ( 1, 4,  'AI / ML',           1),
    ( 2, 4,  'Web Development',   2),
    ( 3, 4,  'Cybersecurity',     3),
    ( 4, 4,  'IoT',               4),
    ( 5, 5,  'Java',              1),
    ( 6, 5,  'Python',            2),
    ( 7, 5,  'SQL',               3),
    ( 8, 5,  'JavaScript',        4),
    ( 9, 9,  'Too slow',          1),
    (10, 9,  'Just right',        2),
    (11, 9,  'Too fast',          3),
    (12, 10, 'ER Diagrams',       1),
    (13, 10, 'Normalization',     2),
    (14, 10, 'SQL Joins',         3),
    (15, 10, 'Transactions',      4),
    (16, 13, 'Registration desk', 1),
    (17, 13, 'Track and field',   2),
    (18, 13, 'First aid',         3);

-- ---------------------------------------------------------------------
-- Eligibility rules
-- Event 1: (DEPARTMENT = CSE AND YEAR >= 2 AND ROLE = PARTICIPANT)
--       OR (DEPARTMENT = IT  AND ROLE = PARTICIPANT)
--   -> eligible: Arjun(4), Sneha(5), Priya(6), Karan(8), Rahul(9)  = 5
--   -> NOT eligible: Vikram (CSE, year 1), Meera (MECH), Aisha (ECE),
--      Rohan (CIVIL), Dev (INACTIVE), Anil (IT but a CREATOR)
--
-- Event 2: DEPARTMENT IN (CSE, IT) AND ROLE = PARTICIPANT
--   -> eligible: 4, 5, 6, 7, 8, 9 = 6
--
-- Event 3: no rules -> every ACTIVE user
--
-- Event 4: YEAR >= 3
--   -> eligible: Priya(6), Rahul(9), Meera(10), Rohan(13) = 4
-- ---------------------------------------------------------------------
INSERT INTO eligibility_rules (rule_id, event_id, group_no, attribute, operator, rule_value) VALUES
    (1, 1, 1, 'DEPARTMENT', 'EQUALS',           'CSE'),
    (2, 1, 1, 'YEAR',       'GREATER_OR_EQUAL', '2'),
    (3, 1, 1, 'ROLE',       'EQUALS',           'PARTICIPANT'),
    (4, 1, 2, 'DEPARTMENT', 'EQUALS',           'IT'),
    (5, 1, 2, 'ROLE',       'EQUALS',           'PARTICIPANT'),
    (6, 2, 1, 'DEPARTMENT', 'IN',               'CSE,IT'),
    (7, 2, 1, 'ROLE',       'EQUALS',           'PARTICIPANT'),
    (8, 4, 1, 'YEAR',       'GREATER_OR_EQUAL', '3');

-- ---------------------------------------------------------------------
-- Submissions
--   Event 1: Arjun, Priya, Karan submitted -> Sneha, Rahul pending (3/5)
--   Event 2: everyone except Vikram submitted (5/6)
-- ---------------------------------------------------------------------
INSERT INTO submissions (submission_id, event_id, user_id, attempt_no, submitted_at, status) VALUES
    (1, 1, 4, 1, NOW() - INTERVAL 3 DAY,  'SUBMITTED'),
    (2, 1, 6, 1, NOW() - INTERVAL 2 DAY,  'SUBMITTED'),
    (3, 1, 8, 1, NOW() - INTERVAL 1 DAY,  'SUBMITTED'),
    (4, 2, 4, 1, NOW() - INTERVAL 14 DAY, 'SUBMITTED'),
    (5, 2, 5, 1, NOW() - INTERVAL 12 DAY, 'SUBMITTED'),
    (6, 2, 6, 1, NOW() - INTERVAL 12 DAY, 'SUBMITTED'),
    (7, 2, 8, 1, NOW() - INTERVAL 8 DAY,  'SUBMITTED'),
    (8, 2, 9, 1, NOW() - INTERVAL 3 DAY,  'SUBMITTED');

-- ---------------------------------------------------------------------
-- Answers  (text / number columns; choice answers get selections below)
-- ---------------------------------------------------------------------
INSERT INTO answers (answer_id, submission_id, question_id, answer_text, answer_number) VALUES
    -- Submission 1 (Arjun, hackathon)
    ( 1, 1, 1, 'Code Crusaders',          NULL),
    ( 2, 1, 2, NULL,                      3),
    ( 3, 1, 3, 'arjun.mehta@college.edu', NULL),
    ( 4, 1, 4, NULL,                      NULL),
    ( 5, 1, 5, NULL,                      NULL),
    ( 6, 1, 6, NULL,                      5),
    ( 7, 1, 7, 'NO',                      NULL),
    -- Submission 2 (Priya, hackathon)
    ( 8, 2, 1, 'Null Pointers',           NULL),
    ( 9, 2, 2, NULL,                      4),
    (10, 2, 3, 'priya.nair@college.edu',  NULL),
    (11, 2, 4, NULL,                      NULL),
    (12, 2, 5, NULL,                      NULL),
    (13, 2, 6, NULL,                      4),
    (14, 2, 7, 'YES',                     NULL),
    -- Submission 3 (Karan, hackathon) – skipped the optional skills question
    (15, 3, 1, 'Byte Me',                 NULL),
    (16, 3, 2, NULL,                      2),
    (17, 3, 3, 'karan.patel@college.edu', NULL),
    (18, 3, 4, NULL,                      NULL),
    (19, 3, 6, NULL,                      3),
    (20, 3, 7, 'YES',                     NULL),
    -- Submission 4 (Arjun, feedback)
    (21, 4, 8,  NULL, 5),
    (22, 4, 9,  NULL, NULL),
    (23, 4, 10, NULL, NULL),
    (24, 4, 11, 'YES', NULL),
    (25, 4, 12, 'Loved the normalization examples.', NULL),
    -- Submission 5 (Sneha, feedback)
    (26, 5, 8,  NULL, 4),
    (27, 5, 9,  NULL, NULL),
    (28, 5, 10, NULL, NULL),
    (29, 5, 11, 'YES', NULL),
    -- Submission 6 (Priya, feedback)
    (30, 6, 8,  NULL, 4),
    (31, 6, 9,  NULL, NULL),
    (32, 6, 10, NULL, NULL),
    (33, 6, 11, 'YES', NULL),
    (34, 6, 12, 'More practice on transactions please.', NULL),
    -- Submission 7 (Karan, feedback) – skipped topics and comments
    (35, 7, 8,  NULL, 3),
    (36, 7, 9,  NULL, NULL),
    (37, 7, 11, 'NO',  NULL),
    -- Submission 8 (Rahul, feedback) – skipped comments
    (38, 8, 8,  NULL, 5),
    (39, 8, 9,  NULL, NULL),
    (40, 8, 10, NULL, NULL),
    (41, 8, 11, 'YES', NULL);

-- ---------------------------------------------------------------------
-- Selected options for choice answers
-- ---------------------------------------------------------------------
INSERT INTO answer_selections (answer_id, option_id) VALUES
    ( 4, 1),            -- Arjun: AI / ML
    ( 5, 5), ( 5, 7),   -- Arjun: Java, SQL
    (11, 2),            -- Priya: Web Development
    (12, 5), (12, 7), (12, 8),   -- Priya: Java, SQL, JavaScript
    (18, 1),            -- Karan: AI / ML
    (22, 10),           -- Arjun: Just right
    (23, 13), (23, 14), -- Arjun: Normalization, SQL Joins
    (27, 11),           -- Sneha: Too fast
    (28, 12),           -- Sneha: ER Diagrams
    (31, 10),           -- Priya: Just right
    (32, 14), (32, 15), -- Priya: SQL Joins, Transactions
    (36, 11),           -- Karan: Too fast
    (39, 10),           -- Rahul: Just right
    (40, 13);           -- Rahul: Normalization

-- ---------------------------------------------------------------------
-- Reminder history: Riya manually reminded the two pending users yesterday
-- ---------------------------------------------------------------------
INSERT INTO reminders (reminder_id, event_id, user_id, sent_by, reminder_type, sent_at, delivery_status) VALUES
    (1, 1, 5, 2, 'MANUAL', NOW() - INTERVAL 1 DAY, 'SENT'),
    (2, 1, 9, 2, 'MANUAL', NOW() - INTERVAL 1 DAY, 'SENT');

-- ---------------------------------------------------------------------
-- Public summary settings for the closed feedback event
-- ---------------------------------------------------------------------
INSERT INTO public_summaries (summary_id, event_id, question_id, summary_type, visibility) VALUES
    (1, 2, NULL, 'RESPONSE_COUNT',        'PUBLIC_ALWAYS'),
    (2, 2, 8,    'AVERAGE',               'PUBLIC_AFTER_DEADLINE'),
    (3, 2, 11,   'YES_NO_COUNT',          'PUBLIC_AFTER_DEADLINE'),
    (4, 2, 9,    'OPTION_COUNT',          'PRIVATE'),
    (5, 2, NULL, 'BY_DEPARTMENT',         'PRIVATE'),
    (6, 1, NULL, 'RESPONSE_COUNT',        'PUBLIC_ALWAYS'),
    (7, 1, 6,    'AVERAGE',               'PUBLIC_AFTER_DEADLINE');

-- ---------------------------------------------------------------------
-- Audit log
-- ---------------------------------------------------------------------
INSERT INTO event_audit_logs (event_id, actor_id, action, details, created_at) VALUES
    (1, 2,    'CREATED',        'Event created',                         NOW() - INTERVAL 6 DAY),
    (1, 2,    'PUBLISHED',      'Event published, status OPEN',          NOW() - INTERVAL 5 DAY),
    (1, 2,    'REMINDER_SENT',  'Manual reminder sent to 2 users',       NOW() - INTERVAL 1 DAY),
    (2, 2,    'CREATED',        'Event created',                         NOW() - INTERVAL 16 DAY),
    (2, 2,    'PUBLISHED',      'Event published, status OPEN',          NOW() - INTERVAL 15 DAY),
    (2, NULL, 'AUTO_CLOSED',    'Deadline reached, closed by scheduler', NOW() - INTERVAL 2 DAY),
    (3, 3,    'CREATED',        'Event created',                         NOW() - INTERVAL 1 DAY),
    (4, 3,    'CREATED',        'Event created',                         NOW() - INTERVAL 1 DAY),
    (4, 3,    'PUBLISHED',      'Published, starts in 3 days (SCHEDULED)', NOW() - INTERVAL 1 DAY);

COMMIT;

-- Row counts – compare with the expected numbers on the right.
SELECT 'departments'       AS table_name, COUNT(*) AS row_count FROM departments        -- 5
UNION ALL SELECT 'users',             COUNT(*) FROM users              -- 13
UNION ALL SELECT 'events',            COUNT(*) FROM events             -- 4
UNION ALL SELECT 'questions',         COUNT(*) FROM questions          -- 18
UNION ALL SELECT 'question_options',  COUNT(*) FROM question_options   -- 18
UNION ALL SELECT 'eligibility_rules', COUNT(*) FROM eligibility_rules  -- 8
UNION ALL SELECT 'submissions',       COUNT(*) FROM submissions        -- 8
UNION ALL SELECT 'answers',           COUNT(*) FROM answers            -- 41
UNION ALL SELECT 'answer_selections', COUNT(*) FROM answer_selections  -- 19
UNION ALL SELECT 'reminders',         COUNT(*) FROM reminders          -- 2
UNION ALL SELECT 'public_summaries',  COUNT(*) FROM public_summaries   -- 7
UNION ALL SELECT 'event_audit_logs',  COUNT(*) FROM event_audit_logs;  -- 9
