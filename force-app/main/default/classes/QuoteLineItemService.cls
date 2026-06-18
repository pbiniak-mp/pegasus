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

	public static void applyQuoteGlobalDiscount(List<QuoteLineItem> newList) {
		if (newList == null || newList.isEmpty()) return;

		// Only consider new lines without an explicitly set discount, so a
		// manually entered per-line discount is never overwritten.
		Set<Id> quoteIds = new Set<Id>();
		Set<Id> pricebookEntryIds = new Set<Id>();
		for (QuoteLineItem qli : newList) {
			if (qli.QuoteId != null && qli.Discount == null) {
				quoteIds.add(qli.QuoteId);
				if (qli.PricebookEntryId != null) {
					pricebookEntryIds.add(qli.PricebookEntryId);
				}
			}
		}

		if (quoteIds.isEmpty()) return;

		Map<Id, Decimal> discountByQuoteId = QuoteSelector.getGlobalDiscountByQuoteIds(quoteIds);
		if (discountByQuoteId.isEmpty()) return;

		// Fixed-price products are excluded from any automatic discount.
		Set<Id> fixedPriceEntryIds = getFixedPriceEntryIds(pricebookEntryIds);

		for (QuoteLineItem qli : newList) {
			if (qli.QuoteId != null && qli.Discount == null && discountByQuoteId.containsKey(qli.QuoteId) && !fixedPriceEntryIds.contains(qli.PricebookEntryId)) {
				qli.Discount = discountByQuoteId.get(qli.QuoteId);
			}
		}
	}

	private static Set<Id> getFixedPriceEntryIds(Set<Id> pricebookEntryIds) {
		Set<Id> fixedPriceEntryIds = new Set<Id>();
		if (pricebookEntryIds.isEmpty()) return fixedPriceEntryIds;

		for (PricebookEntry pbe : PricebookEntrySelector.getEntriesByIds(pricebookEntryIds)) {
			if (pbe.Product2 != null && pbe.Product2.Family == Constants.PRODUCT_FAMILY_FIXED_PRICE) {
				fixedPriceEntryIds.add(pbe.Id);
			}
		}
		return fixedPriceEntryIds;
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
