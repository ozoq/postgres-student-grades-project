DROP TABLE IF EXISTS grades, grade_components, enrollments, courseteachers, courses, teachers, students, users, grades_history CASCADE;

CREATE TABLE users (
    -- I am not sure if I will ever need to define my own sequences in this project
    -- Postgres has this feature called "SERIAL" so field can auto-increment automatically
    -- Without the need to create an external sequence
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) NOT NULL,
    -- Admin is the one who will be able to create courses and grade components
    -- And assign teachers to courses
    -- And create/delete users
    -- Role is not to be changed for an existing user
    role VARCHAR(20) NOT NULL CHECK (role IN ('student', 'teacher', 'admin')),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Extra table coz ONLY STUDENT USERS need "programme"
-- Also later used for relations for better readibility
CREATE TABLE students (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    programme VARCHAR(50) NOT NULL
    -- GPA is calculated on request, and not stored
);

-- Extra table coz ONLY TEACHER USERS need "contact_room"
-- Also later used for relations for better readibility
CREATE TABLE teachers (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    contact_room VARCHAR(50) NOT NULL
);

CREATE TABLE courses (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    -- ECTS used to calculate weighted GPA
    ects INTEGER NOT NULL CHECK (ects > 0),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Each course can have several grade components
-- For example, kolokwium-1, kolokwium-2, lab-1, exam, etc.
CREATE TABLE grade_components (
    id SERIAL PRIMARY KEY,
    course_id INTEGER NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    max_score NUMERIC(5, 2) NOT NULL CHECK (max_score > 0),
    -- It is cleaner this way (No dublicate names)
    UNIQUE (course_id, name)
);

CREATE TABLE enrollments (
    id SERIAL PRIMARY KEY,
    -- Note: One student can take one course multiple times
    student_id INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    course_id INTEGER NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
    -- Not the usual timestamp so to diverse the project with feature richness 
    enrollment_date DATE DEFAULT CURRENT_DATE,
    -- Note: Total grade is nullable, updated automatically via triggers
    final_grade NUMERIC(4, 2)
);

-- Only teachers of a course can change the grades for this course's students
CREATE TABLE courseteachers (
    id SERIAL PRIMARY KEY,
    teacher_id INTEGER NOT NULL REFERENCES teachers(id) ON DELETE CASCADE,
    course_id INTEGER NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
    assigned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (teacher_id, course_id)
);

-- Grades table (Linked to grade components for each student)
CREATE TABLE grades (
    id SERIAL PRIMARY KEY,
    enrollment_id INTEGER NOT NULL REFERENCES enrollments(id) ON DELETE CASCADE,
    grade_component_id INTEGER NOT NULL REFERENCES grade_components(id) ON DELETE CASCADE,
    grade NUMERIC(5, 2) CHECK (grade >= 0), -- between 0 and max score for that component
    graded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    -- Only one grade for a grade component!
    UNIQUE (enrollment_id, grade_component_id)
);

-- This one has more info than just a grade, so it is not updated via trigger
-- But via a procedure
CREATE TABLE grades_history (
    id SERIAL PRIMARY KEY,
    grade_id INTEGER NOT NULL REFERENCES grades(id) ON DELETE CASCADE,
    old_grade NUMERIC(5, 1),
    new_grade NUMERIC(5, 1),
     -- Teacher who made the change
    teacher_id INTEGER NOT NULL REFERENCES teachers(id) ON DELETE CASCADE,
    change_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    change_reason TEXT
);

---------------------------------------------------------------------------
-- Trigger to prevent changing the role on an existing user
-- If ever a student becomes a teacher he needs a new account
---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION prevent_role_update()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.role <> OLD.role THEN
        RAISE EXCEPTION 'Role cannot be updated';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER prevent_role_update_trigger
BEFORE UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION prevent_role_update();

---------------------------------------------------------------------------
-- Trigger to prevent reassinging the user of student or teacher
-- Basically same logic as to preventing changing the role in the trigger above
---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION prevent_user_id_update()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.user_id <> OLD.user_id THEN
        -- https://www.postgresql.org/docs/current/plpgsql-trigger.html
        -- TG_TABLE_NAME: table that caused the trigger invocation.
        RAISE EXCEPTION 'user_id cannot be updated in % table', TG_TABLE_NAME;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER prevent_user_id_update_trigger_students
BEFORE UPDATE ON students
FOR EACH ROW
EXECUTE FUNCTION prevent_user_id_update();

CREATE TRIGGER prevent_user_id_update_trigger_teachers
BEFORE UPDATE ON teachers
FOR EACH ROW
EXECUTE FUNCTION prevent_user_id_update();


---------------------------------------------------------------------------
-- Procedure to assign or update the grade with history
-- There also somewhere a trigger that updates the final_grade
---------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE assign_or_update_grade(
    p_enrollment_id INTEGER,
    p_grade_component_id INTEGER,
    p_new_grade NUMERIC(5, 2),
    p_teacher_username VARCHAR,
    p_change_reason TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_existing_grade NUMERIC(5, 2);
    v_grade_id INTEGER;
    v_teacher_id INTEGER;
    v_course_id INTEGER;
    v_component_course_id INTEGER;
BEGIN
    v_teacher_id := get_user_role_based_id(p_teacher_username, 'teacher');

    SELECT course_id INTO v_course_id
    FROM enrollments
    WHERE id = p_enrollment_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Enrollment ID % does not exist.', p_enrollment_id;
    END IF;

    SELECT course_id INTO v_component_course_id
    FROM grade_components
    WHERE id = p_grade_component_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Grade component ID % does not exist.', p_grade_component_id;
    END IF;

    IF v_course_id <> v_component_course_id THEN
        RAISE EXCEPTION 'Grade component ID % does not belong to the course for enrollment ID %.', 
            p_grade_component_id, p_enrollment_id;
    END IF;

    SELECT grade INTO v_existing_grade
    FROM grades
    WHERE enrollment_id = p_enrollment_id
    AND grade_component_id = p_grade_component_id;

    IF FOUND THEN
        IF v_existing_grade <> p_new_grade THEN
            UPDATE grades
            SET grade = p_new_grade, graded_at = CURRENT_TIMESTAMP
            WHERE enrollment_id = p_enrollment_id
            AND grade_component_id = p_grade_component_id;

            INSERT INTO grades_history (grade_id, old_grade, new_grade, teacher_id, change_timestamp, change_reason)
            SELECT g.id, v_existing_grade, p_new_grade, v_teacher_id, CURRENT_TIMESTAMP, p_change_reason
            FROM grades g
            WHERE g.enrollment_id = p_enrollment_id
            AND g.grade_component_id = p_grade_component_id;

            RAISE NOTICE 'Grade for enrollment % and grade component % updated to %.', 
                p_enrollment_id, p_grade_component_id, p_new_grade;
        ELSE
            RAISE NOTICE 'The grade is already set to the new value, no change made.';
        END IF;
    ELSE
        INSERT INTO grades (enrollment_id, grade_component_id, grade)
        VALUES (p_enrollment_id, p_grade_component_id, p_new_grade)
        RETURNING id INTO v_grade_id;

        INSERT INTO grades_history (grade_id, old_grade, new_grade, teacher_id, change_timestamp, change_reason)
        VALUES (v_grade_id, NULL, p_new_grade, v_teacher_id, CURRENT_TIMESTAMP, p_change_reason);

        RAISE NOTICE 'Grade for enrollment % and grade component % assigned with %.', 
            p_enrollment_id, p_grade_component_id, p_new_grade;
    END IF;
END;
$$;

---------------------------------------------------------------------------
-- Trigger to update final grade when a grade on a grade compnent changes
-- Final grade will only be set if all the grade components has been graded
-- Then, changes to grade components will reflect to final grade
-- Sort of how it is done in USOS
---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION update_final_grade()
RETURNS TRIGGER AS $$
DECLARE
    total_score NUMERIC(5, 2) := 0;
    total_max_score NUMERIC(5, 2) := 0;
    average_score NUMERIC(5, 2);
    v_final_grade NUMERIC(2, 1);
    missing_grades INTEGER;
    grade_record RECORD;
    grade_cursor CURSOR FOR
        SELECT g.grade, gc.max_score
        FROM grades g
        JOIN grade_components gc ON g.grade_component_id = gc.id
        WHERE g.enrollment_id = NEW.enrollment_id;
BEGIN
    -- 1. Ensure there are no "missing grades", coz all components have to be graded
    -- in order to calculate and set the final grade (otherwise we'll have lots of 2.0)
    SELECT COUNT(*) INTO missing_grades
    FROM grade_components gc
    LEFT JOIN grades g ON g.grade_component_id = gc.id AND g.enrollment_id = NEW.enrollment_id
    JOIN enrollments e ON e.id = NEW.enrollment_id
    WHERE g.grade IS NULL
    AND gc.course_id = e.course_id;

    IF missing_grades > 0 THEN
        RAISE NOTICE 'Not all grade components are graded for this enrolment. Final grade will not be updated.';
        RETURN NEW;
    END IF;

    -- 2. Normalize the grade to 0-100
    OPEN grade_cursor;
    LOOP
        FETCH grade_cursor INTO grade_record;
        EXIT WHEN NOT FOUND;

        -- Accumulate the total score and total max score
        total_score := total_score + grade_record.grade;
        total_max_score := total_max_score + grade_record.max_score;
    END LOOP;
    CLOSE grade_cursor;

    IF total_max_score > 0 THEN
        average_score := (total_score / total_max_score) * 100;
    ELSE
        RAISE NOTICE 'Not updating final grade as no points can be earned for this course.';
        RETURN NEW;
    END IF;

    -- 3. Map the final grade from 0-100 to 2-5
    IF average_score >= 91 THEN
        v_final_grade := 5.0;
    ELSIF average_score >= 81 THEN
        v_final_grade := 4.5;
    ELSIF average_score >= 71 THEN
        v_final_grade := 4.0;
    ELSIF average_score >= 61 THEN
        v_final_grade := 3.5;
    ELSIF average_score >= 51 THEN
        v_final_grade := 3.0;
    ELSE
        v_final_grade := 2.0;
    END IF;

    -- 4. Finally, update the final grade
    UPDATE enrollments
    SET final_grade = v_final_grade
    WHERE id = NEW.enrollment_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER update_final_grade_trigger
AFTER UPDATE ON grades
FOR EACH ROW
EXECUTE FUNCTION update_final_grade();


---------------------------------------------------------------------------
-- Procedure to create a user
-- Not gonna be used by application
-- But will be used by other wrappers
---------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE create_user(
    p_username VARCHAR(50),
    p_role VARCHAR(20),
    p_programme VARCHAR(50),
    p_contact_room VARCHAR(50)
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_user_id INTEGER;
BEGIN
    INSERT INTO users (username, role)
    VALUES (p_username, p_role)
    RETURNING id INTO v_user_id;

    IF p_role = 'student' THEN
        INSERT INTO students (user_id, programme)
        VALUES (v_user_id, p_programme);
    ELSIF p_role = 'teacher' THEN
        INSERT INTO teachers (user_id, contact_room)
        VALUES (v_user_id, p_contact_room);
    ELSIF p_role = 'admin' THEN
        NULL;
    ELSE
        RAISE EXCEPTION 'Invalid role: %', p_role;
    END IF;

    RAISE NOTICE 'User % created with role %.', p_username, p_role;
END;
$$;

---------------------------------------------------------------------------
-- Create teacher
---------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE create_teacher(
    p_username VARCHAR(50),
    p_contact_room VARCHAR(50)
)
LANGUAGE plpgsql
AS $$
BEGIN
    CALL create_user(p_username, 'teacher', NULL, p_contact_room);
END;
$$;

---------------------------------------------------------------------------
-- Create student
---------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE create_student(
    p_username VARCHAR(50),
    p_programme VARCHAR(50)
)
LANGUAGE plpgsql
AS $$
BEGIN
    CALL create_user(p_username, 'student', p_programme, NULL);
END;
$$;

-------------------------------------------------------------------------
-- Create admin
-------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE create_admin(
    p_username VARCHAR(50)
)
LANGUAGE plpgsql
AS $$
BEGIN
    CALL create_user(p_username, 'admin', NULL, NULL);
END;
$$;

---------------------------------------------------------------------------
-- Create a course
---------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE create_course(
    p_name VARCHAR(100),     -- Name of the course
    p_description TEXT,      -- Description of the course
    p_ects INTEGER           -- ECTS credits for the course
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO courses (name, description, ects)
    VALUES (p_name, p_description, p_ects);
    RAISE NOTICE 'Course % created.', p_name;
END;
$$;

---------------------------------------------------------------------------
-- Create a grade component
---------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE create_grade_component(
    p_course_id INTEGER,       -- Course ID the grade component belongs to
    p_name VARCHAR(100),       -- Name of the grade component
    p_max_score NUMERIC(5, 2)  -- Maximum score for the grade component
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO grade_components (course_id, name, max_score)
    VALUES (p_course_id, p_name, p_max_score);
    RAISE NOTICE 'Grade component % for course % created.', p_name, p_course_id;
END;
$$;

---------------------------------------------------------------------------
-- Assign a teacher to a course
---------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE assign_teacher_to_course(
    p_teacher_username VARCHAR,  -- Teacher's username to be assigned
    p_course_id INTEGER         -- Course ID the teacher will be assigned to
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_teacher_id INTEGER;
BEGIN
    v_teacher_id := get_user_role_based_id(p_teacher_username, 'teacher');

    INSERT INTO courseteachers (teacher_id, course_id)
    VALUES (v_teacher_id, p_course_id);

    RAISE NOTICE 'Teacher "%" assigned to course %.', p_teacher_username, p_course_id;
END;
$$;


---------------------------------------------------------------------------
-- Enroll a student in a course
---------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE enroll_student(
    p_student_username VARCHAR,   -- Student's username to enroll
    p_course_id INTEGER           -- Course ID to enroll the student in
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_student_id INTEGER;
BEGIN
    v_student_id := get_user_role_based_id(p_student_username, 'student');

    INSERT INTO enrollments (student_id, course_id)
    VALUES (v_student_id, p_course_id);

    RAISE NOTICE 'Student "%" enrolled in course %.', p_student_username, p_course_id;
END;
$$;


---------------------------------------------------------------------------
-- get_courses_for_teacher
---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_courses_for_teacher(p_username VARCHAR)
RETURNS TABLE(course_id INT, course_name VARCHAR) AS $$
DECLARE
  v_teacher_id INT;
BEGIN
  v_teacher_id := get_user_role_based_id(p_username, 'teacher');

  RETURN QUERY
  SELECT c.id, c.name
  FROM courses c
  JOIN courseteachers ct ON c.id = ct.course_id
  WHERE ct.teacher_id = v_teacher_id;
END;
$$ LANGUAGE plpgsql;


---------------------------------------------------------------------------
-- get_courses_for_student
---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_courses_for_student(p_username VARCHAR)
RETURNS TABLE(course_id INT, course_name VARCHAR, final_grade NUMERIC(4, 2)) AS $$
DECLARE
  v_student_id INT;
BEGIN
  v_student_id := get_user_role_based_id(p_username, 'student');

  RETURN QUERY
  SELECT c.id, c.name, e.final_grade
  FROM courses c
  JOIN enrollments e ON c.id = e.course_id
  WHERE e.student_id = v_student_id;
END;
$$ LANGUAGE plpgsql;



---------------------------------------------------------------------------
-- get_user_role_based_id
---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_user_role_based_id(
    p_username VARCHAR,
    p_required_role VARCHAR
)
RETURNS INTEGER AS $$
DECLARE
    v_user_id INTEGER;
    v_role VARCHAR;
BEGIN
    SELECT u.id, u.role INTO v_user_id, v_role
    FROM users u
    WHERE u.username = p_username;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'User with username "%" not found', p_username;
    END IF;

    IF v_role != p_required_role THEN
        RAISE EXCEPTION 'User "%" does not have the required role "%", actual role: "%"', 
                        p_username, p_required_role, v_role;
    END IF;

    IF v_role = 'student' THEN
        SELECT s.id INTO v_user_id
        FROM students s
        WHERE s.user_id = v_user_id;
    ELSIF v_role = 'teacher' THEN
        SELECT t.id INTO v_user_id
        FROM teachers t
        WHERE t.user_id = v_user_id;
    ELSE
        RAISE EXCEPTION 'Role "%" not recognized for username "%"', v_role, p_username;
    END IF;

    RETURN v_user_id;
END;
$$ LANGUAGE plpgsql;

---------------------------------------------------------------------------
-- delete user
---------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE delete_user(
    p_username VARCHAR(50)  -- Username of the user to delete
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_user_id INTEGER;
    v_role VARCHAR(20);
BEGIN
    SELECT u.id, u.role INTO v_user_id, v_role
    FROM users u
    WHERE u.username = p_username;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'User with username "%" not found', p_username;
    END IF;

    DELETE FROM users WHERE id = v_user_id;

    RAISE NOTICE 'User "%" and all associated data have been deleted.', p_username;
END;
$$;

---------------------------------------------------------------------------
-- delete course
---------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE delete_course(
    p_course_id INTEGER  -- ID of the course to delete
)
LANGUAGE plpgsql
AS $$
BEGIN
    -- Delete the course, related enrollments, grades, grade components, and course-teacher assignments will be handled by CASCADE
    DELETE FROM courses
    WHERE id = p_course_id;

    RAISE NOTICE 'Course with ID % and all associated data have been deleted.', p_course_id;
END;
$$;


---------------------------------------------------------------------------
-- change_course_info
---------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE change_course_info(
    p_course_id INTEGER,            -- ID of the course to update
    p_new_name VARCHAR(100),        -- New name of the course
    p_new_description TEXT,         -- New description of the course
    p_new_ects INTEGER              -- New ECTS credits for the course
)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE courses
    SET name = p_new_name,
        description = p_new_description,
        ects = p_new_ects
    WHERE id = p_course_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Course with ID % not found.', p_course_id;
    END IF;

    RAISE NOTICE 'Course with ID % updated successfully.', p_course_id;
END;
$$;

---------------------------------------------------------------------------
-- create_grade_component
---------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE create_grade_component(
    p_course_id INTEGER,       -- Course ID the grade component belongs to
    p_name VARCHAR(100),       -- Name of the grade component
    p_max_score NUMERIC(5, 2)  -- Maximum score for the grade component
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO grade_components (course_id, name, max_score)
    VALUES (p_course_id, p_name, p_max_score);

    RAISE NOTICE 'Grade component "%" for course % created.', p_name, p_course_id;
END;
$$;

---------------------------------------------------------------------------
-- change_teacher_room
---------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE change_teacher_room(
    p_teacher_username VARCHAR,      -- Teacher's username whose contact room needs to be changed
    p_new_contact_room VARCHAR(50)   -- New contact room for the teacher
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_teacher_id INTEGER;
BEGIN
    v_teacher_id := get_user_role_based_id(p_teacher_username, 'teacher');

    UPDATE teachers
    SET contact_room = p_new_contact_room
    WHERE id = v_teacher_id;

    RAISE NOTICE 'Teacher "%" contact room updated to "%".', p_teacher_username, p_new_contact_room;
END;
$$;


---------------------------------------------------------------------------
-- view_grade_history
---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION view_grade_history(p_username VARCHAR)
RETURNS TABLE (
    grade_history_id INT,
    old_grade NUMERIC(5, 2),
    new_grade NUMERIC(5, 2),
    change_timestamp TIMESTAMP,
    change_reason TEXT,
    teacher_username VARCHAR
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        gh.id AS grade_history_id,
        gh.old_grade,
        gh.new_grade,
        gh.change_timestamp,
        gh.change_reason,
        u.username AS teacher_username
    FROM grades_history gh
    JOIN grades g ON gh.grade_id = g.id
    JOIN enrollments e ON g.enrollment_id = e.id
    JOIN students s ON e.student_id = s.id
    JOIN teachers t ON gh.teacher_id = t.id
    JOIN users u ON t.user_id = u.id
    WHERE s.id = get_user_role_based_id(p_username, 'student')
    ORDER BY gh.change_timestamp DESC;
END;
$$ LANGUAGE plpgsql;






CREATE OR REPLACE FUNCTION get_enrollments_for_course(for_course_id INT)
RETURNS TABLE(
  enrollment_id INT,
  student_username VARCHAR,
  final_grade NUMERIC(4, 2)
) AS $$
BEGIN
  RETURN QUERY
  SELECT e.id, u.username, e.final_grade
  FROM enrollments e
  JOIN students s ON e.student_id = s.id
  JOIN users u ON s.user_id = u.id
  WHERE e.course_id = for_course_id;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION get_grade_components_for_course(for_course_id INT)
RETURNS TABLE(
  grade_component_id INT,
  component_name VARCHAR,
  max_score NUMERIC(5, 2)
) AS $$
BEGIN
  RETURN QUERY
  SELECT gc.id, gc.name, gc.max_score
  FROM grade_components gc
  WHERE gc.course_id = for_course_id;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION get_student_grades_for_enrollment(for_enrollment_id INT)
RETURNS TABLE(
  component_name VARCHAR,
  grade NUMERIC(5, 2)
) AS $$
BEGIN
  RETURN QUERY
  SELECT gc.name, g.grade
  FROM grades g
  JOIN grade_components gc ON g.grade_component_id = gc.id
  WHERE g.enrollment_id = for_enrollment_id;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION get_student_gpa(p_username VARCHAR)
RETURNS NUMERIC(4, 2) AS $$
DECLARE
    v_student_id INTEGER;
    v_gpa NUMERIC(4, 2);
BEGIN
    v_student_id := get_user_role_based_id(p_username, 'student');

    SELECT 
        CASE
            WHEN SUM(c.ects) = 0 THEN NULL
            ELSE ROUND(SUM(e.final_grade * c.ects) / SUM(c.ects), 2)
        END
    INTO v_gpa
    FROM courses c
    JOIN enrollments e ON c.id = e.course_id
    WHERE e.student_id = v_student_id
    AND e.final_grade IS NOT NULL;

    RETURN v_gpa;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION get_student_ects(p_username VARCHAR)
RETURNS INTEGER AS $$
DECLARE
    v_student_id INTEGER;
    v_total_ects INTEGER;
BEGIN
    v_student_id := get_user_role_based_id(p_username, 'student');

    SELECT COALESCE(SUM(c.ects), 0)
    INTO v_total_ects
    FROM courses c
    JOIN enrollments e ON c.id = e.course_id
    WHERE e.student_id = v_student_id
    AND e.final_grade IS NOT NULL;

    RETURN v_total_ects;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION get_student_info(p_username VARCHAR)
RETURNS TABLE (programme VARCHAR, ects INTEGER, gpa NUMERIC(4, 2)) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        s.programme,
        get_student_ects(p_username) AS ects,
        get_student_gpa(p_username) AS gpa
    FROM students s
    WHERE s.id = get_user_role_based_id(p_username, 'student');
END;
$$ LANGUAGE plpgsql;
