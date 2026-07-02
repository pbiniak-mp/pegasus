# AI Chat POC — read-only Salesforce agent on Claude

A minimal, Agentforce-style assistant that answers questions about your CRM data
("How many leads came in today?", "Which open opportunity has the largest
amount?") by letting Claude generate SOQL, which we run **in the logged-in
user's context**. It is **read-only** and respects each user's sharing and
permissions automatically.

## How it works

```
aiChat (LWC, Home page)
   │  ask(question, history)
   ▼
AiChatController  ── with sharing ──►  ClaudeAgentService
                                          │  tool-use loop (max 5 iterations)
                                          ▼
                       Anthropic Messages API  (callout: Anthropic_API)
                                          │  tool_use: run_soql("SELECT ...")
                                          ▼
                       AgentQuerySelector.runReadOnlyQuery
                          Database.query(soql, AccessLevel.USER_MODE)
                          → results returned to Claude as tool_result
                          → loop until Claude returns a final text answer
```

**Why this is safe**
- Every query runs with `AccessLevel.USER_MODE`, so Salesforce enforces the
  user's object/field/record access. The model never decides who sees what.
- The only tool exposed is a SELECT query (`run_soql`); there is no write path.
- The Anthropic API key lives in a Named Credential, never in code or git.

## Components in this repo

| Type | Name |
| --- | --- |
| Apex | `AgentQuerySelector`, `ClaudeAgentService`, `AiChatController` |
| Apex (reused) | `IntegrationCalloutService`, `Constants`, `BoltErrorLogger` |
| LWC | `aiChat` (exposed to Home, App, and Record pages) |
| Permission Set | `AI Chat Agent User` |

## Setup (one-time)

### 1. Get an Anthropic API key
Create a key at <https://console.anthropic.com> (Settings → API Keys). It starts
with `sk-ant-`. This is **API billing**, separate from a Claude Code subscription.

### 2. Deploy the metadata
Deploy the Apex classes, the `aiChat` LWC, and the permission set the usual way.
(The Named Credential is created by clicks below — secrets must not live in
metadata/git.)

### 3. Create the External Credential (stores the key, encrypted)
Setup → **Named Credentials** → **External Credentials** tab → **New**
- Label: `Anthropic API`  •  Name: `Anthropic_API`
- Authentication Protocol: **Custom** → Save
- In **Principals** → **New**:
  - Parameter Name: `AnthropicPrincipal`  •  Sequence: `1`  •  Identity Type: **Named Principal**
  - **Authentication Parameters** → Add one: Name `ApiKey`, Value = *your* `sk-ant-...` key
  - Save

### 4. Create the Named Credential (the secure callout endpoint)
Setup → **Named Credentials** → **Named Credentials** tab → **New**
- Label: `Anthropic API`  •  Name: `Anthropic_API`
- URL: `https://api.anthropic.com`
- External Credential: **Anthropic API**
- **Uncheck** "Generate Authorization Header"
- **Check** "Allow Formulas in HTTP Header"
- Save, then in the NC's **Custom Headers** add:
  | Name | Value |
  | --- | --- |
  | `x-api-key` | `{!$Credential.Anthropic_API.ApiKey}` |
  | `anthropic-version` | `2023-06-01` |

### 5. Authorize the principal
On the **External Credential** → **Permission Set Mappings** → add a mapping
between the `AI Chat Agent User` permission set and the `AnthropicPrincipal`
principal. (Without this, callouts return an authorization error.)

### 6. Assign the permission set
Assign **AI Chat Agent User** to yourself / the demo users.

### 7. Drop the component on Home
Setup → **Lightning App Builder** → edit your **Home** page → drag the **AI Chat**
custom component onto the page → Save → Activate.

## Try it
- "How many leads were created today?"
- "List the 5 opportunities with the largest amount that are still open."
- "Which accounts in the Technology industry have open opportunities?"

## Known limits (POC)
- **Synchronous**: each agent step is a sequential callout (Apex 120 s cap). Fine
  for single questions; productionizing means async + streaming.
- **Schema hints** for Lead/Opportunity/Account/Contact are baked into the system
  prompt in `ClaudeAgentService`; the agent self-corrects on field-name errors but
  add more objects there for best results.
- Answers render as plain text with preserved formatting (safe, no HTML injection).

## Natural next steps
- Log conversations to a custom object for auditing.
- Stream responses / move to async for snappier UX.
- Allow-list objects, or give the agent a `describe` tool instead of static hints.
- Swap the model in `Constants.ANTHROPIC_MODEL` (e.g. to `claude-opus-4-8`) for
  harder reasoning.
