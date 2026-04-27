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
}
