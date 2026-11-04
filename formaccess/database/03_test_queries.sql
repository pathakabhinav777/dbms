-- =====================================================================
--  FormAccess – important queries (Phase 2 testing)
--  File : database/03_test_queries.sql
--  Run  : mysql -u root -p -t formaccess < database/03_test_queries.sql
--         (-t prints results as tables)
--
--  These are the queries the Java application will need later.
--  Each one lists the result you should see with the sample data.
--  Hibernate will generate the simple ones for us; the reporting ones
--  (statistics) we will write ourselves with @Query in Phase 11.
-- =====================================================================
USE formaccess;

-- ---------------------------------------------------------------------
-- Q1. Who is eligible for event 1?
-- Rules: (CSE AND year >= 2 AND PARTICIPANT) OR (IT AND PARTICIPANT)
-- In the app, EligibilityService evaluates the rule rows in Java.
-- This hand-written SQL lets you verify the Java answer.
-- LEFT JOIN: keeps users without a department (admin) in the scan.
-- EXPECTED: 4 Arjun, 5 Sneha, 6 Priya, 8 Karan, 9 Rahul   (5 rows)
-- ---------------------------------------------------------------------
SELECT u.user_id, u.full_name, d.code AS dept, u.year_of_study, u.role
FROM users u
LEFT JOIN departments d ON d.dept_id = u.dept_id
WHERE u.account_status = 'ACTIVE'
  AND (
        (d.code = 'CSE' AND u.year_of_study >= 2 AND u.role = 'PARTICIPANT')
     OR (d.code = 'IT'  AND u.role = 'PARTICIPANT')
  )
ORDER BY u.user_id;

-- ---------------------------------------------------------------------
-- Q2. Show the rules of event 1 in a readable form.
-- GROUP_CONCAT joins the conditions of one group with ' AND '.
-- EXPECTED:
--   1 | DEPARTMENT EQUALS CSE AND YEAR GREATER_OR_EQUAL 2 AND ROLE EQUALS PARTICIPANT
--   2 | DEPARTMENT EQUALS IT AND ROLE EQUALS PARTICIPANT
-- (Read the two rows as: group 1 OR group 2)
-- ---------------------------------------------------------------------
SELECT group_no,
       GROUP_CONCAT(CONCAT(attribute, ' ', operator, ' ', rule_value)
                    ORDER BY rule_id SEPARATOR ' AND ') AS conditions
FROM eligibility_rules
WHERE event_id = 1
GROUP BY group_no
ORDER BY group_no;

-- ---------------------------------------------------------------------
-- Q3. Pending users for event 1 (eligible but not submitted).
-- NOT EXISTS: "keep this user only if no submission row exists for them".
-- This is the list the reminder system emails.
-- EXPECTED: 5 Sneha Iyer, 9 Rahul Verma
-- ---------------------------------------------------------------------
SELECT u.user_id, u.full_name, u.email
FROM users u
LEFT JOIN departments d ON d.dept_id = u.dept_id
WHERE u.account_status = 'ACTIVE'
  AND (
        (d.code = 'CSE' AND u.year_of_study >= 2 AND u.role = 'PARTICIPANT')
     OR (d.code = 'IT'  AND u.role = 'PARTICIPANT')
  )
  AND NOT EXISTS (
        SELECT 1 FROM submissions s
        WHERE s.event_id = 1
          AND s.user_id  = u.user_id
          AND s.status   = 'SUBMITTED'
  )
ORDER BY u.user_id;

-- ---------------------------------------------------------------------
-- Q4. Creator dashboard: Riya's events with submission counts.
-- LEFT JOIN so events with 0 submissions still appear (with count 0).
-- COUNT(s.submission_id) counts only matched rows (NULLs are skipped).
-- EXPECTED: event 1 -> 3, event 2 -> 5
-- (eligible count comes from the Java rule engine, pending = eligible - submitted)
-- ---------------------------------------------------------------------
SELECT e.event_id, e.title, e.status, e.deadline_at,
       COUNT(s.submission_id) AS submitted
FROM events e
LEFT JOIN submissions s
       ON s.event_id = e.event_id AND s.status = 'SUBMITTED'
WHERE e.creator_id = 2
GROUP BY e.event_id, e.title, e.status, e.deadline_at
ORDER BY e.event_id;

