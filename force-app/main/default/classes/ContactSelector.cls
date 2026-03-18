public inherited sharing class ContactSelector {

	public static List<Contact> getContactsByIds(Set<Id> contactIds) {
		return [
			SELECT
				Id,
				FirstName,
				LastName,
				Name
			FROM Contact
			WHERE Id IN :contactIds
		];
	}

	public static Contact getContactById(Id contactId) {
		if (contactId == null) return null;
		List<Contact> contacts = getContactsByIds(new Set<Id>{ contactId });
		return contacts.isEmpty() ? null : contacts[0];
	}
}