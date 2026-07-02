/**
 * All SOQL for Integration_Log__c. In v1 only outbound logs exist, and a log
 * awaiting delivery is uniquely identified by Status = Queued.
 */
public inherited sharing class IntegrationLogSelector {

	public static List<Integration_Log__c> getQueued(Integer maxRecords) {
		return [
			SELECT Id, Integration_Name__c, Event_Type__c, Source_Record_Id__c, Request_Body__c,
				HTTP_Method__c, Endpoint__c
			FROM Integration_Log__c
			WHERE Status__c = :Constants.INTEGRATION_STATUS_QUEUED
			ORDER BY CreatedDate ASC
			LIMIT :maxRecords
		];
	}

	public static Integer countQueued() {
		return [
			SELECT COUNT()
			FROM Integration_Log__c
			WHERE Status__c = :Constants.INTEGRATION_STATUS_QUEUED
		];
	}
}
