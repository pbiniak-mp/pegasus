public inherited sharing class ContentDocumentLinkSelector {
	public static List<ContentDocumentLink> getByLinkedEntityIds(Set<Id> linkedEntityIds) {
		return [
			SELECT Id,
				ContentDocumentId,
				LinkedEntityId,
				ShareType,
				Visibility
			FROM ContentDocumentLink
			WHERE LinkedEntityId IN :linkedEntityIds
		];
	}

	public static ContentDocumentLink getByLinkedEntityId(Id id) {
		List<ContentDocumentLink> records = getByLinkedEntityIds(new Set<Id>{ id });
		return records.isEmpty() ? null : records[0];
	}
}
