import { Command } from "commander";
import { client } from "./dbClient.js";
const program = new Command();

client.connect();

program
  .command("list-students")
  .description("List all students")
  .action(async () => {
    try {
      const res = await client.query("SELECT * FROM students");
      console.log("Students:", res.rows);
    } catch (err) {
      console.error("Error fetching students:", err.message);
    }
  });

program
  .command("create-student <username> <programme>")
  .description("Create a new student")
  .action(async (username, programme) => {
    try {
      const res = await client.query(
        "SELECT id FROM users WHERE username = $1",
        [username]
      );
      const user = res.rows[0];

      if (user) {
        await client.query(
          "INSERT INTO students (user_id, programme) VALUES ($1, $2)",
          [user.id, programme]
        );
        console.log(`Student ${username} created successfully.`);
      } else {
        console.error("User not found. Please create the user first.");
      }
    } catch (err) {
      console.error("Error creating student:", err.message);
    }
  });

program
  .command("list-courses")
  .description("List all courses")
  .action(async () => {
    try {
      const res = await client.query("SELECT * FROM courses");
      console.log("Courses:", res.rows);
    } catch (err) {
      console.error("Error fetching courses:", err.message);
    }
  });

program
  .command("enroll-student <student_id> <course_id>")
  .description("Enroll a student in a course")
  .action(async (student_id, course_id) => {
    try {
      await client.query(
        "INSERT INTO enrollments (student_id, course_id) VALUES ($1, $2)",
        [student_id, course_id]
      );
      console.log(`Student ${student_id} enrolled in course ${course_id}.`);
    } catch (err) {
      console.error("Error enrolling student:", err.message);
    }
  });

program
  .command("assign-grade <enrollment_id> <grade_component_id> <grade>")
  .description("Assign a grade to a student")
  .action(async (enrollment_id, grade_component_id, grade) => {
    try {
      const res = await client.query(
        "INSERT INTO grades (enrollment_id, grade_component_id, grade) VALUES ($1, $2, $3) RETURNING id",
        [enrollment_id, grade_component_id, grade]
      );
      console.log(`Grade assigned with ID ${res.rows[0].id}`);
    } catch (err) {
      console.error("Error assigning grade:", err.message);
    }
  });

program
  .command("list-enrollments")
  .description("List all enrollments")
  .action(async () => {
    try {
      const res = await client.query("SELECT * FROM enrollments");
      console.log("Enrollments:", res.rows);
    } catch (err) {
      console.error("Error fetching enrollments:", err.message);
    }
  });

await program.parseAsync(process.argv);

client.end();

process.on("exit", () => {
  client.end();
});
