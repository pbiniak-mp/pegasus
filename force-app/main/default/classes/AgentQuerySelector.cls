/**
 * Security boundary for the read-only AI chat agent.
 *
 * Executes a single, model-supplied SOQL string in the running user's context.
 * `AccessLevel.USER_MODE` is the real guarantee here: it enforces the user's
 * object permissions, field-level security AND record sharing, so the agent can
 * never surface data the logged-in user is not allowed to see — the LLM does not
 * decide visibility, the org's sharing model does.
 *
 * Read-only is enforced structurally: only SELECT statements are accepted and no
 * DML tool is ever exposed to the model. Declared `with sharing` as defence in
 * depth on this dynamic-query surface (the explicit USER_MODE access level is
 * authoritative either way).
 */
public with sharing class AgentQuerySelector {

	public class AgentQueryException extends Exception {}

	/**
	 * Runs a validated, read-only SOQL query in user mode and returns the
	 * matching records serialized as JSON. Throws AgentQueryException for any
	 * non-SELECT input; lets QueryException bubble up so the caller can hand the
	 * error back to the model for self-correction.
	 */
	public static String runReadOnlyQuery(String soql) {
		String prepared = prepareQuery(soql);
		List<SObject> records = Database.query(prepared, AccessLevel.USER_MODE);
		return JSON.serialize(records);
	}

	private static String prepareQuery(String soql) {
		String trimmed = soql == null ? '' : soql.trim();
		if (trimmed.endsWith(';')) {
			trimmed = trimmed.substring(0, trimmed.length() - 1).trim();
		}
		String lowered = trimmed.toLowerCase();

		if (!lowered.startsWith('select ')) {
			throw new AgentQueryException('Only read-only SELECT queries are allowed.');
		}
		if (lowered.contains(' for update')) {
			throw new AgentQueryException('FOR UPDATE locking is not allowed in read-only mode.');
		}
		// Guarantee a bounded result set even if the model forgets a LIMIT — but
		// never on an overall aggregate query (e.g. COUNT(Id) with no GROUP BY),
		// because SOQL forbids LIMIT there and throws an uncatchable exception.
		Boolean hasLimit = Pattern.compile('(?i)\\blimit\\b').matcher(trimmed).find();
		Boolean hasAggregate = Pattern.compile('(?i)\\b(count|count_distinct|sum|avg|min|max)\\s*\\(').matcher(trimmed).find();
		Boolean hasGroupBy = Pattern.compile('(?i)\\bgroup\\s+by\\b').matcher(trimmed).find();
		Boolean isOverallAggregate = hasAggregate && !hasGroupBy;
		if (!hasLimit && !isOverallAggregate) {
			trimmed += ' LIMIT ' + Constants.AGENT_DEFAULT_QUERY_LIMIT;
		}
		return trimmed;
	}
}
