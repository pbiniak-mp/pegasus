# Repository instructions for coding agents

## Salesforce deployments

- Never run `sf project deploy`, validation deployments, quick deploys, or any other deployment command. The user performs deployments through the repository workflow.

## Apex test map

When adding, renaming, or deleting an Apex class, Apex trigger, or Apex test class:

1. Add or update the relevant Apex tests in the same change.
2. Check whether `config/unitTestMap.json` contains a valid mapping for every affected production class or trigger.
3. Never invent a mapping based only on class names. Mappings must come from measured `ApexCodeCoverage` data.
4. After the changed Apex has been deployed to UAT, refresh the map with:

   ```bash
   npm run test-map:refresh -- UAT-pegasus
   ```

5. Review and include the resulting `config/unitTestMap.json` change in a follow-up commit or pull request.

If the changed Apex is not yet present on UAT, or the full UAT test run does not pass, do not generate or hand-edit a guessed mapping. Keep the selector's safe `RunLocalTests` fallback and explicitly tell the user that the map refresh remains a required post-UAT step. A missing map entry is allowed temporarily because it affects validation speed, not correctness.
