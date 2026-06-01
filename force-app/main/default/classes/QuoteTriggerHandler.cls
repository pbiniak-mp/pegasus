public with sharing class QuoteTriggerHandler extends TriggerHandler {

	public override void beforeInsert() {
		QuoteService.applyAccountDefaultDiscount(Trigger.new);
	}

	public override void afterInsert() {
		QuoteService.assignQuoteNumbers(Trigger.new);
	}

	public override void afterUpdate() {
		QuoteService.applyGlobalDiscount(
			Trigger.new,
			(Map<Id, Quote>) Trigger.oldMap
		);
		QuoteService.syncQuoteFieldsToOpportunity(
			Trigger.new,
			(Map<Id, Quote>) Trigger.oldMap
		);
	}
}
