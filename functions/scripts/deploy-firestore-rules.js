"use strict";
/* eslint-disable require-jsdoc, valid-jsdoc */

const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");

const PROJECT_ID = "esec-bus-01";
const RULES_API = "https://firebaserules.googleapis.com/v1";

admin.initializeApp();

async function request(endpoint, options = {}) {
  const credential = admin.app().options.credential;
  const accessToken = await credential.getAccessToken();
  const response = await fetch(`${RULES_API}${endpoint}`, {
    ...options,
    headers: {
      "authorization": `Bearer ${accessToken.access_token}`,
      "content-type": "application/json",
      ...(options.headers || {}),
    },
  });
  const body = await response.json();
  if (!response.ok) {
    throw new Error(
        `Rules API ${response.status}: ${JSON.stringify(body.error || body)}`,
    );
  }
  return body;
}

async function main() {
  const rulesPath = path.resolve(__dirname, "..", "..", "firestore.rules");
  const content = fs.readFileSync(rulesPath, "utf8");
  const ruleset = await request(`/projects/${PROJECT_ID}/rulesets`, {
    method: "POST",
    body: JSON.stringify({
      source: {files: [{name: "firestore.rules", content}]},
    }),
  });
  await request(`/projects/${PROJECT_ID}/releases/cloud.firestore`, {
    method: "PATCH",
    body: JSON.stringify({
      release: {
        name: `projects/${PROJECT_ID}/releases/cloud.firestore`,
        rulesetName: ruleset.name,
      },
    }),
  });
  const release = await request(
      `/projects/${PROJECT_ID}/releases/cloud.firestore`,
  );
  if (release.rulesetName !== ruleset.name) {
    throw new Error("Rules release verification failed.");
  }
  console.log(`Deployed ${ruleset.name} to cloud.firestore.`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
