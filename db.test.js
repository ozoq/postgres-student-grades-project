import { client, executeSqlFile, createDatabase } from "./src/dbClient.js";
import { callProcedure } from "./src/utils.js";

async function resetDb() {
  await executeSqlFile("./sql/create-tables.sql");
  await executeSqlFile("./sql/functions.sql");
  await executeSqlFile("./sql/procedures.sql");
  await executeSqlFile("./sql/triggers.sql");
  await executeSqlFile("./sql/seed.sql");
}

beforeAll(async () => {
  await createDatabase();
  await client.connect();
});

beforeEach(async () => {
  await resetDb();
});

afterAll(async () => {
  await resetDb();
  await client.end();
});

async function query(...args) {
  return client.query(...args);
}

describe("Seed", () => {
  test("Check if user role is returned correctly", async () => {
    const queryStr = "SELECT role FROM users WHERE username = $1";
    const username = "admin";
    const result = await query(queryStr, [username]);
    expect(result.rows[0].role).toBe("admin");
  });

  test("List all users with their roles", async () => {
    const queryStr = "SELECT username, role, id FROM users";
    const result = await query(queryStr, []);
    const users = result.rows;

    expect(users.length).toBe(5);
    expect(users[0].username).toBe("admin");
    expect(users[1].role).toBe("teacher");
    expect(users[2].username).toBe("student1");
  });

  test("List all courses for a teacher", async () => {
    const queryStr =
      "SELECT c.name FROM courses c JOIN courseteachers ct ON c.id = ct.course_id JOIN teachers t ON ct.teacher_id = t.id WHERE t.user_id = (SELECT id FROM users WHERE username = $1)";
    const username = "teacher1";
    const result = await query(queryStr, [username]);

    expect(result.rows.length).toBe(4); // Teacher1 teaches 4 courses
    expect(result.rows[0].name).toBe("Course1");
    expect(result.rows[3].name).toBe("Course4");
  });

  test("List all courses for a student", async () => {
    const queryStr =
      "SELECT c.name, e.final_grade FROM courses c JOIN enrollments e ON c.id = e.course_id JOIN students s ON e.student_id = s.id WHERE s.user_id = (SELECT id FROM users WHERE username = $1)";
    const username = "student1";
    const result = await query(queryStr, [username]);

    expect(result.rows.length).toBe(2); // Student1 is enrolled in 2 courses
    expect(result.rows).toContainEqual(
      expect.objectContaining({
        name: "Course1",
        final_grade: "4.50",
      })
    );
    expect(result.rows).toContainEqual(
      expect.objectContaining({ name: "Course3", final_grade: null })
    );
  });

  test("Get course info by course ID", async () => {
    const courseId = 1;
    const queryStr =
      "SELECT name, description, ects FROM courses WHERE id = $1";
    const result = await query(queryStr, [courseId]);

    expect(result.rows[0].name).toBe("Course1");
    expect(result.rows[0].description).toBe("Description for Course1");
    expect(result.rows[0].ects).toBe(6);
  });

  test("Get grade history for a student", async () => {
    const queryStr =
      "SELECT old_grade, new_grade, change_timestamp, teacher_id, change_reason FROM grades_history gh JOIN grades g ON gh.grade_id = g.id JOIN students s ON g.enrollment_id = s.id WHERE s.user_id = (SELECT id FROM users WHERE username = $1)";
    const username = "student1";
    const result = await query(queryStr, [username]);

    expect(result.rows.length).toBe(2); // 2 grade changes
    expect(result.rows[0].old_grade).toBe("85.0");
    expect(result.rows[0].new_grade).toBe("88.0");
  });

  test("List enrollments for a course", async () => {
    const courseId = 1;
    const queryStr =
      "SELECT u.username, e.final_grade FROM enrollments e JOIN students s ON e.student_id = s.id JOIN users u ON s.user_id = u.id WHERE e.course_id = $1";
    const result = await query(queryStr, [courseId]);

    expect(result.rows.length).toBe(2); // 2 students enrolled in Course1
    expect(result.rows[0].username).toBe("student1");
    expect(result.rows[0].final_grade).toBe("4.50"); // Expected final grade
  });

  test("List grade components for a course", async () => {
    const courseId = 1;
    const queryStr =
      "SELECT name, max_score FROM grade_components WHERE course_id = $1";
    const result = await query(queryStr, [courseId]);

    expect(result.rows.length).toBe(3); // 3 grade components for Course1
    expect(result.rows[0].name).toBe("Assignment 1");
    expect(result.rows[0].max_score).toBe("100.00");
  });

  test("List student grades for a specific enrollment", async () => {
    const enrollmentId = 1;
    const queryStr =
      "SELECT gc.name, g.grade FROM grades g JOIN grade_components gc ON g.grade_component_id = gc.id WHERE g.enrollment_id = $1";
    const result = await query(queryStr, [enrollmentId]);

    expect(result.rows.length).toBe(3); // 3 grade components for student in enrollment 1
    expect(result.rows[0].name).toBe("Assignment 1");
    expect(result.rows[0].grade).toBe("85.00");
  });

  test("List all courses", async () => {
    const queryStr = "SELECT id, name FROM courses";
    const result = await query(queryStr, []);

    expect(result.rows.length).toBe(4); // 4 courses in total
    expect(result.rows[0].name).toBe("Course1");
    expect(result.rows[3].name).toBe("Course4");
  });

  test("Display student information", async () => {
    const username = "student1";
    const queryStr =
      "SELECT s.programme, c.ects FROM students s JOIN enrollments e ON s.id = e.student_id JOIN courses c ON e.course_id = c.id WHERE s.user_id = (SELECT id FROM users WHERE username = $1)";
    const result = await query(queryStr, [username]);

    expect(result.rows.length).toBe(2); // Student1 has 2 courses enrolled
    expect(result.rows[0].programme).toBe("Computer Science");
  });
});

