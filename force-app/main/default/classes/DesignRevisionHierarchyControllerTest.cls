@IsTest
private class DesignRevisionHierarchyControllerTest {
	private static final String OPP_NAME = 'Test Hierarchy Opp';
	private static final String OPP_STAGE = 'Prospecting';
	private static final Integer OPP_CLOSE_DAYS = 30;
	private static final String REV_REASON = '--';
	private static final String REV_NUMBER = '00';

	@TestSetup
	static void setup() {
		insert new Opportunity(
			Name = OPP_NAME,
			StageName = OPP_STAGE,
			CloseDate = Date.today().addDays(OPP_CLOSE_DAYS)
		);
	}

	@IsTest
	static void testGetRevisionHierarchy_returnsRootsWithNoParent() {
		Opportunity opp = getOpp();
		insert new List<Design_Revision__c>{
			buildRevision(opp.Id, '00', null),
			buildRevision(opp.Id, '01', null)
		};

		Test.startTest();
		List<DesignRevisionHierarchyController.RevisionNode> result =
			DesignRevisionHierarchyController.getRevisionHierarchy(opp.Id);
		Test.stopTest();

		Assert.areEqual(2, result.size(), 'Should return 2 root nodes');
		Assert.isTrue(result[0].children.isEmpty(), 'Root nodes should have no children');
	}

	@IsTest
	static void testGetRevisionHierarchy_buildsParentChildRelationship() {
		Opportunity opp = getOpp();
		Design_Revision__c parent = buildRevision(opp.Id, '00', null);
		insert parent;
		Design_Revision__c child = buildRevision(opp.Id, '01', parent.Id);
		insert child;

		Test.startTest();
		List<DesignRevisionHierarchyController.RevisionNode> result =
			DesignRevisionHierarchyController.getRevisionHierarchy(opp.Id);
		Test.stopTest();

		Assert.areEqual(1, result.size(), 'Should return 1 root node');
		Assert.areEqual(1, result[0].children.size(), 'Root should have 1 child');
		Assert.areEqual(child.Id, result[0].children[0].id, 'Child Id should match');
	}

	@IsTest
	static void testGetRevisionHierarchy_mapsNodeFieldsCorrectly() {
		Opportunity opp = getOpp();
		Design_Revision__c rev = buildRevision(opp.Id, '00', null);
		rev.Revision_Reason__c = 'Client Request';
		rev.Project_Notes__c = 'Some notes';
		insert rev;

		Design_Revision__c inserted = [SELECT Id, Name FROM Design_Revision__c WHERE Id = :rev.Id];

		Test.startTest();
		List<DesignRevisionHierarchyController.RevisionNode> result =
			DesignRevisionHierarchyController.getRevisionHierarchy(opp.Id);
		Test.stopTest();

		DesignRevisionHierarchyController.RevisionNode node = result[0];
		Assert.areEqual(inserted.Id, node.id, 'Id should match');
		Assert.areEqual(inserted.Name, node.name, 'Name should match');
		Assert.areEqual(Constants.DESIGN_REVISION_RECORD_URL_BASE + inserted.Id + Constants.RECORD_URL_VIEW_SUFFIX, node.recordUrl, 'recordUrl should be correct');
		Assert.areEqual('Client Request', node.revisionReason, 'revisionReason should match');
		Assert.areEqual('Some notes', node.projectNotes, 'projectNotes should match');
	}

	@IsTest
	static void testGetRevisionHierarchy_returnsEmptyListWhenNoRevisions() {
		Opportunity opp = getOpp();

		Test.startTest();
		List<DesignRevisionHierarchyController.RevisionNode> result =
			DesignRevisionHierarchyController.getRevisionHierarchy(opp.Id);
		Test.stopTest();

		Assert.areEqual(0, result.size(), 'Should return empty list when no revisions exist');
	}

	@IsTest
	static void testGetRevisionHierarchy_childWithUnknownParentBecomesRoot() {
		Opportunity opp = getOpp();
		Design_Revision__c rev = buildRevision(opp.Id, '00', null);
		insert rev;

		// Simulate a child whose parent belongs to a different Opportunity (not in query result)
		Opportunity otherOpp = new Opportunity(
			Name = 'Other Opp',
			StageName = OPP_STAGE,
			CloseDate = Date.today().addDays(OPP_CLOSE_DAYS)
		);
		insert otherOpp;
		Design_Revision__c foreignParent = buildRevision(otherOpp.Id, '00', null);
		insert foreignParent;

		Design_Revision__c orphan = buildRevision(opp.Id, '01', foreignParent.Id);
		insert orphan;

		Test.startTest();
		List<DesignRevisionHierarchyController.RevisionNode> result =
			DesignRevisionHierarchyController.getRevisionHierarchy(opp.Id);
		Test.stopTest();

		Assert.areEqual(2, result.size(), 'Orphan with unknown parent should be treated as root');
	}

	private static Opportunity getOpp() {
		return [SELECT Id FROM Opportunity WHERE Name = :OPP_NAME LIMIT 1];
	}

	private static Design_Revision__c buildRevision(Id oppId, String revNumber, Id parentId) {
		return new Design_Revision__c(
			Opportunity__c = oppId,
			Revision_Number__c = revNumber,
			Revision_Reason__c = REV_REASON,
			Parent_Revision__c = parentId
		);
	}
}
