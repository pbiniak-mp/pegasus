@IsTest
private class OpportunityIntegrationPayloadBuilderTest {

	private static Integer idCounter = 1;

	private static Id fakeOppId() {
		String n = String.valueOf(idCounter++);
		return Id.valueOf(Opportunity.SObjectType.getDescribe().getKeyPrefix() + '000000000000'.substring(n.length()) + n);
	}

	@IsTest
	static void createPayloadIncludesWattage() {
		Opportunity opp = new Opportunity(
			Id = fakeOppId(),
			Name = 'P1',
			StageName = 'Qualification',
			Project_Wattage_kW__c = 9.25
		);
		Datetime ts = Datetime.newInstanceGmt(2026, 6, 23, 10, 0, 0);

		IIntegrationPayloadBuilder builder = new OpportunityIntegrationPayloadBuilder();
		String payloadJson = builder.buildPayload(opp, Constants.INTEGRATION_EVENT_OPP_CREATED, ts);

		Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(payloadJson);
		Assert.areEqual('P1', (String) body.get('name'));
		Assert.areEqual('Qualification', (String) body.get('stageName'));
		Assert.areEqual(Constants.INTEGRATION_EVENT_OPP_CREATED, (String) body.get('eventType'));
		Assert.areEqual('9.25', String.valueOf(body.get('projectWattageKw')));
		Assert.isNotNull(body.get('opportunityId'));
		Assert.isNotNull(body.get('eventTimestamp'));
	}

	@IsTest
	static void stageChangePayloadOmitsWattage() {
		Opportunity opp = new Opportunity(
			Id = fakeOppId(),
			Name = 'P2',
			StageName = Constants.OPPORTUNITY_STAGE_QUOTE,
			Project_Wattage_kW__c = 9.25
		);

		IIntegrationPayloadBuilder builder = new OpportunityIntegrationPayloadBuilder();
		String payloadJson = builder.buildPayload(opp, Constants.INTEGRATION_EVENT_OPP_STAGE_CHANGED, Datetime.now());

		Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(payloadJson);
		Assert.isFalse(body.containsKey('projectWattageKw'), 'Stage-change contract has no wattage');
		Assert.areEqual(Constants.OPPORTUNITY_STAGE_QUOTE, (String) body.get('stageName'));
		Assert.areEqual(Constants.INTEGRATION_EVENT_OPP_STAGE_CHANGED, (String) body.get('eventType'));
	}
}
