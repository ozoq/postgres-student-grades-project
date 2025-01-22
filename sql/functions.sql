
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

---------------------------------------------------------------------------
-- get_enrollments_for_course
---------------------------------------------------------------------------
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

---------------------------------------------------------------------------
-- get_grade_components_for_course
---------------------------------------------------------------------------
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

---------------------------------------------------------------------------
-- get_student_grades_for_enrollment
---------------------------------------------------------------------------
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

---------------------------------------------------------------------------
-- get_student_gpa
---------------------------------------------------------------------------
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

---------------------------------------------------------------------------
-- get_student_ects
---------------------------------------------------------------------------
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

---------------------------------------------------------------------------
-- get_student_info
---------------------------------------------------------------------------
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