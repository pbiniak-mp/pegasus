const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const test = require("node:test");

const projectRoot = path.resolve(__dirname, "../..");
const selectorPath = path.join(__dirname, "select-deployment-tests.js");
const emptyChanges = { add: {}, modify: {}, delete: {}, rename: {} };
const testMap = {
  version: 1,
  minimumComponentCoverage: 75,
  alwaysRun: [],
  components: {
    "ApexClass:Constants": {
      tests: ["ContentDocumentLinkSelectorTest"],
      coveragePercent: 100,
      coveredLines: 27,
      totalLines: 27,
    },
  },
};

function runSelector(changes) {
  const tempDirectory = fs.mkdtempSync(
    path.join(os.tmpdir(), "deployment-test-selector-"),
  );
  const manifestPath = path.join(tempDirectory, "changes.manifest.json");
  const mapPath = path.join(tempDirectory, "unitTestMap.json");
  const outputPath = path.join(tempDirectory, "github-output.txt");

  try {
    fs.writeFileSync(manifestPath, JSON.stringify(changes));
    fs.writeFileSync(mapPath, JSON.stringify(testMap));
    const result = spawnSync(
      process.execPath,
      [selectorPath, manifestPath, mapPath],
      {
        cwd: projectRoot,
        encoding: "utf8",
        env: { ...process.env, GITHUB_OUTPUT: outputPath },
      },
    );
    assert.equal(result.status, 0, result.stderr || result.stdout);

    return Object.fromEntries(
      fs
        .readFileSync(outputPath, "utf8")
        .trim()
        .split("\n")
        .map((line) => {
          const separator = line.indexOf("=");
          return [line.slice(0, separator), line.slice(separator + 1)];
        }),
    );
  } finally {
    fs.rmSync(tempDirectory, { recursive: true, force: true });
  }
}

test("selects mapped tests for a covered production class", () => {
  const output = runSelector({
    ...emptyChanges,
    modify: { ApexClass: ["Constants"] },
  });

  assert.equal(output.test_level, "RunSpecifiedTests");
  assert.equal(output.tests, "ContentDocumentLinkSelectorTest");
});

test("runs a changed test class directly", () => {
  const output = runSelector({
    ...emptyChanges,
    modify: { ApexClass: ["ContentDocumentLinkSelectorTest"] },
  });

  assert.equal(output.test_level, "RunSpecifiedTests");
  assert.equal(output.tests, "ContentDocumentLinkSelectorTest");
});

test("falls back when a production class has no mapping", () => {
  const output = runSelector({
    ...emptyChanges,
    modify: { ApexClass: ["RestResponseUtils"] },
  });

  assert.equal(output.test_level, "RunLocalTests");
  assert.match(output.selection_reason, /missing mapping/);
});

test("preserves RunLocalTests for metadata-only changes", () => {
  const output = runSelector({
    ...emptyChanges,
    modify: { PermissionSet: ["Pegasus_Manager"] },
  });

  assert.equal(output.test_level, "RunLocalTests");
  assert.equal(output.selection_reason, "metadata-only deployment");
});
