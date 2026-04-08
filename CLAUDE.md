# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Important

**Never run `sf project deploy` or any deploy command.** The user deploys manually.

## Architecture

This is a **Salesforce DX project** (`force-app/main/default/`) using API version 65.0.

### Apex Layer

Follows a layered pattern:

- **Selectors** (`*Selector.cls`) — all SOQL queries; `inherited sharing`
- **Service** (`*Service.cls`) — business logic; called from trigger handlers and controllers
- **Trigger Handlers** (`*TriggerHandler.cls`) — extend `TriggerHandler` base class (managed package); delegate to service
- **Controllers** (`*Controller.cls`) — `@AuraEnabled` methods for LWC; `with sharing`
- **Invocables** (`*Invocable.cls`) — Flow-callable wrappers around service methods

Error handling uses `BoltErrorLogger.logError(...)` (managed package) throughout. `TriggerHandler.bypass(handlerName)` / `clearBypass(handlerName)` is used in the service to prevent recursive trigger execution during bulk updates.

Constants are centralized in `Constants.cls`.