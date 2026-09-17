@IsTest
private class IntegrationLogServiceTest {

	private static final Integer LONG_TEXT_LIMIT = 131072;
	private static final Id FAKE_OPP_ID = Id.valueOf(
		Opportunity.SObjectType.getDescribe().getKeyPrefix() + '000000000001'
	);

	@IsTest
	static void buildOutboundLogMapsAllFields() {
		Datetime ts = Datetime.newInstanceGmt(2026, 6, 25, 12, 0, 0);

		Integration_Log__c log = IntegrationLogService.buildOutboundLog(
			Constants.INTEGRATION_GLIDE_ANALYTICS,
			Constants.INTEGRATION_EVENT_OPP_CREATED,
			FAKE_OPP_ID,
			'{"salesforce_id":"x"}',
			Constants.INTEGRATION_HTTP_METHOD_POST,
			'callout:Glide_Analytics/opportunities',
			ts
		);

		Assert.areEqual(IntegrationLogService.getOutboundRecordTypeId(), log.RecordTypeId,
			'Log is created with the Outbound record type');
		Assert.areEqual(Constants.INTEGRATION_GLIDE_ANALYTICS, log.Integration_Name__c);
		Assert.areEqual(Constants.INTEGRATION_EVENT_OPP_CREATED, log.Event_Type__c);
		Assert.areEqual(Constants.INTEGRATION_SOURCE_OBJECT_OPPORTUNITY, log.Source_Object__c);
		Assert.areEqual(String.valueOf(FAKE_OPP_ID), log.Source_Record_Id__c);
		Assert.areEqual('callout:Glide_Analytics/opportunities', log.Endpoint__c);
		Assert.areEqual(Constants.INTEGRATION_HTTP_METHOD_POST, log.HTTP_Method__c);
		Assert.areEqual('{"salesforce_id":"x"}', log.Request_Body__c);
		Assert.areEqual(Constants.INTEGRATION_STATUS_QUEUED, log.Status__c, 'New logs start Queued');
		Assert.areEqual(ts, log.Event_Timestamp__c);
	}

	@IsTest
	static void applyCalloutResultOnSuccessMarksSent() {
		Integration_Log__c log = new Integration_Log__c(Status__c = Constants.INTEGRATION_STATUS_QUEUED);
		IntegrationCalloutService.CalloutResult result = new IntegrationCalloutService.CalloutResult();
		result.isSuccess = true;
		result.statusCode = 200;
		result.responseBody = '{"ok":true}';
		result.responseHeaders = '{"X-Request-Id":"req-1"}';
		result.requestHeaders = '{"Content-Type":"application/json"}';

		IntegrationLogService.applyCalloutResult(log, result);

		Assert.areEqual(Constants.INTEGRATION_STATUS_SENT, log.Status__c);
		Assert.areEqual(200, log.Response_Status_Code__c);
		Assert.areEqual('{"ok":true}', log.Response_Body__c);
		Assert.areEqual('{"X-Request-Id":"req-1"}', log.Response_Headers__c);
		Assert.areEqual('{"Content-Type":"application/json"}', log.Request_Headers__c);
		Assert.isNull(log.Error_Message__c, 'No error message on success');
		Assert.isNotNull(log.Sent_At__c, 'Sent At records the callout moment');
	}

	@IsTest
	static void applyCalloutResultOnFailureMarksFailed() {
		Integration_Log__c log = new Integration_Log__c(Status__c = Constants.INTEGRATION_STATUS_QUEUED);
		IntegrationCalloutService.CalloutResult result = new IntegrationCalloutService.CalloutResult();
		result.isSuccess = false;
		result.statusCode = 500;
		result.errorMessage = 'HTTP 500';

		IntegrationLogService.applyCalloutResult(log, result);

		Assert.areEqual(Constants.INTEGRATION_STATUS_FAILED, log.Status__c);
		Assert.areEqual(500, log.Response_Status_Code__c);
		Assert.areEqual('HTTP 500', log.Error_Message__c);
		Assert.isNotNull(log.Sent_At__c, 'Sent At is recorded even for failed attempts');
	}

