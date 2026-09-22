#!/usr/bin/env node

const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const targetOrg = process.argv[2];
const outputPath = process.argv[3] || "config/unitTestMap.json";

if (!targetOrg) {
  console.error("Usage: generate-unit-test-map.js <target-org> [output-path]");
  process.exit(1);
}

const projectRoot = process.cwd();
const classesDir = path.join(projectRoot, "force-app/main/default/classes");
const triggersDir = path.join(projectRoot, "force-app/main/default/triggers");

const classNames = new Set(
  fs
    .readdirSync(classesDir)
    .filter((name) => name.endsWith(".cls"))
    .map((name) => name.replace(/\.cls$/, "")),
);
const triggerNames = new Set(
  fs
    .readdirSync(triggersDir)
    .filter((name) => name.endsWith(".trigger"))
    .map((name) => name.replace(/\.trigger$/, "")),
);
const testClassNames = new Set(
  [...classNames].filter((name) =>
    /@IsTest\b/i.test(
      fs.readFileSync(path.join(classesDir, `${name}.cls`), "utf8"),
    ),
  ),
);

const query = [
  "SELECT ApexTestClass.Name, ApexClassOrTrigger.Name, Coverage,",
  "NumLinesCovered, NumLinesUncovered",
  "FROM ApexCodeCoverage",
  "WHERE NumLinesCovered > 0",
].join(" ");

const rawResult = execFileSync(
  "sf",
  [
    "data",
    "query",
    "--use-tooling-api",
    "--target-org",
    targetOrg,
    "--query",
    query,
    "--json",
  ],
  { encoding: "utf8", maxBuffer: 100 * 1024 * 1024 },
);
const records = JSON.parse(rawResult).result.records;
const coverageByComponent = new Map();

for (const record of records) {
  const componentName = record.ApexClassOrTrigger?.Name;
  const testName = record.ApexTestClass?.Name;
  const type = classNames.has(componentName)
    ? "ApexClass"
    : triggerNames.has(componentName)
      ? "ApexTrigger"
      : null;

  if (
    !type ||
    testClassNames.has(componentName) ||
    !testClassNames.has(testName)
  ) {
    continue;
  }

  const key = `${type}:${componentName}`;
  const component = coverageByComponent.get(key) || {
    coveredLines: new Set(),
    totalLines: new Set(),
    tests: new Map(),
  };
  const testLines = component.tests.get(testName) || new Set();
  const coveredLines = record.Coverage?.coveredLines || [];
  const uncoveredLines = record.Coverage?.uncoveredLines || [];

  for (const line of coveredLines) {
    component.coveredLines.add(line);
    component.totalLines.add(line);
    testLines.add(line);
  }
  for (const line of uncoveredLines) {
    component.totalLines.add(line);
  }

  component.tests.set(testName, testLines);
  coverageByComponent.set(key, component);
}

function chooseTests(componentKey, component) {
  const selected = [];
  const selectedLines = new Set();
  const remaining = new Map(component.tests);
  const componentName = componentKey.split(":")[1];
  const preferredNames = new Set([
    `${componentName}Test`,
    `${componentName.replace(/Trigger$/, "")}TriggerTest`,
    `${componentName.replace(/Handler$/, "")}Test`,
  ]);

  while (
    selectedLines.size < component.coveredLines.size &&
    remaining.size > 0
  ) {
    const candidates = [...remaining.entries()].map(([testName, lines]) => ({
      testName,
      lines,
      newLines: [...lines].filter((line) => !selectedLines.has(line)).length,
      preferred: preferredNames.has(testName),
    }));
    candidates.sort(
      (left, right) =>
        right.newLines - left.newLines ||
        Number(right.preferred) - Number(left.preferred) ||
        left.testName.localeCompare(right.testName),
    );

    const best = candidates[0];
    if (!best || best.newLines === 0) {
      break;
    }

    selected.push(best.testName);
    for (const line of best.lines) {
      selectedLines.add(line);
    }
    remaining.delete(best.testName);
  }

  return selected.sort();
}

const components = {};
for (const [componentKey, component] of [...coverageByComponent.entries()].sort(
  ([left], [right]) => left.localeCompare(right),
)) {
  const totalLines = component.totalLines.size;
  const coveredLines = component.coveredLines.size;
  components[componentKey] = {
    tests: chooseTests(componentKey, component),
    coveragePercent:
      totalLines === 0 ? 100 : Math.floor((coveredLines / totalLines) * 100),
    coveredLines,
    totalLines,
  };
}

const output = {
  version: 1,
  generatedFromOrg: targetOrg,
  minimumComponentCoverage: 75,
  alwaysRun: [],
  components,
};

const resolvedOutputPath = path.resolve(projectRoot, outputPath);
fs.mkdirSync(path.dirname(resolvedOutputPath), { recursive: true });
fs.writeFileSync(resolvedOutputPath, `${JSON.stringify(output, null, 2)}\n`);

console.log(
  `Wrote ${Object.keys(components).length} component mappings to ${path.relative(projectRoot, resolvedOutputPath)}`,
);
