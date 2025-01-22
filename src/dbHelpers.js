import { queryAndLog } from "./utils.js";

export async function getUserRole(username) {
  const query = "SELECT role FROM users WHERE username = $1";
  const logCallback = (rows) => (rows.length > 0 ? rows[0].role : null);
  return await queryAndLog(query, [username], logCallback);
}

export async function listUsers() {
  const query = "SELECT username, role, id FROM users";
  const logCallback = (rows) => {
    console.log("\nList of users and their roles:");
    rows.forEach((row) => {
      console.log(
        `ID: ${row.id}, Username: ${row.username}, Role: ${row.role}`
      );
    });
  };
  await queryAndLog(query, [], logCallback);
}

export async function listCoursesForTeacher(username) {
  const query = "SELECT * FROM get_courses_for_teacher($1)";
  const logCallback = (rows) => {
    console.log("\nYour courses:");
    rows.forEach((row) => {
      console.log(`ID: ${row.course_id}, Course Name: ${row.course_name}`);
    });
  };
  await queryAndLog(query, [username], logCallback);
}

export async function listCoursesForStudent(username) {
  const query = "SELECT * FROM get_courses_for_student($1)";
  const logCallback = (rows) => {
    console.log("\nYour courses:");
    rows.forEach((row) => {
      console.log(
        `ID: ${row.course_id}, Course Name: ${row.course_name}, Final Grade: ${row.final_grade}`
      );
    });
  };
  await queryAndLog(query, [username], logCallback);
}

export async function listCourseInfo(courseId) {
  const query = `SELECT c.name, c.description, c.ects, c.id 
                 FROM courses c 
                 WHERE c.id = $1`;
  const logCallback = (rows) => {
    const course = rows[0];
    console.log(
      `ID: ${course.id}, Course Name: ${course.name}, Description: ${course.description}, ECTS: ${course.ects}`
    );
  };
  await queryAndLog(query, [courseId], logCallback);
}

export async function viewGradeHistory(username) {
  const query = "SELECT * FROM view_grade_history($1)";
  const logCallback = (rows) => {
    console.log("Grade History:");
    rows.forEach((row) => {
      console.log(`ID: ${row.grade_history_id}, Old Grade: ${row.old_grade}, New Grade: ${row.new_grade}, 
        Change Timestamp: ${row.change_timestamp}, Teacher: ${row.teacher_username}, 
        Reason: ${row.change_reason}`);
    });
  };
  await queryAndLog(query, [username], logCallback);
}

export async function listEnrollmentsForCourse(courseId) {
  const query = "SELECT * FROM get_enrollments_for_course($1)";
  const logCallback = (rows) => {
    console.log("\nEnrollments for the course:");
    rows.forEach((row) => {
      console.log(
        `Enrollment ID: ${row.enrollment_id}, Student: ${row.student_username}, Final Grade: ${row.final_grade}`
      );
    });
  };
  await queryAndLog(query, [courseId], logCallback);
}

export async function listGradeComponentsForCourse(courseId) {
  const query = "SELECT * FROM get_grade_components_for_course($1)";
  const logCallback = (rows) => {
    console.log("\nGrade components for the course:");
    rows.forEach((row) => {
      console.log(
        `Grade Component ID: ${row.grade_component_id}, Name: ${row.component_name}, Max Score: ${row.max_score}`
      );
    });
  };
  await queryAndLog(query, [courseId], logCallback);
}

export async function listStudentGradesForEnrollment(enrollmentId) {
  const query = "SELECT * FROM get_student_grades_for_enrollment($1)";
  const logCallback = (rows) => {
    console.log("\nGrades for the student in this course:");
    rows.forEach((row) => {
      console.log(
        `Grade Component: ${row.component_name}, Grade: ${row.grade}`
      );
    });
  };
  await queryAndLog(query, [enrollmentId], logCallback);
}

export async function listCourses() {
  const query = "SELECT id, name FROM courses";
  const logCallback = (rows) => {
    rows.forEach((course) => {
      console.log(`ID: ${course.id}, Course Name: ${course.name}`);
    });
  };
  await queryAndLog(query, [], logCallback);
}

export async function displayStudentInfo(username) {
  const query = "SELECT * FROM get_student_info($1)";
  const logCallback = (rows) => {
    const row = rows[0];
    console.log(
      `Programme: ${row.programme}, ECTS: ${row.ects}, GPA: ${row.gpa}`
    );
  };
  await queryAndLog(query, [username], logCallback);
}
