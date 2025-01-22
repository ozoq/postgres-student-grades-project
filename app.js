import { client } from "./src/dbClient.js";
import {
  callProcedure,
  questionGreen,
  questionBlue,
  questionBlueFloat,
  questionBlueInt,
} from "./src/utils.js";
import {
  getUserRole,
  listUsers,
  listCoursesForTeacher,
  listCoursesForStudent,
  listCourseInfo,
  viewGradeHistory,
  listEnrollmentsForCourse,
  listGradeComponentsForCourse,
  listStudentGradesForEnrollment,
  listCourses,
} from "./src/dbHelpers.js";
import chalk from "chalk";

client.connect();

client.on("notice", (msg) => {
  console.log(chalk.gray(`PostgreSQL Notice: ${msg.message}`));
});

async function handleAdmin() {
  const action = questionGreen(
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
      const studentUsername = questionBlue("Enter username for new student: ");
      const studentProgramme = questionBlue("Enter programme for student: ");
      await callProcedure("create_student", studentUsername, studentProgramme);
      break;
    case "create teacher":
      const teacherUsername = questionBlue("Enter username for new teacher: ");
      const teacherRoom = questionBlue("Enter room for teacher: ");
      await callProcedure("create_teacher", teacherUsername, teacherRoom);
      break;
    case "create admin":
      const adminUsername = questionBlue("Enter username for new teacher: ");
      await callProcedure("create_admin", adminUsername);
      break;
    case "delete user":
      const userToDelete = questionBlue("Enter username of user to delete: ");
      await callProcedure("delete_user", userToDelete);
      break;
    case "create course":
      const courseName = questionBlue("Enter course name: ");
      const courseDescription = questionBlue("Enter course description: ");
      const ects = questionBlueInt("Enter ECTS: ");
      await callProcedure("create_course", courseName, courseDescription, ects);
      break;
    case "delete course":
      const courseIdToDelete = questionBlueInt("Enter course ID to delete: ");
      await callProcedure("delete_course", courseIdToDelete);
      break;
    case "change course info":
      const courseIdToChange = questionBlueInt("Enter course ID to change: ");
      const newCourseName = questionBlue("Enter new course name: ");
      const newCourseDescription = questionBlue(
        "Enter new course description: "
      );
      const newEctsValue = questionBlue("Enter ECTS: ");
      await callProcedure(
        "change_course_info",
        courseIdToChange,
        newCourseName,
        newCourseDescription,
        newEctsValue
      );
      break;
    case "create grade component":
      const gradeComponentCourseId = questionBlueInt(
        "Enter course ID for grade component: "
      );
      const gradeComponentName = questionBlue("Enter grade component name: ");
      const maxScore = questionBlueFloat("Enter max score: ");
      await callProcedure(
        "create_grade_component",
        gradeComponentCourseId,
        gradeComponentName,
        maxScore
      );
      break;
    case "assign teacher":
      const teacherUsernameToAssign = questionBlue("Enter teacher username: ");
      const courseIdToAssign = questionBlueInt("Enter course ID: ");
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
  const action = questionGreen(
    "Choose an action (ls courses, ls enrollments, ls grade components, ls student grades, set grade, change room, logout): \n> "
  );

  switch (action) {
    case "ls courses":
      await listCoursesForTeacher(username);
      break;
    case "ls enrollments":
      const courseIdForEnrollments = questionBlueInt(
        "Enter course ID to list enrollments: "
      );
      await listEnrollmentsForCourse(courseIdForEnrollments);
      break;
    case "ls grade components":
      const courseIdForGradeComponents = questionBlueInt(
        "Enter course ID to list grade components: "
      );
      await listGradeComponentsForCourse(courseIdForGradeComponents);
      break;
    case "ls student grades":
      const enrollmentIdForGrades = questionBlueInt(
        "Enter enrollment ID to list student grades: "
      );
      await listStudentGradesForEnrollment(enrollmentIdForGrades);
      break;
    case "set grade":
      const enrollmentId = questionBlueInt(
        "Enter enrollment ID to set grade: "
      );
      const gradeComponentId = questionBlueInt("Enter grade component ID: ");
      const change_reason = questionBlueInt("Why?: ");
      const grade = questionBlueFloat("Enter grade: ");
      await callProcedure(
        "assign_or_update_grade",
        enrollmentId,
        gradeComponentId,
        grade,
        teacher_username,
        change_reason
      );
      break;
    case "change room":
      const newRoom = questionBlue("Enter new room: ");
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
  const action = questionGreen(
    "Choose an action (me, ls all courses, ls my courses, enroll, course info, grades history, logout): \n> "
  );

  switch (action) {
    case "me":
      await displayStudentInfo(username);
      break;
    case "ls my courses":
      await listCoursesForStudent(username);
      break;
    case "ls all courses":
      await listCourses();
      break;
    case "enroll":
      const courseIdToEnroll = questionBlueInt(
        "Enter course ID to enroll in: "
      );
      await callProcedure("enroll_student", username, courseIdToEnroll);
      break;
    case "course info":
      const courseIdToView = questionBlueInt("Enter course ID to view info: ");
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
  const username = questionBlue("\nEnter your username: ");
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