-- ---------------------------------------------------------------------
-- Q5. Duplicate check before a submission (run by SubmissionService).
-- EXPECTED: 1  (Arjun already submitted event 1 -> app shows "already submitted")
-- ---------------------------------------------------------------------
SELECT COUNT(*) AS existing_submissions
FROM submissions
WHERE event_id = 1 AND user_id = 4 AND status = 'SUBMITTED';

-- ---------------------------------------------------------------------
-- Q6. Participant submission history (Arjun).
-- EXPECTED: 2 rows – Hackathon Registration 2026, DBMS Course Feedback
-- ---------------------------------------------------------------------
SELECT e.title, e.status AS event_status, s.submitted_at, s.status AS submission_status
FROM submissions s
JOIN events e ON e.event_id = s.event_id
WHERE s.user_id = 4
ORDER BY s.submitted_at DESC;

-- ---------------------------------------------------------------------
-- Q7. Load a form for rendering: questions in order with their options.
-- This is exactly what the dynamic form page needs (Phase 6).
-- EXPECTED: 7 rows; row 4 options "AI / ML | Web Development | Cybersecurity | IoT"
-- ---------------------------------------------------------------------
SELECT q.display_order, q.question_text, q.question_type, q.is_required,
       GROUP_CONCAT(o.option_text ORDER BY o.display_order SEPARATOR ' | ') AS options
FROM questions q
LEFT JOIN question_options o ON o.question_id = q.question_id
WHERE q.event_id = 1
GROUP BY q.question_id, q.display_order, q.question_text, q.question_type, q.is_required
ORDER BY q.display_order;

-- ---------------------------------------------------------------------
-- Q8. Rating statistics for question 8 (teaching quality).
-- EXPECTED: responses 5, average 4.20, min 3, max 5
-- ---------------------------------------------------------------------
SELECT COUNT(answer_number)          AS responses,
       ROUND(AVG(answer_number), 2)  AS average_rating,
       MIN(answer_number)            AS min_rating,
       MAX(answer_number)            AS max_rating
FROM answers
WHERE question_id = 8;

-- ---------------------------------------------------------------------
-- Q9. Option counts and percentage for a single-choice question (q9, pace).
-- Starts FROM question_options so options with 0 votes still show.
-- SUM(...) OVER () is a window function: the total of all groups,
-- computed without collapsing the rows – perfect for percentages.
-- EXPECTED:  Too slow 0 0.0 | Just right 3 60.0 | Too fast 2 40.0
-- (For CHECKBOX questions divide by the number of respondents instead,
--  because one person can pick several options.)
-- ---------------------------------------------------------------------
SELECT o.option_text,
       COUNT(sel.answer_id) AS votes,
       ROUND(100 * COUNT(sel.answer_id) / SUM(COUNT(sel.answer_id)) OVER (), 1) AS percentage
FROM question_options o
LEFT JOIN answer_selections sel ON sel.option_id = o.option_id
WHERE o.question_id = 9
GROUP BY o.option_id, o.option_text, o.display_order
ORDER BY o.display_order;

-- ---------------------------------------------------------------------
-- Q10. YES / NO totals for question 11 (would recommend).
-- In MySQL a comparison returns 1 or 0, so SUM(condition) counts matches.
-- EXPECTED: yes 4, no 1
-- ---------------------------------------------------------------------
SELECT SUM(answer_text = 'YES') AS yes_count,
       SUM(answer_text = 'NO')  AS no_count
FROM answers
WHERE question_id = 11;

-- ---------------------------------------------------------------------
-- Q11. Responses by department for event 2.
-- EXPECTED: CSE 3, IT 2
-- ---------------------------------------------------------------------
SELECT d.code AS department, COUNT(*) AS responses
FROM submissions s
JOIN users u       ON u.user_id = s.user_id
JOIN departments d ON d.dept_id = u.dept_id
WHERE s.event_id = 2 AND s.status = 'SUBMITTED'
GROUP BY d.code
ORDER BY responses DESC;

-- ---------------------------------------------------------------------
-- Q12. Submission timeline for event 2 (for the Chart.js line chart).
-- Inner query: submissions per day. Outer query: running total.
-- EXPECTED: 4 days with counts 1, 2, 1, 1 and running total 1, 3, 4, 5
-- ---------------------------------------------------------------------
SELECT day, submissions,
       SUM(submissions) OVER (ORDER BY day) AS running_total
