# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Architecture

### Apex Layer Structure

The codebase follows a layered architecture:

**Trigger Handler Framework** (`TriggerHandler.cls`)
- Base class extended by all trigger handlers
- Prevents recursive loops (max 5 iterations, configurable via `setMaxLoopCount`)
- Bypass mechanism: `TriggerHandler.bypass('HandlerName')` / `TriggerHandler.clearBypass('HandlerName')`
- Override `beforeInsert()`, `afterInsert()`, `beforeUpdate()`, etc. in subclasses

**Selector Classes (Data Access)**
- One selector per SObject: `DesignRevisionSelector`, `OpportunitySelector`, `QuoteSelector`, `ContentDocumentLinkSelector`, `ContactSelector`, `QuoteLineItemSelector`
- **All SOQL must go through selector methods — never write inline SOQL in controllers, services, handlers, or invocables.** If the right selector method doesn't exist yet, add it to the appropriate selector class first, then call it.

### Error Logging

Use `BoltErrorLogger` for all caught exceptions. Pattern:
```apex
try {
    // ...
} catch (Exception e) {
    BoltErrorLogger.log(e, 'ClassName', 'methodName');
}
```
`BoltErrorLogger` is an installed/managed package utility — do not modify it.

### Apex Test Classes
All test classes follow the `*Test.cls` naming convention. They are excluded from deployment packages via `.forceignore`.

## Salesforce Best Practices

### Bulkification
Always write code that handles collections, not single records. Triggers receive up to 200 records per execution.
- Collect IDs first, query once outside loops, process results in maps
- Never put SOQL, DML, or callouts inside `for` loops
- Use `Map<Id, SObject>` to correlate query results back to trigger records

### Governor Limits to Watch
| Limit          | Per-transaction cap |
|----------------|---------------------|
| SOQL queries   | 100                 |
| DML statements | 150                 |
| DML rows       | 10,000              |
| CPU time       | 10,000 ms           |
| Heap size      | 6 MB                |
| Callouts       | 100                 |

- Use `Limits.getQueries()` / `Limits.getLimitQueries()` etc. for diagnostic logging when debugging limit issues
- Prefer `Database.insert(records, false)` with partial success when bulk-inserting records that may partially fail

### SOQL Best Practices
- Always filter on indexed fields (`Id`, `Name`, lookup fields, fields marked as External ID) when possible
- Use `WITH SECURITY_ENFORCED` or `WITH USER_MODE` on queries that surface data to users
- Avoid `SELECT *` patterns — only query fields you need

### DML & Data Integrity
- Use `SObjectType.fields` describe or `Schema` methods when dynamically referencing fields to avoid hardcoded strings breaking on field rename
- After DML, check `Database.SaveResult` / `Database.UpsertResult` for row-level errors rather than assuming success

- Use our service-layer pattern
- Respect naming conventions
- Avoid SOQL inside loops
- Enforce bulkification
- Follow FLS/CRUD checks
- Avoid hardcoding IDs and Strings
- Respect managed package boundaries (Conga CLM)
- Avoid violating PHI/data compliance constraints
- Follow our integration patterns (Platform Events vs REST vs Queueable)
- Align with our deployment process (no metadata that breaks unlocked packages)
