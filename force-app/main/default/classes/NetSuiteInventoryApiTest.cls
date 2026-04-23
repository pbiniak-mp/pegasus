@IsTest
private class NetSuiteInventoryApiTest {

	private static final String ITEM_ID_1 = '6245';
	private static final String ITEM_ID_2 = '6246';
	private static final String LOC_ID_1  = 'L1';
	private static final String LOC_ID_2  = 'L2';

	private static void setRestContext(String body) {
		RestRequest req = new RestRequest();
		req.requestUri  = '/services/apexrest/netsuite/inventory';
		req.httpMethod  = 'POST';
		req.requestBody = body == null ? null : Blob.valueOf(body);
		RestContext.request  = req;
		RestContext.response = new RestResponse();
	}

	private static String buildPayload(List<Map<String, Object>> items) {
		return JSON.serialize(new Map<String, Object>{ 'items' => items });
	}

	private static String responseBody() {
		return RestContext.response.responseBody.toString();
	}

	// ── happy path ──────────────────────────────────────────────────────

	@IsTest
	static void testHandlePost_validPayload_upsertsRecord() {
		String body = buildPayload(new List<Map<String, Object>>{
			new Map<String, Object>{
				'netsuiteItemId'     => ITEM_ID_1,
				'netsuiteLocationId' => LOC_ID_1,
				'locationName'       => 'Warehouse A',
				'onHandQty'          => 100
			}
		});
		setRestContext(body);

		Test.startTest();
		NetSuiteInventoryApi.handlePost();
		Test.stopTest();

		Assert.areEqual(200, RestContext.response.statusCode);
		Assert.isTrue(responseBody().startsWith('OK: 1 upserted'), 'Response should confirm single upsert');

		List<Inventory_Location__c> records = [
			SELECT Composite_Key__c, Quantity_On_Hand__c, NetSuite_Item_ID__c, NetSuite_Location_ID__c
			FROM Inventory_Location__c
		];
		Assert.areEqual(1, records.size(), 'Should insert one record');
		Assert.areEqual(ITEM_ID_1 + '-' + LOC_ID_1, records[0].Composite_Key__c);
		Assert.areEqual(ITEM_ID_1, records[0].NetSuite_Item_ID__c);
		Assert.areEqual(LOC_ID_1, records[0].NetSuite_Location_ID__c);
		Assert.areEqual(100, records[0].Quantity_On_Hand__c);
	}

	@IsTest
	static void testHandlePost_multipleItems_upsertsAll() {
		String body = buildPayload(new List<Map<String, Object>>{
			new Map<String, Object>{ 'netsuiteItemId' => ITEM_ID_1, 'netsuiteLocationId' => LOC_ID_1, 'onHandQty' => 1 },
			new Map<String, Object>{ 'netsuiteItemId' => ITEM_ID_2, 'netsuiteLocationId' => LOC_ID_2, 'onHandQty' => 2 }
		});
		setRestContext(body);

		NetSuiteInventoryApi.handlePost();

		Assert.areEqual(200, RestContext.response.statusCode);
		Assert.areEqual(2, [SELECT COUNT() FROM Inventory_Location__c]);
		Assert.isTrue(responseBody().contains('2 upserted'));
	}

	@IsTest
	static void testHandlePost_nullOnHand_defaultsToZero() {
		String body = buildPayload(new List<Map<String, Object>>{
			new Map<String, Object>{ 'netsuiteItemId' => ITEM_ID_1, 'netsuiteLocationId' => LOC_ID_1 }
		});
		setRestContext(body);

		NetSuiteInventoryApi.handlePost();

		Inventory_Location__c rec = [SELECT Quantity_On_Hand__c FROM Inventory_Location__c LIMIT 1];
		Assert.areEqual(0, rec.Quantity_On_Hand__c, 'Missing onHandQty should default to 0');
	}

	@IsTest
	static void testHandlePost_existingRecord_updatesViaComposite() {
		insert new Inventory_Location__c(
			Composite_Key__c        = ITEM_ID_1 + '-' + LOC_ID_1,
			Quantity_On_Hand__c     = 10,
			NetSuite_Item_ID__c     = ITEM_ID_1,
			NetSuite_Location_ID__c = LOC_ID_1
		);

		String body = buildPayload(new List<Map<String, Object>>{
			new Map<String, Object>{ 'netsuiteItemId' => ITEM_ID_1, 'netsuiteLocationId' => LOC_ID_1, 'onHandQty' => 42 }
		});
		setRestContext(body);

		NetSuiteInventoryApi.handlePost();

		Assert.areEqual(200, RestContext.response.statusCode);
		List<Inventory_Location__c> records = [SELECT Quantity_On_Hand__c FROM Inventory_Location__c];
		Assert.areEqual(1, records.size(), 'Upsert by composite key should update existing record');
		Assert.areEqual(42, records[0].Quantity_On_Hand__c);
	}

	// ── skip / validation ───────────────────────────────────────────────

	@IsTest
	static void testHandlePost_itemsMissingIds_areSkipped() {
		String body = buildPayload(new List<Map<String, Object>>{
			new Map<String, Object>{ 'netsuiteItemId' => ITEM_ID_1, 'netsuiteLocationId' => LOC_ID_1, 'onHandQty' => 5 },
			new Map<String, Object>{ 'netsuiteItemId' => '',        'netsuiteLocationId' => LOC_ID_2, 'onHandQty' => 5 },
			new Map<String, Object>{ 'netsuiteItemId' => ITEM_ID_2, 'netsuiteLocationId' => null,     'onHandQty' => 5 }
		});
		setRestContext(body);

		NetSuiteInventoryApi.handlePost();

		Assert.areEqual(200, RestContext.response.statusCode);
		Assert.areEqual(1, [SELECT COUNT() FROM Inventory_Location__c], 'Only valid item should be inserted');
	}

	@IsTest
	static void testHandlePost_allItemsInvalid_returnsNoValidItems() {
		String body = buildPayload(new List<Map<String, Object>>{
			new Map<String, Object>{ 'netsuiteItemId' => '', 'netsuiteLocationId' => '', 'onHandQty' => 5 }
		});
		setRestContext(body);

		NetSuiteInventoryApi.handlePost();

		Assert.areEqual(200, RestContext.response.statusCode);
		Assert.isTrue(responseBody().contains('No valid items'), 'Should confirm no valid items');
		Assert.areEqual(0, [SELECT COUNT() FROM Inventory_Location__c]);
	}

	@IsTest
	static void testHandlePost_emptyItemsArray_returnsBadRequest() {
		setRestContext(buildPayload(new List<Map<String, Object>>()));

		NetSuiteInventoryApi.handlePost();

		Assert.areEqual(400, RestContext.response.statusCode);
		Assert.isTrue(responseBody().startsWith('ERROR:'));
	}

	@IsTest
	static void testHandlePost_missingItemsField_returnsBadRequest() {
		setRestContext('{}');

		NetSuiteInventoryApi.handlePost();

		Assert.areEqual(400, RestContext.response.statusCode);
	}

	@IsTest
	static void testHandlePost_malformedJson_returnsInternalError() {
		setRestContext('not-json');

		NetSuiteInventoryApi.handlePost();

		Assert.areEqual(500, RestContext.response.statusCode);
		Assert.isTrue(responseBody().startsWith('ERROR:'));
	}
}
