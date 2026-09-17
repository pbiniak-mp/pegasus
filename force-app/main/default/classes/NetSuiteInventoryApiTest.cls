@IsTest
private class NetSuiteInventoryApiTest {

	private static final String ITEM_ID = 'TNS-API-ITEM-1';
	private static final String ITEM_NAME = 'TEST-API-SKU';
	private static final String LOC_ID = 'TNS-API-LOC-1';
	private static final String RUN_ID = 'NSINV-20260917T120000Z';

	@TestSetup
	static void setup() {
		insert new Product2(Name = 'Api Test Product', External_Id__c = ITEM_ID);
		insert new Warehouse_Location__c(Name = 'Api Test Location', NetSuite_ID__c = LOC_ID, Type__c = 'Offline');
	}

	private static void setRestContext(String body) {
		RestRequest req = new RestRequest();
		req.requestUri = Constants.NETSUITE_INVENTORY_ENDPOINT;
		req.httpMethod = 'POST';
		req.requestBody = body == null ? null : Blob.valueOf(body);
		RestContext.request = req;
		RestContext.response = new RestResponse();
	}

	private static Map<String, Object> itemRow(String itemId, String itemName, Decimal onHand, Decimal committed) {
		return new Map<String, Object>{
			'netsuiteItemId' => itemId,
			'netsuiteItemName' => itemName,
			'netsuiteLocationId' => LOC_ID,
			'locationName' => 'Api Test Location',
			'onHandQty' => onHand,
			'committedQty' => committed
		};
	}

	private static String payload(List<Map<String, Object>> items) {
		return JSON.serialize(new Map<String, Object>{
			'runId' => RUN_ID,
			'generatedAt' => '2026-09-17T12:00:00.000Z',
			'batchNumber' => 1,
			'batchCount' => 1,
			'items' => items
		});
	}

	private static Map<String, Object> responseJson() {
		return (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());
	}

	private static Integration_Log__c onlyLog() {
		List<Integration_Log__c> logs = [
			SELECT RecordTypeId, Integration_Name__c, Event_Type__c, Source_Object__c, Endpoint__c,
				HTTP_Method__c, Request_Body__c, Correlation_Id__c, Status__c, Response_Status_Code__c,
				Response_Body__c, Error_Message__c, Event_Timestamp__c
			FROM Integration_Log__c
		];
		Assert.areEqual(1, logs.size(), 'Exactly one log per request');
		return logs[0];
	}

	@IsTest
	static void validPayloadReturnsProcessedSummaryAndLogsRequest() {
		String body = payload(new List<Map<String, Object>>{ itemRow(ITEM_ID, ITEM_NAME, 12, 2) });
		setRestContext(body);

		Test.startTest();
		NetSuiteInventoryApi.handlePost();
		Test.stopTest();

		Map<String, Object> response = responseJson();
		Assert.areEqual(200, RestContext.response.statusCode);
		Assert.areEqual(Constants.HTTP_CONTENT_TYPE_JSON, RestContext.response.headers.get(Constants.HTTP_HEADER_CONTENT_TYPE));
		Assert.areEqual(Constants.INTEGRATION_STATUS_PROCESSED, response.get('status'));
		Assert.areEqual(1, response.get('rowsUpserted'));
		Assert.areEqual(RUN_ID, response.get('runId'));

		Integration_Log__c log = onlyLog();
		Assert.areEqual(String.valueOf(log.Id), String.valueOf(response.get('logId')));
		Assert.areEqual(IntegrationLogService.getInboundRecordTypeId(), log.RecordTypeId);
		Assert.areEqual(Constants.NETSUITE_INVENTORY_INTEGRATION_NAME, log.Integration_Name__c);
		Assert.areEqual(Constants.NETSUITE_INVENTORY_EVENT_TYPE, log.Event_Type__c);
		Assert.areEqual(Constants.NETSUITE_INVENTORY_SOURCE_OBJECT, log.Source_Object__c);
		Assert.areEqual(Constants.NETSUITE_INVENTORY_ENDPOINT, log.Endpoint__c);
		Assert.areEqual('POST', log.HTTP_Method__c);
		Assert.areEqual(RUN_ID, log.Correlation_Id__c);
		Assert.areEqual(body, log.Request_Body__c);
		Assert.areEqual(Constants.INTEGRATION_STATUS_PROCESSED, log.Status__c);
		Assert.areEqual(200, log.Response_Status_Code__c);
		Assert.isTrue(log.Response_Body__c.contains('"rowsUpserted":1'));
		Assert.isNull(log.Error_Message__c, 'Nothing to report for a fully applied batch');
		Assert.isNotNull(log.Event_Timestamp__c);

		Product2 p = [SELECT On_Hand__c, Committed__c FROM Product2 WHERE External_Id__c = :ITEM_ID];
		Assert.areEqual(12, p.On_Hand__c);
		Assert.areEqual(2, p.Committed__c);
	}

