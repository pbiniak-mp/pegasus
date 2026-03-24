@IsTest
private class DesignRevisionSelectorTest {

	private static final String OPP_NAME    = 'Selector Test Opp';
	private static final String OPP_STAGE   = 'Prospecting';
	private static final Integer CLOSE_DAYS = 30;
	private static final String REV_REASON  = '--';
	private static final String REV_NUMBER  = '00';

	@TestSetup
	static void setup() {
		Opportunity opp = new Opportunity(
			Name      = OPP_NAME,
			StageName = OPP_STAGE,
			CloseDate = Date.today().addDays(CLOSE_DAYS)
		);
		insert opp;

		insert new Design_Revision__c(
			Opportunity__c        = opp.Id,
			Building_Height_ft__c = 10,
			Module_Wattage_W__c   = 400,
			Revision_Reason__c    = REV_REASON,
			Revision_Number__c    = REV_NUMBER
		);
	}

	private static Design_Revision__c getRev() {
		return [SELECT Id, Opportunity__c FROM Design_Revision__c LIMIT 1];
	}

	private static Opportunity getOpp() {
		return [SELECT Id FROM Opportunity LIMIT 1];
	}

	// ── getDesignRevisionsByIds ──────────────────────────────────────────

	@IsTest
	static void testGetDesignRevisionsByIds_returnsMatchingRecord() {
		Design_Revision__c rev = getRev();
		List<Design_Revision__c> result = DesignRevisionSelector.getDesignRevisionsByIds(new Set<Id>{ rev.Id });
		Assert.areEqual(1, result.size(), 'Should return the one matching revision');
		Assert.areEqual(rev.Id, result[0].Id);
	}

	@IsTest
	static void testGetDesignRevisionsByIds_emptySet_returnsEmpty() {
		List<Design_Revision__c> result = DesignRevisionSelector.getDesignRevisionsByIds(new Set<Id>());
		Assert.isTrue(result.isEmpty(), 'Empty id set should return empty list');
	}

	@IsTest
	static void testGetDesignRevisionsByIds_deletedId_returnsEmpty() {
		Opportunity opp = getOpp();
		Design_Revision__c temp = new Design_Revision__c(
			Opportunity__c        = opp.Id,
			Building_Height_ft__c = 10,
			Module_Wattage_W__c   = 400,
			Revision_Reason__c    = REV_REASON,
			Revision_Number__c    = REV_NUMBER
		);
		insert temp;
		Id deletedId = temp.Id;
		delete temp;

		List<Design_Revision__c> result = DesignRevisionSelector.getDesignRevisionsByIds(
			new Set<Id>{ deletedId }
		);
		Assert.isTrue(result.isEmpty(), 'Deleted record id should return empty list');
	}

	// ── getDesignRevisionById ────────────────────────────────────────────

	@IsTest
	static void testGetDesignRevisionById_returnsRecord() {
		Design_Revision__c rev = getRev();
		Design_Revision__c result = DesignRevisionSelector.getDesignRevisionById(rev.Id);
		Assert.isNotNull(result, 'Should return the revision');
		Assert.areEqual(rev.Id, result.Id);
	}

	@IsTest
	static void testGetDesignRevisionById_unknownId_returnsNull() {
		Design_Revision__c result = DesignRevisionSelector.getDesignRevisionById(null);
		Assert.isNull(result, 'Null id should return null');
	}

	// ── getRevisionsByOpportunityIds ─────────────────────────────────────

	@IsTest
	static void testGetRevisionsByOpportunityIds_returnsRevisions() {
		Opportunity opp = getOpp();
		List<Design_Revision__c> result = DesignRevisionSelector.getRevisionsByOpportunityIds(
			new Set<Id>{ opp.Id }
		);
		Assert.areEqual(1, result.size(), 'Should return revisions for the opportunity');
		Assert.areEqual(opp.Id, result[0].Opportunity__c);
	}

	@IsTest
	static void testGetRevisionsByOpportunityIds_emptySet_returnsEmpty() {
		List<Design_Revision__c> result = DesignRevisionSelector.getRevisionsByOpportunityIds(new Set<Id>());
		Assert.isTrue(result.isEmpty(), 'Empty id set should return empty list');
	}
}
