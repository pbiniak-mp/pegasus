public inherited sharing class QuoteLineItemSelector {

	public static List<QuoteLineItem> getLineItemsByQuoteIds(Set<Id> quoteIds) {
		return [
			SELECT
				Id,
				Product2Id,
				Product2.Name,
				Product2.ProductCode,
				Product2.Description,
				Quantity,
				UnitPrice,
				TotalPrice,
				Description,
				SortOrder
			FROM QuoteLineItem
			WHERE QuoteId IN :quoteIds
			ORDER BY SortOrder ASC NULLS LAST, CreatedDate ASC
		];
	}

	public static List<QuoteLineItem> getLineItemsByQuoteId(Id quoteId) {
		return getLineItemsByQuoteIds(new Set<Id>{ quoteId });
	}

	public static List<QuoteLineItem> getLineItemsForDiscountUpdate(Set<Id> quoteIds) {
		return [
			SELECT Id, QuoteId, Discount
			FROM QuoteLineItem
			WHERE QuoteId IN :quoteIds
		];
	}

	public static List<AggregateResult> getTotalWeightByQuoteIds(Set<Id> quoteIds) {
		return [
			SELECT QuoteId quoteId, SUM(Line_Weight__c) total
			FROM QuoteLineItem
			WHERE QuoteId IN :quoteIds
			GROUP BY QuoteId
		];
	}
}