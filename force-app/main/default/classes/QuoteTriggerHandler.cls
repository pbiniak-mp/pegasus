public with sharing class QuoteTriggerHandler extends TriggerHandler {

	public override void beforeInsert() {
		QuoteService.applyAccountDefaultDiscount(Trigger.new);
		QuoteService.autoActivateIfFirst(Trigger.new);
	}

	public override void afterInsert() {
		QuoteService.assignQuoteNumbers(Trigger.new);
		QuoteService.handleAfterInsert(Trigger.new);
	}

	public override void afterUpdate() {
		QuoteService.applyGlobalDiscount(
			Trigger.new,
			(Map<Id, Quote>) Trigger.oldMap
		);
		QuoteService.handleAfterUpdate(
			Trigger.new,
			(Map<Id, Quote>) Trigger.oldMap
		);
	}

	public override void afterDelete() {
		QuoteService.handleAfterDelete(Trigger.old);
	}
}
