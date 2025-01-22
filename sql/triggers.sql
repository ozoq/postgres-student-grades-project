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