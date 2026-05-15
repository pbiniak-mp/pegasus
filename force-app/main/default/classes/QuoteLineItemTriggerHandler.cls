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

	public override void afterInsert() {
		QuoteLineItemService.recalculateQuoteTotalWeight(collectQuoteIds(Trigger.new));
	}

	public override void afterUpdate() {
		Set<Id> quoteIds = collectQuoteIds(Trigger.new);
		quoteIds.addAll(collectQuoteIds(Trigger.old));
		QuoteLineItemService.recalculateQuoteTotalWeight(quoteIds);
	}

	public override void afterDelete() {
		QuoteLineItemService.recalculateQuoteTotalWeight(
			collectQuoteIds(Trigger.old)
		);
	}

	public override void afterUndelete() {
		QuoteLineItemService.recalculateQuoteTotalWeight(collectQuoteIds(Trigger.new));
	}

	private static Set<Id> collectQuoteIds(List<QuoteLineItem> records) {
		Set<Id> quoteIds = new Set<Id>();
		if (records == null) return quoteIds;
		for (QuoteLineItem qli : records) {
			if (qli.QuoteId != null) {
				quoteIds.add(qli.QuoteId);
			}
		}
		return quoteIds;
	}
}
