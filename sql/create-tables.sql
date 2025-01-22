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
    final_grade NUMERIC(5, 2)
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
