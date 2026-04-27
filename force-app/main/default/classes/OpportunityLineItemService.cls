public with sharing class OpportunityLineItemService {

	public static void populateLineDescriptions(List<OpportunityLineItem> newList) {
		Set<Id> pbeIds = new Set<Id>();
		for (OpportunityLineItem oli : newList) {
			if (oli.PricebookEntryId != null) {
				pbeIds.add(oli.PricebookEntryId);
			}
		}

		if (pbeIds.isEmpty()) return;

		Map<Id, PricebookEntry> pbeMap = new Map<Id, PricebookEntry>(
			PricebookEntrySelector.getEntriesByIds(pbeIds)
		);

		for (OpportunityLineItem oli : newList) {
			if (oli.PricebookEntryId == null) continue;
			PricebookEntry pbe = pbeMap.get(oli.PricebookEntryId);
			if (pbe == null || pbe.Product2 == null) continue;
			String productDescription = pbe.Product2.Description;
			if (String.isNotBlank(productDescription)) {
				oli.Description = productDescription;
			}
		}
	}
}
