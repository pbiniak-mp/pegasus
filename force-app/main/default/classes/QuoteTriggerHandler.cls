public with sharing class QuoteTriggerHandler extends TriggerHandler {

	private static final String CLASS_NAME = 'QuoteTriggerHandler';
	private static final String ERR_AFTER_INSERT = 'Unhandled error during afterInsert on Quote';

	public override void afterInsert() {
		try {
			QuoteService.assignQuoteNumbers(Trigger.new);
		} catch (Exception e) {
			BoltErrorLogger.logError(
				CLASS_NAME,
				'afterInsert',
				ERR_AFTER_INSERT + ': ' + e.getMessage(),
				e.getStackTraceString(),
				Constants.SOURCE_TYPE_APEX,
				Constants.SEVERITY_ERROR,
				UserInfo.getUserId(),
				null
			);
			throw e;
		}
	}
}
