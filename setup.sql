DROP TABLE IF EXISTS grades, grade_components, enrollments, courseteachers, courses, teachers, students, users CASCADE;

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
    programme VARCHAR(50) NOT NULL,
    -- GPA is calculated on request, and not stored
);

-- Extra table coz ONLY TEACHER USERS need "contact_room"
-- Also later used for relations for better readibility
CREATE TABLE teachers (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    contact_room VARCHAR(50) NOT NULL,
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
    final_grade NUMERIC(4, 2),
);

-- Only teachers of a course can change the grades for this course's students
CREATE TABLE courseteachers (
    id SERIAL PRIMARY KEY,
    teacher_id INTEGER NOT NULL REFERENCES teachers(id) ON DELETE CASCADE,
    course_id INTEGER NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
    assigned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
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
    old_grade NUMERIC(2, 1),
    new_grade NUMERIC(2, 1),
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
    p_enrollment_id INTEGER,         -- Enrollment ID
    p_grade_component_id INTEGER,    -- Grade component ID
    p_new_grade NUMERIC(5, 2),       -- Grade value to be assigned/updated
    p_teacher_id INTEGER,            -- Teacher ID who is assigning/updating the grade
    p_change_reason TEXT             -- Reason for the grade change
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_existing_grade NUMERIC(5, 2);
    v_grade_id INTEGER;
BEGIN
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
            SELECT g.id, v_existing_grade, p_new_grade, p_teacher_id, CURRENT_TIMESTAMP, p_change_reason
            FROM grades g
            WHERE g.enrollment_id = p_enrollment_id
            AND g.grade_component_id = p_grade_component_id;
            
            RAISE NOTICE 'Grade for enrollment % and grade component % updated to %.', p_enrollment_id, p_grade_component_id, p_new_grade;
        ELSE
            RAISE NOTICE 'The grade is already set to the new value, no change made.';
        END IF;
    ELSE
        INSERT INTO grades (enrollment_id, grade_component_id, grade)
        VALUES (p_enrollment_id, p_grade_component_id, p_new_grade)
        RETURNING id INTO v_grade_id;

        INSERT INTO grades_history (grade_id, old_grade, new_grade, teacher_id, change_timestamp, change_reason)
        VALUES (v_grade_id, NULL, p_new_grade, p_teacher_id, CURRENT_TIMESTAMP, p_change_reason);

        RAISE NOTICE 'Grade for enrollment % and grade component % assigned with %.', p_enrollment_id, p_grade_component_id, p_new_grade;
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
    final_grade NUMERIC(2, 1);
    missing_grades INTEGER;
BEGIN
    -- 1. Ensure there are no "missing grades", coz all components have to be graded
    --  in order to calculate and set the final grade (otherwise we'll have lots of 2.0)
    SELECT COUNT(*) INTO missing_grades
    FROM grade_components gc
    LEFT JOIN grades g ON g.grade_component_id = gc.id AND g.enrollment_id = NEW.enrollment_id
    WHERE g.grade IS NULL
    AND gc.course_id = NEW.course_id;

    IF missing_grades > 0 THEN
        RAISE NOTICE 'Not all grade components are graded for this enrolment. Final grade will not be updated.';
        RETURN NEW;
    END IF;

    -- 2. Normalize the grade to 0-100
    FOR grade_record IN
        SELECT g.grade, gc.max_score
        FROM grades g
        JOIN grade_components gc ON g.grade_component_id = gc.id
        WHERE g.enrollment_id = NEW.enrollment_id
    LOOP
        total_score := total_score;
        total_max_score := total_max_score + gc.max_score;
    END LOOP;

    IF total_max_score > 0 THEN
        average_score := (total_score / total_max_score) * 100;
    ELSE
        RAISE NOTICE 'Not updating final grade as no points can be earned for this course.';
        RETURN NEW;
    END IF;

    -- 3. Map the final grade from 0-100 to 2-5
    IF average_score >= 91 THEN
        final_grade := 5.0;
    ELSIF average_score >= 81 THEN
        final_grade := 4.5;
    ELSIF average_score >= 71 THEN
        final_grade := 4.0;
    ELSIF average_score >= 61 THEN
        final_grade := 3.5;
    ELSIF average_score >= 51 THEN
        final_grade := 3.0;
    ELSE
        final_grade := 2.0;
    END IF;

    -- 4. Finally, update
    UPDATE enrollments
    SET final_grade = final_grade
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

---------------------------------------------------------------------------
-- Create admin
---------------------------------------------------------------------------

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
    p_teacher_id INTEGER,      -- Teacher ID to be assigned
    p_course_id INTEGER        -- Course ID the teacher will be assigned to
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO courseteachers (teacher_id, course_id)
    VALUES (p_teacher_id, p_course_id);
    RAISE NOTICE 'Teacher % assigned to course %.', p_teacher_id, p_course_id;
END;
$$;

---------------------------------------------------------------------------
-- Enroll a student in a course
---------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE enroll_student(
    p_student_id INTEGER,     -- Student ID to enroll
    p_course_id INTEGER       -- Course ID to enroll the student in
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO enrollments (student_id, course_id)
    VALUES (p_student_id, p_course_id);
    RAISE NOTICE 'Student % enrolled in course %.', p_student_id, p_course_id;
END;
$$;