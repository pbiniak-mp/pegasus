/**
 * LWC entry point for the read-only AI chat agent. Delegates to
 * ClaudeAgentService and never leaks raw exceptions to the UI — failures are
 * logged via BoltErrorLogger and returned as a friendly message. `with sharing`
 * so the running user's context flows through to every query the agent runs.
 */
public with sharing class AiChatController {

	private static final String CLASS_NAME = 'AiChatController';

	@AuraEnabled
	public static AiChatResult ask(String question, String history) {
		// Gate on the custom permission so a user without the AI_Chat_Agent_User
		// permission set gets a clear message rather than a raw access error. The
		// LWC hides the UI too, but this guards direct Apex calls.
		if (!FeatureManagement.checkPermission(Constants.AGENT_ACCESS_CUSTOM_PERMISSION)) {
			return new AiChatResult(null, true, Constants.AGENT_NO_ACCESS_MESSAGE);
		}
		if (String.isBlank(question)) {
			return new AiChatResult(null, true, 'Please enter a question.');
		}
		try {
			// History arrives as a JSON string: a List<ChatTurn> param passed
			// straight from LWC deserializes to an empty list, so we parse it here.
			List<ChatTurn> priorTurns = String.isBlank(history)
				? new List<ChatTurn>()
				: (List<ChatTurn>) JSON.deserialize(history, List<ChatTurn>.class);
			String answer = ClaudeAgentService.ask(question, priorTurns);
			return new AiChatResult(answer, false, null);
		} catch (ClaudeAgentService.ApiKeyNotConfiguredException e) {
			// Not a code failure — the org just has no valid API key yet. Tell the
			// user how to fix it; no BoltErrorLogger entry is warranted.
			return new AiChatResult(null, true, e.getMessage());
		} catch (Exception e) {
			BoltErrorLogger.logError(
				CLASS_NAME,
				'ask',
				Constants.AGENT_ERROR_CATEGORY + ': ' + e.getMessage(),
				e.getStackTraceString(),
				Constants.SOURCE_TYPE_APEX,
				Constants.SEVERITY_ERROR,
				UserInfo.getUserId(),
				null
			);
			return new AiChatResult(null, true, 'Sorry, something went wrong while answering. Please try again.');
		}
	}

	/** A prior turn of the conversation, sent from the LWC for follow-up context. */
	public class ChatTurn {
		@AuraEnabled
		public String role; // 'user' | 'assistant'
		@AuraEnabled
		public String text;
	}

	public class AiChatResult {
		@AuraEnabled
		public String answer;
		@AuraEnabled
		public Boolean isError;
		@AuraEnabled
		public String errorMessage;

		public AiChatResult(String answer, Boolean isError, String errorMessage) {
			this.answer = answer;
			this.isError = isError;
			this.errorMessage = errorMessage;
		}
	}
}
