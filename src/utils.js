import { client } from "./dbClient.js";
import readlineSync from "readline-sync";
import chalk from "chalk";

export async function callProcedure(procedure, ...params) {
  const query = `CALL ${procedure}(${params.map((p) => `'${p}'`).join(", ")});`;
  try {
    await client.query(query);
    console.log(`Procedure ${procedure} executed successfully.`);
  } catch (err) {
    console.error(`Error executing ${procedure}:`, err.message);
  }
}

export async function queryAndLog(query, params, logCallback) {
  try {
    const res = await client.query(query, params);
    if (res.rows.length > 0) {
      return logCallback(res.rows);
    } else {
      console.log("No results found.");
    }
  } catch (err) {
    console.error("Error fetching data:", err.message);
  }
}

export function questionGreen(text) {
  return readlineSync.question(chalk.green(text));
}

export function questionBlue(text) {
  return readlineSync.question(chalk.blue(text));
}

export function questionBlueInt(text) {
  return readlineSync.questionInt(chalk.blue(text));
}

export function questionBlueFloat(text) {
  return readlineSync.questionFloat(chalk.blue(text));
}
