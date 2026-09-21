@IsTest
private class IntegrationCalloutQueueableTest {

	private static final String ENDPOINT = 'callout:Glide_Analytics/opportunities';

	private class Mock implements HttpCalloutMock {
		private Integer code;
		private Mock(Integer code) {
			this.code = code;
		}
		public HttpResponse respond(HttpRequest req) {
			HttpResponse res = new HttpResponse();
			res.setStatusCode(code);
			res.setBody('{}');
			return res;
		}
	}

	/**
	 * Integration stays inactive so the Opportunity trigger does not queue its
	 * own logs — these tests drive the Queueable directly.
	 *
	 * @return the inserted Opportunity used by the Queueable tests
	 */
	private static Opportunity makeOpp() {
		GlideAnalyticsIntegrationService.configOverride = new Outbound_Integration__mdt(Active__c = false);
		Account acc = new Account(Name = 'Queueable Acc');
		insert acc;
		Opportunity opp = new Opportunity(
			Name = 'Queueable Opp',
			AccountId = acc.Id,
			StageName = 'Qualification',
			CloseDate = Date.today().addDays(30)
		);
		insert opp;
		return opp;
	}

	private static void queueLog(Id oppId, String method, String endpoint) {
		insert IntegrationLogService.buildOutboundLog(
			Constants.INTEGRATION_GLIDE_ANALYTICS,
			Constants.INTEGRATION_EVENT_OPP_CREATED,
			oppId,
			'{"salesforce_id":"' + oppId + '"}',
			method,
			endpoint,
			Datetime.now()
		);
	}

	@IsTest
	static void emptyQueueIsANoOp() {
		Test.startTest();
		System.enqueueJob(new IntegrationCalloutQueueable());
		Test.stopTest();

		Assert.areEqual(0, [SELECT COUNT() FROM Integration_Log__c],
			'Nothing to process and nothing created');
	}

	@IsTest
	static void sendsQueuedLogAndStampsDeliveryOnOpportunity() {
		Opportunity opp = makeOpp();
		queueLog(opp.Id, Constants.INTEGRATION_HTTP_METHOD_POST, ENDPOINT);
		Test.setMock(HttpCalloutMock.class, new Mock(200));

		Test.startTest();
		System.enqueueJob(new IntegrationCalloutQueueable());
		Test.stopTest();

		Integration_Log__c log = [
			SELECT Status__c, Response_Status_Code__c, Sent_At__c, Opportunity__c
			FROM Integration_Log__c
			LIMIT 1
		];
		Assert.areEqual(Constants.INTEGRATION_STATUS_SENT, log.Status__c);
		Assert.areEqual(200, log.Response_Status_Code__c);
		Assert.isNotNull(log.Sent_At__c);
		Assert.areEqual(opp.Id, log.Opportunity__c,
			'Log is reachable from the Opportunity through the typed lookup');

		Opportunity stamped = [SELECT Last_Sent__c FROM Opportunity WHERE Id = :opp.Id];
		Assert.isNotNull(stamped.Last_Sent__c);
	}

	@IsTest
	static void failedCalloutLeavesTheOpportunityAlone() {
		Opportunity opp = makeOpp();
		queueLog(opp.Id, Constants.INTEGRATION_HTTP_METHOD_PATCH, ENDPOINT + '/' + opp.Id);
		Test.setMock(HttpCalloutMock.class, new Mock(503));

		Test.startTest();
		System.enqueueJob(new IntegrationCalloutQueueable());
		Test.stopTest();

		Integration_Log__c log = [
			SELECT Status__c, Error_Message__c, Opportunity__c
			FROM Integration_Log__c
			LIMIT 1
		];
		Assert.areEqual(Constants.INTEGRATION_STATUS_FAILED, log.Status__c);
		Assert.areEqual('HTTP 503', log.Error_Message__c);
		Assert.areEqual(opp.Id, log.Opportunity__c,
			'A failure is still reachable from the Opportunity, on the log');

		// The failure lives on the log only. Nothing is written to the Opportunity,
		// so it can never carry a stale Failed after the problem is fixed.
		Opportunity stamped = [SELECT Last_Sent__c FROM Opportunity WHERE Id = :opp.Id];
		Assert.isNull(stamped.Last_Sent__c, 'Last Sent only reflects successful deliveries');
	}
}
