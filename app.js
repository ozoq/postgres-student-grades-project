import { client } from "./dbClient.js";
import readlineSync from "readline-sync";

client.connect();

async function callProcedure(procedure, ...params) {
  const query = `CALL ${procedure}(${params.map((p) => `'${p}'`).join(", ")});`;
  try {
    await client.query(query);
    console.log(`Procedure ${procedure} executed successfully.`);
  } catch (err) {
    console.error(`Error executing ${procedure}:`, err.message);
  }
}

async function getUserRole(username) {
  try {
    const res = await client.query(
      "SELECT role FROM users WHERE username = $1",
      [username]
    );
    if (res.rows.length > 0) {
      return res.rows[0].role;
    }
    return null;
  } catch (err) {
    console.error("Error fetching user role:", err.message);
    return null;
  }
}

async function listUsers() {
  try {
    const res = await client.query("SELECT username, role, id FROM users");
    if (res.rows.length > 0) {
      console.log("\nList of users and their roles:");
      res.rows.forEach((row) => {
        console.log(
          `ID: ${row.id}, Username: ${row.username}, Role: ${row.role}`
        );
      });
    } else {
      console.log("No users found.");
    }
  } catch (err) {
    console.error("Error fetching users:", err.message);
  }
}

async function listCoursesForTeacher(username) {
  try {
    const res = await client.query(
      "SELECT * FROM get_courses_for_teacher($1)",
      [username]
    );
    if (res.rows.length > 0) {
      console.log("\nYour courses:");
      res.rows.forEach((row) => {
        console.log(`ID: ${row.course_id}, Course Name: ${row.course_name}`);
      });
    } else {
      console.log("You are not assigned to any courses.");
    }
  } catch (err) {
    console.error("Error fetching courses for teacher:", err.message);
  }
}

async function listCoursesForStudent(username) {
  try {
    const res = await client.query(
      "SELECT * FROM get_courses_for_student($1)",
      [username]
    );
    if (res.rows.length > 0) {
      console.log("\nYour courses:");
      res.rows.forEach((row) => {
        console.log(
          `ID: ${row.course_id}, Course Name: ${row.course_name}, Final Grade: ${row.final_grade}`
        );
      });
    } else {
      console.log("You are not enrolled in any courses.");
    }
  } catch (err) {
    console.error("Error fetching courses for student:", err.message);
  }
}

async function listCourseInfo(courseId) {
  try {
    const res = await client.query(
      `SELECT c.name, c.description, c.ects, c.id 
       FROM courses c 
       WHERE c.id = $1`,
      [courseId]
    );
    if (res.rows.length > 0) {
      const course = res.rows[0];
      console.log(
        `ID: ${course.id}, Course Name: ${course.name}, Description: ${course.description}, ECTS: ${course.ects}`
      );
    } else {
      console.log("Course not found.");
    }
  } catch (err) {
    console.error("Error fetching course information:", err.message);
  }
}

async function viewGradeHistory(username) {
  try {
    const res = await client.query(`SELECT * FROM view_grade_history($1)`, [
      username,
    ]);

    if (res.rows.length === 0) {
      console.log(
        "No grade history found or you do not have permission to view it."
      );
    } else {
      console.log("Grade History:");
      res.rows.forEach((row) => {
        console.log(`ID: ${row.grade_history_id}, Old Grade: ${row.old_grade}, New Grade: ${row.new_grade}, 
          Change Timestamp: ${row.change_timestamp}, Teacher: ${row.teacher_username}, 
          Reason: ${row.change_reason}`);
      });
    }
  } catch (err) {
    console.error("Error fetching grade history:", err.message);
  }
}

async function listEnrollmentsForCourse(courseId) {
  try {
    const res = await client.query(
      "SELECT * FROM get_enrollments_for_course($1)",
      [courseId]
    );
    if (res.rows.length > 0) {
      console.log("\nEnrollments for the course:");
      res.rows.forEach((row) => {
        console.log(
          `Enrollment ID: ${row.enrollment_id}, Student: ${row.student_username}, Final Grade: ${row.final_grade}`
        );
      });
    } else {
      console.log("No enrollments found for this course.");
    }
  } catch (err) {
    console.error("Error fetching enrollments:", err.message);
  }
}

