#!/usr/bin/env node

const fs = require("node:fs");
const path = require("node:path");

const manifestPath = process.argv[2] || ".delta/changes.manifest.json";
const mapPath = process.argv[3] || "config/unitTestMap.json";
const projectRoot = process.cwd();
const classesDir = path.join(projectRoot, "force-app/main/default/classes");

const manifest = JSON.parse(
  fs.readFileSync(path.resolve(projectRoot, manifestPath), "utf8"),
);
const testMap = JSON.parse(
  fs.readFileSync(path.resolve(projectRoot, mapPath), "utf8"),
);
const selectedTests = new Set(testMap.alwaysRun || []);
const fallbackReasons = [];

const addedOrModified = (type) => [
  ...(manifest.add?.[type] || []),
  ...(manifest.modify?.[type] || []),
  ...(manifest.rename?.[type] || []).map((rename) => rename.to),
];
const deletedOrRenamedFrom = (type) => [
  ...(manifest.delete?.[type] || []),
  ...(manifest.rename?.[type] || []).map((rename) => rename.from),
];

for (const type of ["ApexClass", "ApexTrigger"]) {
  const destructiveComponents = deletedOrRenamedFrom(type);
  if (destructiveComponents.length > 0) {
    fallbackReasons.push(
      `${type} deletion/rename: ${destructiveComponents.join(", ")}`,
    );
  }

  for (const componentName of addedOrModified(type)) {
    if (type === "ApexClass") {
      const sourcePath = path.join(classesDir, `${componentName}.cls`);
      if (
        fs.existsSync(sourcePath) &&
        /@IsTest\b/i.test(fs.readFileSync(sourcePath, "utf8"))
      ) {
        selectedTests.add(componentName);
        continue;
      }
    }

    const componentKey = `${type}:${componentName}`;
    const mapping = testMap.components?.[componentKey];
    if (!mapping) {
      fallbackReasons.push(`missing mapping for ${componentKey}`);
      continue;
    }
    if (mapping.coveragePercent < testMap.minimumComponentCoverage) {
      fallbackReasons.push(
        `${componentKey} has only ${mapping.coveragePercent}% measured coverage`,
      );
      continue;
    }
    for (const testName of mapping.tests) {
      selectedTests.add(testName);
    }
  }
}

for (const testName of selectedTests) {
  const sourcePath = path.join(classesDir, `${testName}.cls`);
  if (
    !fs.existsSync(sourcePath) ||
    !/@IsTest\b/i.test(fs.readFileSync(sourcePath, "utf8"))
  ) {
    fallbackReasons.push(
      `mapped test class is missing or invalid: ${testName}`,
    );
  }
}

const hasApexChanges = ["ApexClass", "ApexTrigger"].some(
  (type) =>
    addedOrModified(type).length > 0 || deletedOrRenamedFrom(type).length > 0,
);

let testLevel;
let reason;
if (fallbackReasons.length > 0) {
  testLevel = "RunLocalTests";
  reason = fallbackReasons.join("; ");
} else if (hasApexChanges && selectedTests.size > 0) {
  testLevel = "RunSpecifiedTests";
  reason = `selected ${selectedTests.size} mapped test class(es)`;
} else {
  // Preserve the current production safety level for metadata-only deployments.
  testLevel = "RunLocalTests";
  reason = hasApexChanges
    ? "Apex changed but no tests were selected"
    : "metadata-only deployment";
}

const tests = [...selectedTests].sort();
console.log(`Test level: ${testLevel}`);
console.log(`Reason: ${reason}`);
if (tests.length > 0) {
  console.log(`Tests: ${tests.join(", ")}`);
}

if (process.env.GITHUB_OUTPUT) {
  fs.appendFileSync(
    process.env.GITHUB_OUTPUT,
    `test_level=${testLevel}\ntests=${tests.join(" ")}\nselection_reason=${reason}\n`,
  );
}
