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
}