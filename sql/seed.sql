-- Users
INSERT INTO users (username, role) VALUES
('admin', 'admin'),
('teacher1', 'teacher'),
('student1', 'student'),
('student2', 'student'),
('student3', 'student');

-- Students
INSERT INTO students (user_id, programme) VALUES
(3, 'Computer Science'),
(4, 'Data Science'),
(5, 'Software Engineering');

-- Teachers
INSERT INTO teachers (user_id, contact_room) VALUES
(2, 'Room 101');

-- Courses
INSERT INTO courses (name, description, ects) VALUES
('Course1', 'Description for Course1', 6),
('Course2', 'Description for Course2', 6),
('Course3', 'Description for Course3', 6),
('Course4', 'Description for Course4', 6);

-- Grade Components
INSERT INTO grade_components (course_id, name, max_score) VALUES
(1, 'Assignment 1', 100),
(1, 'Midterm Exam', 100),
(1, 'Final Exam', 100),
(2, 'Assignment 1', 100),
(2, 'Midterm Exam', 100),
(2, 'Final Exam', 100),
(3, 'Assignment 1', 100),
(3, 'Final Project', 100),
(3, 'Final Exam', 100),
(4, 'Homework 1', 100),
(4, 'Midterm Exam', 100),
(4, 'Final Exam', 100);

-- Assign Teachers to Courses
INSERT INTO courseteachers (teacher_id, course_id) VALUES
(1, 1),  -- Teacher1 teaches Course1
(1, 2),  -- Teacher1 teaches Course2
(1, 3),  -- Teacher1 teaches Course3
(1, 4);  -- Teacher1 teaches Course4

-- Enroll Students in Courses
INSERT INTO enrollments (student_id, course_id, enrollment_date) VALUES
(1, 1, '2025-01-10'),
(2, 1, '2025-01-12'),
(3, 2, '2025-01-15'),
(1, 3, '2025-01-20'),
(2, 4, '2025-01-22'),
(3, 3, '2025-01-23');

-- Grades
INSERT INTO grades (enrollment_id, grade_component_id, grade) VALUES
(1, 1, 85),
(1, 2, 90),
(1, 3, 95),
(2, 1, 75),
(2, 2, 80),
(2, 3, 70),
(3, 1, 88),
(3, 2, 78),
(3, 3, 80);

-- Grades History
INSERT INTO grades_history (grade_id, old_grade, new_grade, teacher_id, change_reason) VALUES
(1, 85, 88, 1, 'Misstake fixed'),
(3, 78, 80, 1, 'Resit');

-- Final Grades
UPDATE enrollments SET final_grade = 4.5 WHERE id = 1;
UPDATE enrollments SET final_grade = 3.0 WHERE id = 2;
UPDATE enrollments SET final_grade = 3.5 WHERE id = 3;