async function listGradeComponentsForCourse(courseId) {
  try {
    const res = await client.query(
      "SELECT * FROM get_grade_components_for_course($1)",
      [courseId]
    );
    if (res.rows.length > 0) {
      console.log("\nGrade components for the course:");
      res.rows.forEach((row) => {
        console.log(
          `Grade Component ID: ${row.grade_component_id}, Name: ${row.component_name}, Max Score: ${row.max_score}`
        );
      });
    } else {
      console.log("No grade components found for this course.");
    }
  } catch (err) {
    console.error("Error fetching grade components:", err.message);
  }
}

async function listStudentGradesForEnrollment(enrollmentId) {
  try {
    const res = await client.query(
      "SELECT * FROM get_student_grades_for_enrollment($1)",
      [enrollmentId]
    );
    if (res.rows.length > 0) {
      console.log("\nGrades for the student in this course:");
      res.rows.forEach((row) => {
        console.log(
          `Grade Component: ${row.component_name}, Grade: ${row.grade}`
        );
      });
    } else {
      console.log("No grades found for this enrollment.");
    }
  } catch (err) {
    console.error("Error fetching student grades:", err.message);
  }
}

async function setGradeForEnrollment(
  enrollmentId,
  gradeComponentId,
  grade,
  teacher_username,
  change_reason
) {
  try {
    await callProcedure(
      "assign_or_update_grade",
      enrollmentId,
      gradeComponentId,
      grade,
      teacher_username,
      change_reason
    );
  } catch (err) {
    console.error("Error setting grade:", err.message);
  }
}

async function listCourses() {
  const courses = await client.query("SELECT id, name FROM courses");
  courses.rows.forEach((course) => {
    console.log(`ID: ${course.id}, Course Name: ${course.name}`);
  });
}

async function handleAdmin() {
  const action = readlineSync.question(
    "Choose an action (ls users, ls courses, create student, create teacher, create admin, delete user, create course, delete course, change course info, create grade component, assign teacher, logout): \n> "
  );

  switch (action) {
    case "ls users":
      await listUsers();
      break;
    case "ls courses":
      await listCourses();
      break;
    case "create student":
      const studentUsername = readlineSync.question(
        "Enter username for new student: "
      );
      const studentProgramme = readlineSync.question(
        "Enter programme for student: "
      );
      await callProcedure("create_student", studentUsername, studentProgramme);
      break;
    case "create teacher":
      const teacherUsername = readlineSync.question(
        "Enter username for new teacher: "
      );
      const teacherRoom = readlineSync.question("Enter room for teacher: ");
      await callProcedure("create_teacher", teacherUsername, teacherRoom);
      break;
    case "create admin":
      const adminUsername = readlineSync.question(
        "Enter username for new teacher: "
      );
      await callProcedure("create_admin", adminUsername);
      break;
    case "delete user":
      const userToDelete = readlineSync.question(
        "Enter username of user to delete: "
      );
      await callProcedure("delete_user", userToDelete);
      break;
    case "create course":
      const courseName = readlineSync.question("Enter course name: ");
      const courseDescription = readlineSync.question(
        "Enter course description: "
      );
      const ects = readlineSync.questionInt("Enter ECTS: ");
      await callProcedure("create_course", courseName, courseDescription, ects);
      break;
    case "delete course":
      const courseIdToDelete = readlineSync.questionInt(
        "Enter course ID to delete: "
      );
      await callProcedure("delete_course", courseIdToDelete);
      break;
    case "change course info":
      const courseIdToChange = readlineSync.questionInt(
        "Enter course ID to change: "
      );
      const newCourseName = readlineSync.question("Enter new course name: ");
      const newCourseDescription = readlineSync.question(
        "Enter new course description: "
      );
      const newEctsValue = readlineSync.question("Enter ECTS: ");
      await callProcedure(
        "change_course_info",
        courseIdToChange,
        newCourseName,
        newCourseDescription,
        newEctsValue
      );
      break;
    case "create grade component":
      const gradeComponentCourseId = readlineSync.questionInt(
        "Enter course ID for grade component: "
      );
      const gradeComponentName = readlineSync.question(
        "Enter grade component name: "
      );
      const maxScore = readlineSync.questionFloat("Enter max score: ");
      await callProcedure(
        "create_grade_component",
        gradeComponentCourseId,
        gradeComponentName,
        maxScore
      );
      break;
    case "assign teacher":
      const teacherUsernameToAssign = readlineSync.question(
        "Enter teacher username: "
      );
      const courseIdToAssign = readlineSync.questionInt("Enter course ID: ");
      await callProcedure(
        "assign_teacher_to_course",
        teacherUsernameToAssign,
        courseIdToAssign
      );
      break;
    case "logout":
      console.log("Goodbye!");
      return;
    default:
      console.log("Invalid choice. Try again.");
  }

  await handleAdmin();
}

