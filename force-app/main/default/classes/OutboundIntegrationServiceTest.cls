@IsTest
private class OutboundIntegrationServiceTest {

	private static final String NC = 'Glide_Analytics';
	private static final String PATH = '/opportunities';
	private static final String STAGE_INITIAL = 'Qualification';
	private static final String STAGE_NEXT = Constants.OPPORTUNITY_STAGE_QUOTE;

	// --- helpers ---------------------------------------------------------

	private static void activateIntegration() {
		OutboundIntegrationService.configOverride = new Outbound_Integration__mdt(
			Named_Credential__c = NC,
			Endpoint_Path__c = PATH,
			HTTP_Method__c = Constants.INTEGRATION_HTTP_METHOD_POST,
			Active__c = true
		);
	}

	private static void deactivateIntegration() {
		OutboundIntegrationService.configOverride = new Outbound_Integration__mdt(
			Named_Credential__c = NC,
			Endpoint_Path__c = PATH,
			Active__c = false
		);
	}

	private static Id makeAccount() {
		Account acc = new Account(Name = 'Integration Acc');
		insert acc;
		return acc.Id;
	}

	private static Opportunity newOpp(Id accId, String name) {
		return new Opportunity(
			Name = name,
			AccountId = accId,
			StageName = STAGE_INITIAL,
			CloseDate = Date.today().addDays(30),
			Project_Wattage_kW__c = 12.5
		);
	}

	private class Mock implements HttpCalloutMock {
		private Integer code;
		private String body;
		private Mock(Integer code, String body) {
			this.code = code;
			this.body = body;
		}
		public HttpResponse respond(HttpRequest req) {
			HttpResponse res = new HttpResponse();
			res.setStatusCode(code);
			res.setBody(body);
			res.setHeader('X-Trace-Id', 'abc-123');
			return res;
		}
	}

	private class ThrowingMock implements HttpCalloutMock {
		public HttpResponse respond(HttpRequest req) {
			throw new CalloutException('Simulated connection failure');
		}
	}

	// --- tests -----------------------------------------------------------

	@IsTest
	static void insertSendsAndStampsOnSuccess() {
		Id accId = makeAccount();
		activateIntegration();
		Test.setMock(HttpCalloutMock.class, new Mock(200, '{"ok":true}'));

		Test.startTest();
		insert newOpp(accId, 'Opp Success');
		Test.stopTest();

		List<Integration_Log__c> logs = [
			SELECT Status__c, Event_Type__c, Response_Status_Code__c, Source_Record_Id__c,
				Request_Body__c, Request_Headers__c, Response_Headers__c, Endpoint__c, HTTP_Method__c, Sent_At__c
			FROM Integration_Log__c
		];
		Assert.areEqual(1, logs.size(), 'One log per Opportunity; the stamp update must not create another');

		Integration_Log__c log = logs[0];
		Assert.areEqual(Constants.INTEGRATION_STATUS_SENT, log.Status__c);
		Assert.areEqual(Constants.INTEGRATION_EVENT_OPP_CREATED, log.Event_Type__c);
		Assert.areEqual(200, log.Response_Status_Code__c);
		Assert.areEqual('callout:' + NC + PATH, log.Endpoint__c);
		Assert.areEqual(Constants.INTEGRATION_HTTP_METHOD_POST, log.HTTP_Method__c, 'Create uses POST');
		Assert.isNotNull(log.Sent_At__c);
		Assert.isTrue(log.Response_Headers__c.contains('X-Trace-Id'), 'Response headers captured');

		Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(log.Request_Body__c);
		Assert.areEqual('Opp Success', (String) body.get('name'));
		Assert.areEqual(STAGE_INITIAL, (String) body.get('stageName'));
		Assert.areEqual(12.50, Decimal.valueOf(String.valueOf(body.get('projectWattageKw'))).setScale(2),
			'Created payload carries project wattage');

		Opportunity stamped = [
			SELECT Integration_Status__c, Last_Sent__c
			FROM Opportunity
			WHERE Id = :log.Source_Record_Id__c
		];
		Assert.areEqual(Constants.OPP_INTEGRATION_STATUS_SENT, stamped.Integration_Status__c);
		Assert.isNotNull(stamped.Last_Sent__c);
	}

