/**
 * Creates and finalises Integration_Log__c records. Centralises record-type
 * resolution, field mapping and Long Text truncation so callers stay thin.
 */
public with sharing class IntegrationLogService {

	private static final Integer MAX_LONG_TEXT = 131072;
	private static Id outboundRecordTypeId;

	public static Id getOutboundRecordTypeId() {
		if (outboundRecordTypeId == null) {
			Schema.RecordTypeInfo info = Schema.SObjectType.Integration_Log__c
				.getRecordTypeInfosByDeveloperName()
				.get(Constants.INTEGRATION_LOG_RT_OUTBOUND);
			outboundRecordTypeId = (info != null) ? info.getRecordTypeId() : null;
		}
		return outboundRecordTypeId;
	}

	public static Integration_Log__c buildOutboundLog(
		String integrationName,
		String eventType,
		Id sourceRecordId,
		String requestBody,
		String httpMethod,
		String endpoint,
		Datetime eventTimestamp
	) {
		return new Integration_Log__c(
			RecordTypeId = getOutboundRecordTypeId(),
			Integration_Name__c = integrationName,
			Event_Type__c = eventType,
			Source_Object__c = Constants.INTEGRATION_SOURCE_OBJECT_OPPORTUNITY,
			Source_Record_Id__c = sourceRecordId,
			// Typed lookup alongside the generic Id, so the log is visible from the
			// Opportunity and joinable in reports. Source_Record_Id__c remains the
			// pointer for any future source object that has no lookup of its own.
			Opportunity__c = asOpportunityId(sourceRecordId),
			Endpoint__c = endpoint,
			HTTP_Method__c = httpMethod,
			Request_Body__c = requestBody,
			Status__c = Constants.INTEGRATION_STATUS_QUEUED,
			Event_Timestamp__c = eventTimestamp
		);
	}

	public static void applyCalloutResult(Integration_Log__c log, IntegrationCalloutService.CalloutResult result) {
		log.Status__c = result.isSuccess
			? Constants.INTEGRATION_STATUS_SENT
			: Constants.INTEGRATION_STATUS_FAILED;
		log.Response_Status_Code__c = result.statusCode;
		log.Response_Body__c = truncate(result.responseBody);
		log.Response_Headers__c = truncate(result.responseHeaders);
		log.Request_Headers__c = truncate(result.requestHeaders);
		log.Error_Message__c = truncate(result.errorMessage);
		log.Sent_At__c = Datetime.now();
	}

	/**
	 * Narrows a source record Id to an Opportunity Id, or null when it points at
	 * anything else. Keeps buildOutboundLog usable for a future source object
	 * without it writing a foreign Id into the Opportunity lookup.
	 *
	 * @param sourceRecordId the record the log was raised for
	 * @return the same Id when it is an Opportunity, otherwise null
	 */
	private static Id asOpportunityId(Id sourceRecordId) {
		if (sourceRecordId == null) {
			return null;
		}
		return sourceRecordId.getSObjectType() == Opportunity.SObjectType ? sourceRecordId : null;
	}

	private static String truncate(String value) {
		if (value == null) {
			return null;
		}
		return value.length() > MAX_LONG_TEXT ? value.substring(0, MAX_LONG_TEXT) : value;
	}
}
