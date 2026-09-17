/**
 * Creates and finalises Integration_Log__c records. Centralises record-type
 * resolution, field mapping and Long Text truncation so callers stay thin.
 */
public with sharing class IntegrationLogService {

	private static final Integer MAX_LONG_TEXT = 131072;
	private static final Integer MAX_CORRELATION_ID = 36;
	private static Id outboundRecordTypeId;
	private static Id inboundRecordTypeId;

	public static Id getOutboundRecordTypeId() {
		if (outboundRecordTypeId == null) {
			Schema.RecordTypeInfo info = Schema.SObjectType.Integration_Log__c
				.getRecordTypeInfosByDeveloperName()
				.get(Constants.INTEGRATION_LOG_RT_OUTBOUND);
			outboundRecordTypeId = (info != null) ? info.getRecordTypeId() : null;
		}
		return outboundRecordTypeId;
	}

	public static Id getInboundRecordTypeId() {
		if (inboundRecordTypeId == null) {
			Schema.RecordTypeInfo info = Schema.SObjectType.Integration_Log__c
				.getRecordTypeInfosByDeveloperName()
				.get(Constants.INTEGRATION_LOG_RT_INBOUND);
			inboundRecordTypeId = (info != null) ? info.getRecordTypeId() : null;
		}
		return inboundRecordTypeId;
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
	 * Builds the log for one request received from an external system. The
	 * outcome is filled in afterwards with applyInboundResult.
	 *
	 * @param integrationName which integration received the request
	 * @param eventType       Event_Type__c picklist value
	 * @param sourceObject    the object the request writes to
	 * @param endpoint        the Salesforce endpoint that received the request
	 * @param httpMethod      HTTP method of the request
	 * @param requestBody     raw request body (truncated to the field limit)
	 * @param correlationId   caller-supplied id that groups related requests, may be null
	 * @return an unsaved Integration_Log__c with the Inbound record type
	 */
	public static Integration_Log__c buildInboundLog(
		String integrationName,
		String eventType,
		String sourceObject,
		String endpoint,
		String httpMethod,
		String requestBody,
		String correlationId
	) {
		return new Integration_Log__c(
			RecordTypeId = getInboundRecordTypeId(),
			Integration_Name__c = integrationName,
			Event_Type__c = eventType,
			Source_Object__c = sourceObject,
			Endpoint__c = endpoint,
			HTTP_Method__c = httpMethod,
			Request_Body__c = truncate(requestBody),
			Correlation_Id__c = String.isBlank(correlationId) ? null : correlationId.left(MAX_CORRELATION_ID),
			Event_Timestamp__c = Datetime.now()
		);
	}

	public static void applyInboundResult(
		Integration_Log__c log,
		String status,
		Integer responseStatusCode,
		String responseBody,
		String errorMessage
	) {
		log.Status__c = status;
		log.Response_Status_Code__c = responseStatusCode;
		log.Response_Body__c = truncate(responseBody);
		log.Error_Message__c = truncate(errorMessage);
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
