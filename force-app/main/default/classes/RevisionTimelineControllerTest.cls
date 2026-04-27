@IsTest
private class RevisionTimelineControllerTest {

	@TestSetup
	static void setup() {
		Account acc = new Account(Name = 'Test Account');
		insert acc;

		Opportunity opp = new Opportunity(
			Name = 'Test Opportunity',
			AccountId = acc.Id,
			StageName = 'Prospecting',
			CloseDate = Date.today().addDays(30)
		);
		insert opp;

		List<Design_Revision__c> revisions = new List<Design_Revision__c>{
			new Design_Revision__c(
				Name = 'Revision 1',
				Opportunity__c = opp.Id,
				Is_Active__c = true,
				Status__c = 'Active Design',
				Project_Wattage_kW__c = 10.5,
				System_Type__c = 'Pitched Roof',
				Roof_Surface__c = 'Gravel',
				Project_Notes__c = 'Test notes'
			),
			new Design_Revision__c(
				Name = 'Revision 2',
				Opportunity__c = opp.Id,
				Is_Active__c = false,
				Status__c = 'Closed',
				Project_Wattage_kW__c = null,
				System_Type__c = null,
				Roof_Surface__c = null,
				Project_Notes__c = null
			)
		};
		insert revisions;
	}

	@IsTest
	static void testGetRevisionsByOpportunity_returnsCorrectCount() {
		Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

		Test.startTest();
		List<RevisionTimelineController.RevisionWrapper> result =
			RevisionTimelineController.getRevisionsByOpportunity(opp.Id);
		Test.stopTest();

		System.assertEquals(2, result.size(), 'Should return 2 revisions');
	}

	@IsTest
	static void testGetRevisionsByOpportunity_activeRevision() {
		Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

		Test.startTest();
		List<RevisionTimelineController.RevisionWrapper> result =
			RevisionTimelineController.getRevisionsByOpportunity(opp.Id);
		Test.stopTest();

		RevisionTimelineController.RevisionWrapper activeRev = null;
		RevisionTimelineController.RevisionWrapper inactiveRev = null;
		for (RevisionTimelineController.RevisionWrapper w : result) {
			if (w.isActive == true) {
				activeRev = w;
			} else {
				inactiveRev = w;
			}
		}

		System.assertNotEquals(null, activeRev, 'Should have an active revision');
		System.assertEquals('Active Design', activeRev.status, 'Active revision status should be Active Design');
		System.assertEquals('10.50', activeRev.projectWattage, 'Project wattage should be formatted as string');

		System.assertNotEquals(null, inactiveRev, 'Should have an inactive revision');
		System.assertEquals('Closed', inactiveRev.status, 'Inactive revision status should be Closed');
		System.assertEquals('—', inactiveRev.projectWattage, 'Null wattage should return em dash');
		System.assertEquals('—', inactiveRev.systemType, 'Null system type should return em dash');
		System.assertEquals('—', inactiveRev.roofSurface, 'Null roof surface should return em dash');
	}

	@IsTest
	static void testGetRevisionsByOpportunity_nullOpportunityId() {
		Test.startTest();
		List<RevisionTimelineController.RevisionWrapper> result = null;
		Exception caughtEx = null;
		try {
			result = RevisionTimelineController.getRevisionsByOpportunity(null);
		} catch (AuraHandledException e) {
			caughtEx = e;
		}
		Test.stopTest();

		// Either returns empty list or throws AuraHandledException — both are acceptable
		if (caughtEx == null) {
			System.assertNotEquals(null, result, 'Result should not be null when opportunityId is null');
		}
	}

	@IsTest
	static void testGetRevisionsByOpportunity_noRevisions() {
		Account acc = new Account(Name = 'Empty Account');
		insert acc;
		Opportunity emptyOpp = new Opportunity(
			Name = 'Empty Opportunity',
			AccountId = acc.Id,
			StageName = 'Prospecting',
			CloseDate = Date.today().addDays(30)
		);
		insert emptyOpp;

		Test.startTest();
		List<RevisionTimelineController.RevisionWrapper> result =
			RevisionTimelineController.getRevisionsByOpportunity(emptyOpp.Id);
		Test.stopTest();

		System.assertEquals(0, result.size(), 'Should return 0 revisions for opportunity with no revisions');
	}
}