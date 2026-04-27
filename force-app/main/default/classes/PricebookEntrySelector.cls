public inherited sharing class PricebookEntrySelector {

	public static List<PricebookEntry> getEntriesByIds(Set<Id> entryIds) {
		return [
			SELECT
				Id,
				Product2Id,
				Product2.Description
			FROM PricebookEntry
			WHERE Id IN :entryIds
		];
	}

	public static PricebookEntry getEntryById(Id entryId) {
		List<PricebookEntry> entries = getEntriesByIds(new Set<Id>{ entryId });
		return entries.isEmpty() ? null : entries[0];
	}
}
