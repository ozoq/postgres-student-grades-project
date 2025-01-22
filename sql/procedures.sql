
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

