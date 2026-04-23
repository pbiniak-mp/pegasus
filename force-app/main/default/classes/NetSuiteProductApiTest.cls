@IsTest
private class NetSuiteProductApiTest {

	private static final String EXT_ID_1       = '6245';
	private static final String EXT_ID_2       = '6246';
	private static final String EXT_ID_MISSING = '9999';

	@TestSetup
	static void setup() {
		insert new List<Product2>{
			new Product2(Name = 'Product A', External_Id__c = EXT_ID_1, Committed__c = 0, IsActive = true),
			new Product2(Name = 'Product B', External_Id__c = EXT_ID_2, Committed__c = 0, IsActive = true)
		};
	}

	private static void setRestContext(String body) {
		RestRequest req = new RestRequest();
		req.requestUri  = '/services/apexrest/netsuite/product';
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
	static void testHandlePost_existingProduct_updatesCommitted() {
		String body = buildPayload(new List<Map<String, Object>>{
			new Map<String, Object>{ 'netsuiteItemId' => EXT_ID_1, 'committedQty' => 5 }
		});
		setRestContext(body);

		Test.startTest();
		NetSuiteProductApi.handlePost();
		Test.stopTest();

		Assert.areEqual(200, RestContext.response.statusCode);
		Assert.isTrue(responseBody().contains('1 updated'));

		Product2 updated = [SELECT Committed__c FROM Product2 WHERE External_Id__c = :EXT_ID_1];
		Assert.areEqual(5, updated.Committed__c);
	}

	@IsTest
	static void testHandlePost_multipleProducts_updatesAll() {
		String body = buildPayload(new List<Map<String, Object>>{
			new Map<String, Object>{ 'netsuiteItemId' => EXT_ID_1, 'committedQty' => 10 },
			new Map<String, Object>{ 'netsuiteItemId' => EXT_ID_2, 'committedQty' => 20 }
		});
		setRestContext(body);

		NetSuiteProductApi.handlePost();

		Assert.areEqual(200, RestContext.response.statusCode);
		Assert.isTrue(responseBody().contains('2 updated'));

		Map<String, Product2> byExt = new Map<String, Product2>();
		for (Product2 p : [SELECT External_Id__c, Committed__c FROM Product2]) {
			byExt.put(p.External_Id__c, p);
		}
		Assert.areEqual(10, byExt.get(EXT_ID_1).Committed__c);
		Assert.areEqual(20, byExt.get(EXT_ID_2).Committed__c);
	}

	@IsTest
	static void testHandlePost_duplicateExternalIds_lastWins() {
		String body = buildPayload(new List<Map<String, Object>>{
			new Map<String, Object>{ 'netsuiteItemId' => EXT_ID_1, 'committedQty' => 1 },
			new Map<String, Object>{ 'netsuiteItemId' => EXT_ID_1, 'committedQty' => 99 }
		});
		setRestContext(body);

		NetSuiteProductApi.handlePost();

		Product2 updated = [SELECT Committed__c FROM Product2 WHERE External_Id__c = :EXT_ID_1];
		Assert.areEqual(99, updated.Committed__c, 'Later item in payload should win via map dedup');
	}

	// ── missing / invalid ───────────────────────────────────────────────

	@IsTest
	static void testHandlePost_missingProduct_reportsMissing() {
		String body = buildPayload(new List<Map<String, Object>>{
			new Map<String, Object>{ 'netsuiteItemId' => EXT_ID_MISSING, 'committedQty' => 5 }
		});
		setRestContext(body);

		NetSuiteProductApi.handlePost();

		Assert.areEqual(200, RestContext.response.statusCode);
		String resp = responseBody();
		Assert.isTrue(resp.contains('0 updated'), 'Should report no updates');
		Assert.isTrue(resp.contains('1 missing'), 'Should report missing external id');
		Assert.isTrue(resp.contains(EXT_ID_MISSING), 'Missing id should be listed');
	}

	@IsTest
	static void testHandlePost_mixedExistingAndMissing_reportsBoth() {
		String body = buildPayload(new List<Map<String, Object>>{
			new Map<String, Object>{ 'netsuiteItemId' => EXT_ID_1,       'committedQty' => 7 },
			new Map<String, Object>{ 'netsuiteItemId' => EXT_ID_MISSING, 'committedQty' => 3 }
		});
		setRestContext(body);

		NetSuiteProductApi.handlePost();

		Assert.areEqual(200, RestContext.response.statusCode);
		String resp = responseBody();
		Assert.isTrue(resp.contains('1 updated'));
		Assert.isTrue(resp.contains('1 missing'));

		Product2 updated = [SELECT Committed__c FROM Product2 WHERE External_Id__c = :EXT_ID_1];
		Assert.areEqual(7, updated.Committed__c);
	}

	@IsTest
	static void testHandlePost_itemsMissingFields_areSkipped() {
		String body = buildPayload(new List<Map<String, Object>>{
			new Map<String, Object>{ 'netsuiteItemId' => EXT_ID_1, 'committedQty' => 5 },
			new Map<String, Object>{ 'netsuiteItemId' => '',        'committedQty' => 5 },
			new Map<String, Object>{ 'netsuiteItemId' => EXT_ID_2 }
		});
		setRestContext(body);

		NetSuiteProductApi.handlePost();

		Assert.areEqual(200, RestContext.response.statusCode);
		Product2 first  = [SELECT Committed__c FROM Product2 WHERE External_Id__c = :EXT_ID_1];
		Product2 second = [SELECT Committed__c FROM Product2 WHERE External_Id__c = :EXT_ID_2];
		Assert.areEqual(5, first.Committed__c, 'Valid item should be updated');
		Assert.areEqual(0, second.Committed__c, 'Item without committedQty should be skipped');
	}

	@IsTest
	static void testHandlePost_allItemsSkipped_returnsNoValidItems() {
		String body = buildPayload(new List<Map<String, Object>>{
			new Map<String, Object>{ 'netsuiteItemId' => '', 'committedQty' => 5 }
		});
		setRestContext(body);

		NetSuiteProductApi.handlePost();

		Assert.areEqual(200, RestContext.response.statusCode);
		Assert.isTrue(responseBody().contains('No valid items'));
	}

	@IsTest
	static void testHandlePost_emptyItemsArray_returnsBadRequest() {
		setRestContext(buildPayload(new List<Map<String, Object>>()));

		NetSuiteProductApi.handlePost();

		Assert.areEqual(400, RestContext.response.statusCode);
		Assert.isTrue(responseBody().startsWith('ERROR:'));
	}

	@IsTest
	static void testHandlePost_missingItemsField_returnsBadRequest() {
		setRestContext('{}');

		NetSuiteProductApi.handlePost();

		Assert.areEqual(400, RestContext.response.statusCode);
	}

	@IsTest
	static void testHandlePost_malformedJson_returnsInternalError() {
		setRestContext('not-json');

		NetSuiteProductApi.handlePost();

		Assert.areEqual(500, RestContext.response.statusCode);
		Assert.isTrue(responseBody().startsWith('ERROR:'));
	}
}