FROM (
    SELECT DATE(submitted_at) AS day, COUNT(*) AS submissions
    FROM submissions
    WHERE event_id = 2 AND status = 'SUBMITTED'
    GROUP BY DATE(submitted_at)
) per_day
ORDER BY day;

-- ---------------------------------------------------------------------
-- Q13. Scheduler queries (run every minute in Phase 9).
-- a) OPEN events whose automatic deadline has passed -> should be closed
-- b) SCHEDULED events whose start time has arrived    -> should be opened
-- EXPECTED: both empty right now (event 2 is already closed, event 4
--           starts in 3 days). Uses idx_events_status_deadline / _start.
-- The app would then run:
--   UPDATE events SET status='CLOSED', closed_at=NOW() WHERE event_id = ?;
-- ---------------------------------------------------------------------
SELECT event_id, title, deadline_at
FROM events
WHERE status = 'OPEN' AND deadline_mode = 'AUTOMATIC' AND deadline_at <= NOW();

SELECT event_id, title, start_at
FROM events
WHERE status = 'SCHEDULED' AND start_at <= NOW();

-- ---------------------------------------------------------------------
-- Q14. Reminder de-duplication: pending users of event 1 who have NOT
-- been reminded in the last 36 hours.
-- EXPECTED: empty – Sneha and Rahul were reminded 24 hours ago.
-- Try changing 36 to 12: both of them appear again.
-- ---------------------------------------------------------------------
SELECT u.user_id, u.full_name
FROM users u
WHERE u.user_id IN (5, 9)            -- the pending list from Q3 (Java supplies it)
  AND NOT EXISTS (
        SELECT 1 FROM reminders r
        WHERE r.event_id = 1
          AND r.user_id  = u.user_id
          AND r.sent_at  > NOW() - INTERVAL 36 HOUR
  );

-- ---------------------------------------------------------------------
-- Q15. Which summaries may a participant see right now?
-- PUBLIC_ALWAYS -> always; PUBLIC_AFTER_DEADLINE -> only once closed /
-- past the deadline; PRIVATE -> never.
-- EXPECTED for event 2: summary 1 (RESPONSE_COUNT), 2 (AVERAGE q8), 3 (YES_NO_COUNT q11)
-- Change event_id to 1: only summary 6 – the average is hidden until the deadline.
-- ---------------------------------------------------------------------
SELECT ps.summary_id, ps.summary_type, ps.question_id, ps.visibility
FROM public_summaries ps
JOIN events e ON e.event_id = ps.event_id
WHERE ps.event_id = 2
  AND (
        ps.visibility = 'PUBLIC_ALWAYS'
     OR (ps.visibility = 'PUBLIC_AFTER_DEADLINE'
         AND (e.status = 'CLOSED' OR e.deadline_at <= NOW()))
  );

-- ---------------------------------------------------------------------
-- Q16. Admin dashboard numbers in one row.
-- EXPECTED: users 13, events 4, open 1, closed 1, draft 1, scheduled 1
-- ---------------------------------------------------------------------
SELECT (SELECT COUNT(*) FROM users)  AS total_users,
       COUNT(*)                      AS total_events,
       SUM(status = 'OPEN')          AS open_events,
       SUM(status = 'CLOSED')        AS closed_events,
       SUM(status = 'DRAFT')         AS draft_events,
       SUM(status = 'SCHEDULED')     AS scheduled_events
FROM events;

-- ---------------------------------------------------------------------
-- Q17. Rebuild one person's full answer sheet (creator viewing submission 4).
-- Shows how text, number and choice answers come back together.
-- EXPECTED: 5 rows; row 3 = "Normalization, SQL Joins"
-- ---------------------------------------------------------------------
SELECT q.display_order, q.question_text,
       COALESCE(a.answer_text,
                CAST(a.answer_number AS CHAR),
                GROUP_CONCAT(o.option_text ORDER BY o.display_order SEPARATOR ', ')) AS answer
FROM answers a
JOIN questions q              ON q.question_id = a.question_id
LEFT JOIN answer_selections s ON s.answer_id   = a.answer_id
LEFT JOIN question_options o  ON o.option_id   = s.option_id
WHERE a.submission_id = 4
GROUP BY a.answer_id, q.display_order, q.question_text, a.answer_text, a.answer_number
ORDER BY q.display_order;