describe("Test triggers", () => {
  test("Change grade and see if final grade changed", async () => {
    // Step 1: From seed data
    const initialResult = await query(
      "SELECT final_grade FROM enrollments WHERE id = 1"
    );
    const initialFinalGrade = initialResult.rows[0].final_grade;

    expect(initialFinalGrade).toBe("4.50"); // As per seed data if we manually calculate it

    // Step 2: Update grade
    const updateGradeQuery = `
      UPDATE grades
      SET grade = 100
      WHERE enrollment_id = 1
    `; // Set all three grades to 100
    await client.query(updateGradeQuery);

    // Step 3: Fetch the new grade
    const updatedResult = await client.query(
      "SELECT final_grade FROM enrollments WHERE id = 1"
    );
    const updatedFinalGrade = updatedResult.rows[0].final_grade;

    // Step 4: Check if the final grade was updated
    expect(updatedFinalGrade).toBe("5.00");

    // Extra checks:
    await client.query(`
    UPDATE grades
    SET grade = 20
    WHERE enrollment_id = 1
    `);
    expect(
      (await client.query("SELECT final_grade FROM enrollments WHERE id = 1"))
        .rows[0].final_grade
    ).toBe("2.00");
  });

  test("Will the grade be 2.00 if we fail the tests", async () => {
    await client.query(`
    UPDATE grades
    SET grade = 20
    WHERE enrollment_id = 1
    `);
    expect(
      (await client.query("SELECT final_grade FROM enrollments WHERE id = 1"))
        .rows[0].final_grade
    ).toBe("2.00");
  });
});

describe("Procedures", () => {
  test("Assign or update grade and check if final grade and history are updated", async () => {
    const enrollmentId = 1;
    const gradeComponentId = 1;
    const newGrade = 10;
    const teacherUsername = "teacher1";
    const changeReason = "Testsssss";

    const historyCheckQuery = `
      SELECT * FROM grades_history
      WHERE grade_id IN (
        SELECT id FROM grades WHERE enrollment_id = $1 AND grade_component_id = $2
      )
      ORDER BY change_timestamp DESC
    `;

    let historyResult = await client.query(historyCheckQuery, [
      enrollmentId,
      gradeComponentId,
    ]);

    expect(historyResult.rows).toHaveLength(1); // We have one from seeding

    await callProcedure(
      "assign_or_update_grade",
      enrollmentId,
      gradeComponentId,
      newGrade,
      teacherUsername,
      changeReason
    );

    const gradeCheckQuery = `
      SELECT grade FROM grades
      WHERE enrollment_id = $1 AND grade_component_id = $2 
    `;
    const gradeResult = await client.query(gradeCheckQuery, [
      enrollmentId,
      gradeComponentId,
    ]);

    expect(parseFloat(gradeResult.rows[0].grade)).toBe(newGrade);

    historyResult = await client.query(historyCheckQuery, [
      enrollmentId,
      gradeComponentId,
    ]);

    expect(historyResult.rows).toHaveLength(2); // We had one before in seed
    expect(historyResult.rows[0].old_grade).toBe("85.0");
    expect(parseFloat(historyResult.rows[0].new_grade)).toBe(newGrade);
  });

  test("Delete user", async () => {
    const userCheckQuery = `
    SELECT * FROM users WHERE username = $1
    `;
    const beforeUserResult = await client.query(userCheckQuery, ["student1"]);
    expect(beforeUserResult.rows).toHaveLength(1);
    await callProcedure("delete_user", "student1");
    const deletedUserResult = await client.query(userCheckQuery, ["student1"]);
    expect(deletedUserResult.rows).toHaveLength(0);
  });
});

describe("Functions", () => {
  test("Get courses for student", async () => {
    const username = "student1";
    const result = await client.query(
      "SELECT * FROM get_courses_for_student($1)",
      [username]
    );

    expect(result.rows).toHaveLength(2);
    expect(result.rows[0]).toHaveProperty("course_id");
    expect(result.rows[0]).toHaveProperty("course_name");
    expect(result.rows[0]).toHaveProperty("final_grade");
  });

  test("Get student GPA", async () => {
    const username = "student1";
    const result = await client.query("SELECT get_student_gpa($1)", [username]);

    expect(parseFloat(result.rows[0].get_student_gpa)).toBeGreaterThan(0);
  });

  test("Get student ECTS", async () => {
    const username = "student1";
    const result = await client.query("SELECT get_student_ects($1)", [
      username,
    ]);

    expect(parseFloat(result.rows[0].get_student_ects)).toBeGreaterThan(0);
  });
});