	@IsTest
	static void serverErrorMarksFailed() {
		Id accId = makeAccount();
		activateIntegration();
		Test.setMock(HttpCalloutMock.class, new Mock(500, 'boom'));

		Test.startTest();
		insert newOpp(accId, 'Opp 500');
		Test.stopTest();

		Integration_Log__c log = [
			SELECT Status__c, Response_Status_Code__c, Error_Message__c
			FROM Integration_Log__c
			LIMIT 1
		];
		Assert.areEqual(Constants.INTEGRATION_STATUS_FAILED, log.Status__c);
		Assert.areEqual(500, log.Response_Status_Code__c);
		Assert.isNotNull(log.Error_Message__c);

		Opportunity stamped = [SELECT Integration_Status__c, Last_Sent__c FROM Opportunity LIMIT 1];
		Assert.areEqual(Constants.OPP_INTEGRATION_STATUS_FAILED, stamped.Integration_Status__c);
		Assert.isNull(stamped.Last_Sent__c, 'Last Sent is only set on a successful delivery');
	}

	@IsTest
	static void calloutExceptionMarksFailed() {
		Id accId = makeAccount();
		activateIntegration();
		Test.setMock(HttpCalloutMock.class, new ThrowingMock());

		Test.startTest();
		insert newOpp(accId, 'Opp Exception');
		Test.stopTest();

		Integration_Log__c log = [
			SELECT Status__c, Response_Status_Code__c, Error_Message__c
			FROM Integration_Log__c
			LIMIT 1
		];
		Assert.areEqual(Constants.INTEGRATION_STATUS_FAILED, log.Status__c);
		Assert.isNull(log.Response_Status_Code__c, 'No HTTP status when the callout throws');
		Assert.isTrue(log.Error_Message__c.contains('CalloutException'), 'Exception captured on the log');
	}

	@IsTest
	static void stageChangeCreatesLog() {
		Id accId = makeAccount();
		deactivateIntegration();
		Opportunity opp = newOpp(accId, 'Opp Stage');
		insert opp;
		Assert.areEqual(0, [SELECT COUNT() FROM Integration_Log__c], 'Inactive integration: insert is a no-op');

		activateIntegration();
		Test.setMock(HttpCalloutMock.class, new Mock(200, '{}'));

		Test.startTest();
		update new Opportunity(Id = opp.Id, StageName = STAGE_NEXT);
		Test.stopTest();

		Integration_Log__c log = [
			SELECT Event_Type__c, Status__c, Request_Body__c, HTTP_Method__c, Endpoint__c
			FROM Integration_Log__c
			LIMIT 1
		];
		Assert.areEqual(Constants.INTEGRATION_EVENT_OPP_STAGE_CHANGED, log.Event_Type__c);
		Assert.areEqual(Constants.INTEGRATION_STATUS_SENT, log.Status__c);
		Assert.areEqual(Constants.INTEGRATION_HTTP_METHOD_PATCH, log.HTTP_Method__c, 'Stage change uses PATCH');
		Assert.areEqual('callout:' + NC + PATH + '/' + opp.Id, log.Endpoint__c,
			'PATCH targets the record by Salesforce Id in the URL');

		Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(log.Request_Body__c);
		Assert.areEqual(STAGE_NEXT, (String) body.get('stageName'));
		Assert.isFalse(body.containsKey('projectWattageKw'), 'Stage-change payload omits wattage');
	}

	@IsTest
	static void inactiveIntegrationDoesNothing() {
		Id accId = makeAccount();
		deactivateIntegration();

		Test.startTest();
		insert newOpp(accId, 'Opp Inactive');
		Test.stopTest();

		Assert.areEqual(0, [SELECT COUNT() FROM Integration_Log__c]);
	}

	@IsTest
	static void bulkRespectsCalloutChunk() {
		Id accId = makeAccount();
		activateIntegration();
		Test.setMock(HttpCalloutMock.class, new Mock(200, '{}'));

		List<Opportunity> opps = new List<Opportunity>();
		for (Integer i = 0; i < 200; i++) {
			opps.add(newOpp(accId, 'Bulk ' + i));
		}

		Test.startTest();
		insert opps;
		Test.stopTest();

		Assert.areEqual(200, [SELECT COUNT() FROM Integration_Log__c], 'One Queued log per Opportunity (bulk insert)');
		Integer sent = [SELECT COUNT() FROM Integration_Log__c WHERE Status__c = :Constants.INTEGRATION_STATUS_SENT];
		Assert.areEqual(Constants.INTEGRATION_CALLOUT_CHUNK_SIZE, sent,
			'A single Queueable run processes one chunk (<=90 callouts), keeping under the 100-callout limit');
		Assert.areEqual(200 - Constants.INTEGRATION_CALLOUT_CHUNK_SIZE, IntegrationLogSelector.countQueued(),
			'Remaining logs stay Queued for the next (chained) run');
	}
}