async function handleTeacher(username) {
  const action = readlineSync.question(
    "Choose an action (ls courses, ls enrollments, ls grade components, ls student grades, set grade, change room, logout): \n> "
  );

  switch (action) {
    case "ls courses":
      await listCoursesForTeacher(username);
      break;
    case "ls enrollments":
      const courseIdForEnrollments = readlineSync.questionInt(
        "Enter course ID to list enrollments: "
      );
      await listEnrollmentsForCourse(courseIdForEnrollments);
      break;
    case "ls grade components":
      const courseIdForGradeComponents = readlineSync.questionInt(
        "Enter course ID to list grade components: "
      );
      await listGradeComponentsForCourse(courseIdForGradeComponents);
      break;
    case "ls student grades":
      const enrollmentIdForGrades = readlineSync.questionInt(
        "Enter enrollment ID to list student grades: "
      );
      await listStudentGradesForEnrollment(enrollmentIdForGrades);
      break;
    case "set grade":
      const enrollmentId = readlineSync.questionInt(
        "Enter enrollment ID to set grade: "
      );
      const gradeComponentId = readlineSync.questionInt(
        "Enter grade component ID: "
      );
      const change_reason = readlineSync.questionInt("Why?: ");
      const grade = readlineSync.questionFloat("Enter grade: ");
      await setGradeForEnrollment(
        enrollmentId,
        gradeComponentId,
        grade,
        username,
        change_reason
      );
      break;
    case "change room":
      const newRoom = readlineSync.question("Enter new room: ");
      await callProcedure("change_teacher_room", username, newRoom);
      break;
    case "logout":
      console.log("Goodbye!");
      return;
    default:
      console.log("Invalid choice. Try again.");
  }

  await handleTeacher(username);
}

async function handleStudent(username) {
  const action = readlineSync.question(
    "Choose an action (me, ls all courses, ls my courses, enroll, course info, grades history, logout): \n> "
  );

  switch (action) {
    case "me":
      const res = await client.query("SELECT * FROM get_student_info($1)", [
        username,
      ]);
      const row = res.rows[0];
      console.log(
        `Programme: ${row.programme}, ECTS: ${row.ects}, GPA: ${row.gpa}`
      );
    case "ls my courses":
      await listCoursesForStudent(username);
      break;
    case "ls all courses":
      await listCourses();
      break;
    case "enroll":
      const courseIdToEnroll = readlineSync.questionInt(
        "Enter course ID to enroll in: "
      );
      await callProcedure("enroll_student", username, courseIdToEnroll);
      break;
    case "course info":
      const courseIdToView = readlineSync.questionInt(
        "Enter course ID to view info: "
      );
      await listCourseInfo(courseIdToView);
      break;
    case "grades history":
      await viewGradeHistory(username);
      break;
    case "logout":
      console.log("Goodbye!");
      return;
    default:
      console.log("Invalid choice. Try again.");
  }

  await handleStudent(username);
}

async function start() {
  const username = readlineSync.question("\nEnter your username: ");
  const role = await getUserRole(username);

  if (!role) {
    console.log("User not found. Exiting..");
    return;
  }

  console.log(`\nWelcome, ${username}! Your role is: ${role}`);

  if (role === "admin") {
    await handleAdmin();
  } else if (role === "teacher") {
    await handleTeacher(username);
  } else if (role === "student") {
    await handleStudent(username);
  } else {
    console.log("Unknown role.");
  }

  await start();
}

start().finally(() => {
  client.end();
  process.on("exit", () => {
    client.end();
  });
});
