import { client, executeSqlFile } from "./dbClient.js";

process.on("exit", () => {
  client.end();
});

(async () => {
  await client.connect();
  await executeSqlFile("./seed.sql");
  client.end();
})();
