public with sharing class QuoteLineItemTriggerHandler extends TriggerHandler {

	private static final String CLASS_NAME = 'QuoteLineItemTriggerHandler';
	private static final String ERR_BEFORE_INSERT = 'Unhandled error during beforeInsert on QuoteLineItem';

	public override void beforeInsert() {
		try {
			QuoteLineItemService.populateLineDescriptions(Trigger.new);
		} catch (Exception e) {
			BoltErrorLogger.logError(
				CLASS_NAME,
				'beforeInsert',
				ERR_BEFORE_INSERT + ': ' + e.getMessage(),
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
