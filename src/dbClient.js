import pg from "pg";
const { Client } = pg;
import fs from "fs";
import config from "./config.js";

export const client = new Client(config);

export async function executeSqlFile(filePath) {
  console.log("Reading SQL file...");
  let sql;
  try {
    sql = fs.readFileSync(filePath, "utf8");
    console.log(`SQL file read from: ${filePath}`);
  } catch (err) {
    console.error(`Error reading SQL file: ${err.message}`);
    return;
  }

  console.log("Executing SQL query...");
  try {
    // console.log(sql);
    await client.query(sql);
    console.log(`Successfully executed: ${filePath}`);
  } catch (err) {
    console.error(`Error executing SQL from ${filePath}:`, err.message);
  }
}

export async function createDatabase() {
  const databaseName = config.database;
  try {
    const clientPg = new Client({ ...config, database: "postgres" });

    await clientPg.connect();

    const result = await clientPg.query(
      `SELECT 1 FROM pg_database WHERE datname = $1`,
      [databaseName]
    );

    if (result.rowCount === 0) {
      await clientPg.query(`CREATE DATABASE ${databaseName}`);
      console.log(`Database ${databaseName} created successfully.`);
    } else {
      console.log(`Database ${databaseName} already exists.`);
    }

    await clientPg.end();
  } catch (err) {
    console.error(`Error creating database:`, err.message);
  }
}
