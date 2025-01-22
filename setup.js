import { client, executeSqlFile, createDatabase } from "./dbClient.js";

process.on("exit", () => {
  client.end();
});

(async () => {
  await createDatabase();
  await client.connect();
  await executeSqlFile("./sql/create-table.sql");
  await executeSqlFile("./sql/functions.sql");
  await executeSqlFile("./sql/procedures.sql");
  await executeSqlFile("./sql/triggers.sql");
  await executeSqlFile("./sql/seed.sql");
  client.end();
})();