	@IsTest
	static void unresolvedItemIsReportedInResponseAndLog() {
		setRestContext(payload(new List<Map<String, Object>>{
			itemRow(ITEM_ID, ITEM_NAME, 12, 2),
			itemRow('TNS-API-UNKNOWN', 'TEST-API-UNKNOWN', 5, 0)
		}));

		Test.startTest();
		NetSuiteInventoryApi.handlePost();
		Test.stopTest();

		Map<String, Object> response = responseJson();
		Assert.areEqual(200, RestContext.response.statusCode, 'Unresolved rows do not fail the request');
		Assert.areEqual(Constants.INTEGRATION_STATUS_PARTIALLY_PROCESSED, response.get('status'));
		Assert.areEqual(1, response.get('rowsSkipped'));

		Integration_Log__c log = onlyLog();
		Assert.areEqual(Constants.INTEGRATION_STATUS_PARTIALLY_PROCESSED, log.Status__c);
		Assert.isTrue(log.Error_Message__c.startsWith('Skipped:'));
		Assert.isTrue(log.Error_Message__c.contains('TNS-API-UNKNOWN'));
		Assert.isTrue(log.Error_Message__c.contains('TEST-API-UNKNOWN'));
	}

	@IsTest
	static void emptyBodyReturnsBadRequestAndLogsFailure() {
		setRestContext(null);

		NetSuiteInventoryApi.handlePost();

		Assert.areEqual(400, RestContext.response.statusCode);
		Assert.areEqual(Constants.INTEGRATION_STATUS_FAILED, responseJson().get('status'));
		Integration_Log__c log = onlyLog();
		Assert.areEqual(Constants.INTEGRATION_STATUS_FAILED, log.Status__c);
		Assert.areEqual(400, log.Response_Status_Code__c);
		Assert.areEqual(Constants.NETSUITE_INVENTORY_MSG_EMPTY_BODY, log.Error_Message__c);
	}

	@IsTest
	static void malformedJsonReturnsBadRequest() {
		setRestContext('not-json');

		NetSuiteInventoryApi.handlePost();

		Assert.areEqual(400, RestContext.response.statusCode);
		Integration_Log__c log = onlyLog();
		Assert.areEqual(Constants.INTEGRATION_STATUS_FAILED, log.Status__c);
		Assert.isTrue(log.Error_Message__c.startsWith(Constants.NETSUITE_INVENTORY_MSG_MALFORMED_JSON));
		Assert.areEqual('not-json', log.Request_Body__c);
	}

	@IsTest
	static void missingOrEmptyItemsReturnsBadRequest() {
		setRestContext('{"runId":"' + RUN_ID + '","items":[]}');

		NetSuiteInventoryApi.handlePost();

		Assert.areEqual(400, RestContext.response.statusCode);
		Map<String, Object> response = responseJson();
		Assert.areEqual(Constants.NETSUITE_INVENTORY_MSG_EMPTY_PAYLOAD, response.get('message'));
		Integration_Log__c log = onlyLog();
		Assert.areEqual(RUN_ID, log.Correlation_Id__c, 'The run id is kept even for rejected batches');
		Assert.areEqual(Constants.INTEGRATION_STATUS_FAILED, log.Status__c);
	}

	@IsTest
	static void unexpectedFailureRollsBackBatchAndReturns500() {
		setRestContext(payload(new List<Map<String, Object>>{ itemRow(ITEM_ID, ITEM_NAME, 12, 2) }));
		NetSuiteInventorySyncService.simulateFailureAfterUpsert = true;

		Test.startTest();
		NetSuiteInventoryApi.handlePost();
		Test.stopTest();

		Assert.areEqual(500, RestContext.response.statusCode);
		Assert.areEqual(0, [SELECT COUNT() FROM Inventory_Location__c], 'The partial upsert is rolled back');
		Assert.isNull([SELECT On_Hand__c FROM Product2 WHERE External_Id__c = :ITEM_ID].On_Hand__c);
		Integration_Log__c log = onlyLog();
		Assert.areEqual(Constants.INTEGRATION_STATUS_FAILED, log.Status__c);
		Assert.areEqual(500, log.Response_Status_Code__c);
		Assert.isTrue(log.Error_Message__c.contains('Simulated failure after upsert'));
	}
}
