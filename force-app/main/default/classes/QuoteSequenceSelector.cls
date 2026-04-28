public inherited sharing class QuoteSequenceSelector {

	public static Quote_Sequence__c getOrgDefaultForUpdate() {
		List<Quote_Sequence__c> records = [
			SELECT Id, Last_Number__c
			FROM Quote_Sequence__c
			WHERE SetupOwnerId = :UserInfo.getOrganizationId()
			LIMIT 1
			FOR UPDATE
		];
		return records.isEmpty() ? null : records[0];
	}
}
