@IsTest
private class OpportunitySelectorTest {

	private static final String OPP_NAME  = 'Opp Selector Test';
	private static final String OPP_STAGE = 'Prospecting';

	@TestSetup
	static void setup() {
		insert new Opportunity(
			Name      = OPP_NAME,
			StageName = OPP_STAGE,
			CloseDate = Date.today().addDays(30)
		);
	}

	private static Opportunity getOpp() {
		return [SELECT Id FROM Opportunity LIMIT 1];
	}

	// ── getOpportunitiesByIds ────────────────────────────────────────────

	@IsTest
	static void testGetOpportunitiesByIds_returnsMatchingRecord() {
		Opportunity opp = getOpp();
		List<Opportunity> result = OpportunitySelector.getOpportunitiesByIds(new Set<Id>{ opp.Id });
		Assert.areEqual(1, result.size(), 'Should return the one matching opportunity');
		Assert.areEqual(opp.Id, result[0].Id);
		Assert.areEqual(OPP_NAME, result[0].Name);
	}

	@IsTest
	static void testGetOpportunitiesByIds_emptySet_returnsEmpty() {
		List<Opportunity> result = OpportunitySelector.getOpportunitiesByIds(new Set<Id>());
		Assert.isTrue(result.isEmpty(), 'Empty id set should return empty list');
	}

	@IsTest
	static void testGetOpportunitiesByIds_deletedId_returnsEmpty() {
		Opportunity temp = new Opportunity(
			Name      = 'Temp Delete Opp',
			StageName = OPP_STAGE,
			CloseDate = Date.today().addDays(30)
		);
		insert temp;
		Id deletedId = temp.Id;
		delete temp;

		List<Opportunity> result = OpportunitySelector.getOpportunitiesByIds(new Set<Id>{ deletedId });
		Assert.isTrue(result.isEmpty(), 'Deleted record id should return empty list');
	}

	// ── getOpportunityById ───────────────────────────────────────────────

	@IsTest
	static void testGetOpportunityById_returnsRecord() {
		Opportunity opp = getOpp();
		Opportunity result = OpportunitySelector.getOpportunityById(opp.Id);
		Assert.isNotNull(result, 'Should return the opportunity');
		Assert.areEqual(opp.Id, result.Id);
		Assert.areEqual(OPP_NAME, result.Name);
	}

	@IsTest
	static void testGetOpportunityById_nullId_returnsNull() {
		Opportunity result = OpportunitySelector.getOpportunityById(null);
		Assert.isNull(result, 'Null id should return null');
	}

	@IsTest
	static void testGetOpportunityById_deletedId_returnsNull() {
		Opportunity temp = new Opportunity(
			Name      = 'Temp Delete Opp 2',
			StageName = OPP_STAGE,
			CloseDate = Date.today().addDays(30)
		);
		insert temp;
		Id deletedId = temp.Id;
		delete temp;

		Opportunity result = OpportunitySelector.getOpportunityById(deletedId);
		Assert.isNull(result, 'Deleted record id should return null');
	}
}
