import { client, executeSqlFile, createDatabase } from "./dbClient.js";

process.on("exit", () => {
  client.end();
});

(async () => {
  await createDatabase();
  await client.connect();
  await executeSqlFile("./setup.sql");
  client.end();
})();
