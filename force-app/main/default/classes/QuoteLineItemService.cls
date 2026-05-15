public with sharing class QuoteLineItemService {

	public static void populateLineDescriptions(List<QuoteLineItem> newList) {
		Set<Id> pbeIds = new Set<Id>();
		for (QuoteLineItem qli : newList) {
			if (qli.PricebookEntryId != null) {
				pbeIds.add(qli.PricebookEntryId);
			}
		}

		if (pbeIds.isEmpty()) return;

		Map<Id, PricebookEntry> pbeMap = new Map<Id, PricebookEntry>(
			PricebookEntrySelector.getEntriesByIds(pbeIds)
		);

		for (QuoteLineItem qli : newList) {
			if (qli.PricebookEntryId == null) continue;
			PricebookEntry pbe = pbeMap.get(qli.PricebookEntryId);
			if (pbe == null || pbe.Product2 == null) continue;
			String productDescription = pbe.Product2.Description;
			if (String.isNotBlank(productDescription)) {
				qli.Description = productDescription;
			}
		}
	}

	public static void recalculateQuoteTotalWeight(Set<Id> quoteIds) {
		if (quoteIds == null) return;
		quoteIds.remove(null);
		if (quoteIds.isEmpty()) return;

		Map<Id, Decimal> weightByQuoteId = new Map<Id, Decimal>();
		for (Id quoteId : quoteIds) {
			weightByQuoteId.put(quoteId, 0);
		}

		for (AggregateResult ar : QuoteLineItemSelector.getTotalWeightByQuoteIds(quoteIds)) {
			Id quoteId = (Id) ar.get('quoteId');
			Decimal total = (Decimal) ar.get('total');
			weightByQuoteId.put(quoteId, total != null ? total : 0);
		}

		List<Quote> toUpdate = new List<Quote>();
		for (Id quoteId : weightByQuoteId.keySet()) {
			toUpdate.add(new Quote(
				Id = quoteId,
				Total_Weight__c = weightByQuoteId.get(quoteId)
			));
		}

		TriggerHandler.bypass(Constants.QUOTE_HANDLER_NAME);
		try {
			update toUpdate;
		} finally {
			TriggerHandler.clearBypass(Constants.QUOTE_HANDLER_NAME);
		}
	}
}