	@IsTest
	static void applyCalloutResultTruncatesOversizedValues() {
		Integration_Log__c log = new Integration_Log__c();
		IntegrationCalloutService.CalloutResult result = new IntegrationCalloutService.CalloutResult();
		result.isSuccess = false;
		result.responseBody = 'x'.repeat(LONG_TEXT_LIMIT + 100);

		IntegrationLogService.applyCalloutResult(log, result);

		Assert.areEqual(LONG_TEXT_LIMIT, log.Response_Body__c.length(),
			'Values longer than the Long Text limit are truncated so the DML cannot fail');
	}

	@IsTest
	static void buildInboundLogMapsAllFields() {
		Integration_Log__c log = IntegrationLogService.buildInboundLog(
			Constants.NETSUITE_INVENTORY_INTEGRATION_NAME,
			Constants.NETSUITE_INVENTORY_EVENT_TYPE,
			Constants.NETSUITE_INVENTORY_SOURCE_OBJECT,
			Constants.NETSUITE_INVENTORY_ENDPOINT,
			Constants.INTEGRATION_HTTP_METHOD_POST,
			'{"items":[]}',
			'NSINV-20260917T120000Z'
		);

		Assert.areEqual(IntegrationLogService.getInboundRecordTypeId(), log.RecordTypeId,
			'Log is created with the Inbound record type');
		Assert.isNotNull(log.RecordTypeId);
		Assert.areEqual(Constants.NETSUITE_INVENTORY_INTEGRATION_NAME, log.Integration_Name__c);
		Assert.areEqual(Constants.NETSUITE_INVENTORY_EVENT_TYPE, log.Event_Type__c);
		Assert.areEqual(Constants.NETSUITE_INVENTORY_SOURCE_OBJECT, log.Source_Object__c);
		Assert.areEqual(Constants.NETSUITE_INVENTORY_ENDPOINT, log.Endpoint__c);
		Assert.areEqual(Constants.INTEGRATION_HTTP_METHOD_POST, log.HTTP_Method__c);
		Assert.areEqual('{"items":[]}', log.Request_Body__c);
		Assert.areEqual('NSINV-20260917T120000Z', log.Correlation_Id__c);
		Assert.isNotNull(log.Event_Timestamp__c);
	}

	@IsTest
	static void buildInboundLogTruncatesOversizedValues() {
		Integration_Log__c log = IntegrationLogService.buildInboundLog(
			Constants.NETSUITE_INVENTORY_INTEGRATION_NAME,
			Constants.NETSUITE_INVENTORY_EVENT_TYPE,
			Constants.NETSUITE_INVENTORY_SOURCE_OBJECT,
			Constants.NETSUITE_INVENTORY_ENDPOINT,
			Constants.INTEGRATION_HTTP_METHOD_POST,
			'x'.repeat(LONG_TEXT_LIMIT + 100),
			'y'.repeat(50)
		);

		Assert.areEqual(LONG_TEXT_LIMIT, log.Request_Body__c.length());
		Assert.areEqual(36, log.Correlation_Id__c.length(), 'Correlation id is cut to the field length');
	}

	@IsTest
	static void applyInboundResultSetsOutcome() {
		Integration_Log__c log = new Integration_Log__c();

		IntegrationLogService.applyInboundResult(
			log,
			Constants.INTEGRATION_STATUS_PARTIALLY_PROCESSED,
			200,
			'{"rowsSkipped":12}',
			'Skipped:\nItem 5001'
		);

		Assert.areEqual(Constants.INTEGRATION_STATUS_PARTIALLY_PROCESSED, log.Status__c);
		Assert.areEqual(200, log.Response_Status_Code__c);
		Assert.areEqual('{"rowsSkipped":12}', log.Response_Body__c);
		Assert.areEqual('Skipped:\nItem 5001', log.Error_Message__c);
	}
}
