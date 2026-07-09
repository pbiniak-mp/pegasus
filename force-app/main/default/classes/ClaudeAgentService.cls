/**
 * Orchestrates the read-only AI chat agent: a tool-use loop against Anthropic's
 * Messages API, mirroring how Agentforce works but on our own Claude license.
 *
 * Flow: the user's question is sent to Claude together with a single `run_soql`
 * tool. Claude decides which SOQL to run; we execute it in the user's context
 * (see AgentQuerySelector) and feed the rows back as a tool_result. The loop
 * repeats — bounded by Constants.AGENT_MAX_ITERATIONS — until Claude returns a
 * final text answer. Read-only is structural: the only tool exposed is a SELECT
 * query, so the agent can never write data.
 *
 * The HTTP call reuses IntegrationCalloutService; the API key and version header
 * are injected by the `Anthropic_API` Named Credential, never stored in code.
 */
public with sharing class ClaudeAgentService {

	private static final String CLASS_NAME = 'ClaudeAgentService';

	/**
	 * Raised when Anthropic rejects the callout with HTTP 401 — the API key in the
	 * `Anthropic_API` Named Credential is missing, empty, expired or invalid. Kept
	 * distinct from a generic failure so the controller can surface a specific,
	 * actionable message instead of the generic error.
	 */
	public class ApiKeyNotConfiguredException extends Exception {}

	private static final String SYSTEM_PROMPT =
		'You are a helpful, read-only data assistant embedded in a Salesforce org.\n' +
		'Answer the user\'s questions about their CRM data by querying it with the run_soql tool.\n\n' +
		'RULES:\n' +
		'- You can ONLY read data. You cannot create, update or delete anything. Never claim to have changed data.\n' +
		'- To get data, call run_soql with a single SELECT SOQL query. Queries run as the logged-in user, so results already respect that user\'s permissions and sharing — do not mention access restrictions unless a query returns no rows.\n' +
		'- Always include a LIMIT of 200 or fewer. For counts, use an aggregate with an alias, e.g. SELECT COUNT(Id) total FROM Lead WHERE CreatedDate = TODAY.\n' +
		'- Ranking / superlative questions ("top 5 by Amount", "largest", "highest", "most expensive", "biggest"): return the N records with the highest POPULATED value. Build it as WHERE <field> != null ... ORDER BY <field> DESC NULLS LAST LIMIT N. CRITICAL: SOQL sorts NULLs FIRST by default even with DESC, so without the "!= null" filter and NULLS LAST you get blank-valued rows that wrongly look like the top results. Never conclude a field is unpopulated just because the first rows are blank — re-query excluding nulls before answering.\n' +
		'- Use SOQL date literals (TODAY, YESTERDAY, THIS_WEEK, THIS_MONTH, LAST_N_DAYS:30) instead of hardcoding dates.\n' +
		'- Traverse relationships with __r (e.g. Account.Name).\n' +
		'- If a query fails, read the error message and retry with a corrected query (e.g. fix a field API name). You may issue several queries before answering.\n' +
		'- When you have the data, reply in the same language as the user. Be concise. Present multiple records as a short list or simple table including the record Name and the key figures. State numbers plainly.\n' +
		'- Make every record clickable: always SELECT Id, and render each record you mention as a Markdown link whose target is the record Id, e.g. [Richie Darling - BKJ Solar](0065g00000XyZabAAB) for an Opportunity or [Q-00042](0Q05g00000AbCdeAAF) for a Quote. Do this for the name/number column in tables and for records in lists, using the exact Id from the query results. Never invent an Id.\n\n' +
		'SCHEMA HINTS (common objects — you may query others the user can access):\n' +
		'- Lead: Id, Name, FirstName, LastName, Company, Status, Email, Phone, LeadSource, Industry, IsConverted, OwnerId, CreatedDate\n' +
		'- Opportunity: Id, Name, Amount, StageName, CloseDate, IsClosed, IsWon, Probability, AccountId, Account.Name, OwnerId, CreatedDate\n' +
		'- Account: Id, Name, Industry, Type, AnnualRevenue, Phone, OwnerId, CreatedDate\n' +
		'- Contact: Id, Name, FirstName, LastName, Email, Phone, Title, AccountId, Account.Name, OwnerId, CreatedDate\n' +
		'- Quote: Id, Name, QuoteNumber, Status, GrandTotal, ExpirationDate, OpportunityId, Opportunity.Name, CreatedDate (an Opportunity has child Quotes via the Quotes relationship; to list quotes for an opportunity use WHERE OpportunityId = the opportunity Id)';

	/**
	 * Runs the agent for a single user question (with optional prior turns for
	 * follow-up context) and returns Claude's final natural-language answer.
	 */
	public static String ask(String question, List<AiChatController.ChatTurn> history) {
		List<Object> messages = new List<Object>();
		if (history != null) {
			for (AiChatController.ChatTurn turn : history) {
				if (turn == null || String.isBlank(turn.text)) {
					continue;
				}
				String role = (turn.role == 'assistant') ? 'assistant' : 'user';
				messages.add(textMessage(role, turn.text));
			}
		}
		messages.add(textMessage('user', question));

		String finalAnswer = '';
		for (Integer i = 0; i < Constants.AGENT_MAX_ITERATIONS; i++) {
			Map<String, Object> parsed = callClaude(messages);
			String stopReason = (String) parsed.get('stop_reason');
			List<Object> content = (List<Object>) parsed.get('content');

			String text = extractText(content);
			if (String.isNotBlank(text)) {
				finalAnswer = text;
			}

			if (stopReason != 'tool_use') {
				return finalAnswer;
			}

			// Echo the assistant turn back verbatim (text + tool_use blocks)...
			messages.add(new Map<String, Object>{ 'role' => 'assistant', 'content' => content });
			// ...then answer each tool_use with a tool_result.
			List<Object> toolResults = new List<Object>();
			for (Object block : content) {
				Map<String, Object> typedBlock = (Map<String, Object>) block;
				if (typedBlock.get('type') == 'tool_use') {
					toolResults.add(runTool(typedBlock));
				}
			}
			messages.add(new Map<String, Object>{ 'role' => 'user', 'content' => toolResults });
		}

		return String.isNotBlank(finalAnswer)
			? finalAnswer
			: 'I could not finish answering that within the allowed number of steps. Please try rephrasing your question.';
	}

	private static Map<String, Object> callClaude(List<Object> messages) {
		Map<String, Object> requestBody = new Map<String, Object>{
			'model' => Constants.ANTHROPIC_MODEL,
			'max_tokens' => Constants.ANTHROPIC_MAX_TOKENS,
			'system' => SYSTEM_PROMPT,
			'tools' => new List<Object>{ buildTool() },
			'messages' => messages
		};

		String endpoint = Constants.CALLOUT_PREFIX
			+ Constants.ANTHROPIC_NAMED_CREDENTIAL
			+ Constants.ANTHROPIC_MESSAGES_PATH;

		IntegrationCalloutService.CalloutResult res = IntegrationCalloutService.send(
			Constants.INTEGRATION_HTTP_METHOD_POST,
			endpoint,
			JSON.serialize(requestBody)
		);

		if (!res.isSuccess) {
			// A missing/invalid API key surfaces two different ways, both meaning
			// "configure the token" — so we raise the same actionable exception.
			if (isApiKeyConfigFailure(res)) {
				throw new ApiKeyNotConfiguredException(Constants.AGENT_API_KEY_MISSING_MESSAGE);
			}
			// Fall back to errorMessage when there is no HTTP body (the callout never
			// completed), so the log carries something useful instead of "null".
			String detail = res.responseBody != null ? res.responseBody : res.errorMessage;
			throw new CalloutException('Anthropic API error (HTTP ' + res.statusCode + '): ' + detail);
		}
		return (Map<String, Object>) JSON.deserializeUntyped(res.responseBody);
	}

	/**
	 * True when a failed callout means the Anthropic API key is not configured:
	 *  - the key is present but blank/wrong → the request reaches Anthropic and
	 *    comes back 401/403;
	 *  - the External Credential or its ApiKey parameter does not exist → Salesforce
	 *    throws BEFORE sending, so there is no HTTP status, only a credential-config
	 *    error message (e.g. "Field Anthropic_API_Credential.ApiKey does not exist").
	 */
	private static Boolean isApiKeyConfigFailure(IntegrationCalloutService.CalloutResult res) {
		if (res.statusCode == Constants.ANTHROPIC_UNAUTHORIZED_STATUS
			|| res.statusCode == Constants.ANTHROPIC_FORBIDDEN_STATUS) {
			return true;
		}
		if (res.statusCode == null) {
			String err = (res.errorMessage == null ? '' : res.errorMessage).toLowerCase();
			return err.contains('credential')
				|| err.contains('apikey')
				|| err.contains(Constants.ANTHROPIC_NAMED_CREDENTIAL.toLowerCase());
		}
		return false;
	}

	private static Object buildTool() {
		return new Map<String, Object>{
			'name' => Constants.AGENT_TOOL_NAME,
			'description' => 'Execute a single read-only SELECT SOQL query against the user\'s Salesforce org and '
				+ 'return matching records as JSON. Queries run in the logged-in user\'s context, so the results '
				+ 'already respect their object, field and record access. Only SELECT statements are permitted.',
			'input_schema' => new Map<String, Object>{
				'type' => 'object',
				'properties' => new Map<String, Object>{
					'query' => new Map<String, Object>{
						'type' => 'string',
						'description' => 'A single SELECT SOQL query. Always include a LIMIT of 200 or fewer.'
					}
				},
				'required' => new List<String>{ 'query' }
			}
		};
	}

	private static Map<String, Object> runTool(Map<String, Object> toolUse) {
		String toolUseId = (String) toolUse.get('id');
		Map<String, Object> input = (Map<String, Object>) toolUse.get('input');
		String resultContent;
		Boolean isError = false;
		try {
			String soql = input == null ? null : (String) input.get('query');
			resultContent = AgentQuerySelector.runReadOnlyQuery(soql);
		} catch (Exception e) {
			// Hand the error back to the model so it can self-correct on the next turn.
			isError = true;
			resultContent = 'Query error: ' + e.getMessage();
		}
		Map<String, Object> result = new Map<String, Object>{
			'type' => 'tool_result',
			'tool_use_id' => toolUseId,
			'content' => resultContent
		};
		if (isError) {
			result.put('is_error', true);
		}
		return result;
	}

	private static String extractText(List<Object> content) {
		if (content == null) {
			return '';
		}
		List<String> parts = new List<String>();
		for (Object block : content) {
			Map<String, Object> typedBlock = (Map<String, Object>) block;
			if (typedBlock.get('type') == 'text') {
				parts.add((String) typedBlock.get('text'));
			}
		}
		return String.join(parts, '\n').trim();
	}

	private static Map<String, Object> textMessage(String role, String text) {
		return new Map<String, Object>{
			'role' => role,
			'content' => new List<Object>{
				new Map<String, Object>{ 'type' => 'text', 'text' => text }
			}
		};
	}
}
