import { Command } from "commander";
import { client } from "./src/dbClient.js";
const program = new Command();

client.connect();

async function executeQuery(query, description) {
  try {
    const res = await client.query(query);
    console.log(`${description}:`, res.rows);
  } catch (err) {
    console.error(`Error fetching ${description.toLowerCase()}:`, err.message);
  }
}

program
  .command("list-users")
  .description("List all users")
  .action(() => executeQuery("SELECT * FROM users", "Users"));

program
  .command("list-students")
  .description("List all students")
  .action(() => executeQuery("SELECT * FROM students", "Students"));

program
  .command("list-teachers")
  .description("List all teachers")
  .action(() => executeQuery("SELECT * FROM teachers", "Teachers"));

program
  .command("list-courses")
  .description("List all courses")
  .action(() => executeQuery("SELECT * FROM courses", "Courses"));

program
  .command("list-enrollments")
  .description("List all enrollments")
  .action(() => executeQuery("SELECT * FROM enrollments", "Enrollments"));

program
  .command("list-grade-components")
  .description("List all grade components")
  .action(() =>
    executeQuery("SELECT * FROM grade_components", "Grade Components")
  );

program
  .command("list-grades")
  .description("List all grades")
  .action(() => executeQuery("SELECT * FROM grades", "Grades"));

program
  .command("list-grades-history")
  .description("List grades history")
  .action(() => executeQuery("SELECT * FROM grades_history", "Grades History"));

await program.parseAsync(process.argv);

process.on("exit", () => {
  client.end();
});

process.exit();
