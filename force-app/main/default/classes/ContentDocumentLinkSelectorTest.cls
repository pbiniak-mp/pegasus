@IsTest
private class ContentDocumentLinkSelectorTest {

	private static final String CDL_SHARE_TYPE = 'V';
	private static final String CDL_VISIBILITY = 'AllUsers';

	@TestSetup
	static void setup() {
		Opportunity opp = new Opportunity(
			Name      = 'CDL Selector Test',
			StageName = 'Prospecting',
			CloseDate = Date.today().addDays(30)
		);
		insert opp;

		ContentVersion cv = new ContentVersion(
			Title          = 'Test File',
			PathOnClient   = 'TestFile.txt',
			VersionData    = Blob.valueOf('test content'),
			IsMajorVersion = true
		);
		insert cv;

		Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;

		insert new ContentDocumentLink(
			ContentDocumentId = docId,
			LinkedEntityId    = opp.Id,
			ShareType         = CDL_SHARE_TYPE,
			Visibility        = CDL_VISIBILITY
		);
	}

	private static Opportunity getOpp() {
		return [SELECT Id FROM Opportunity LIMIT 1];
	}

	// ── getByLinkedEntityIds ─────────────────────────────────────────────

	@IsTest
	static void testGetByLinkedEntityIds_returnsLinks() {
		Opportunity opp = getOpp();
		List<ContentDocumentLink> result = ContentDocumentLinkSelector.getByLinkedEntityIds(
			new Set<Id>{ opp.Id }
		);
		Assert.areEqual(1, result.size(), 'Should return the one CDL for the opportunity');
		Assert.areEqual(opp.Id, result[0].LinkedEntityId);
	}

	@IsTest
	static void testGetByLinkedEntityIds_returnsShareTypeAndVisibility() {
		Opportunity opp = getOpp();
		List<ContentDocumentLink> result = ContentDocumentLinkSelector.getByLinkedEntityIds(
			new Set<Id>{ opp.Id }
		);
		Assert.areEqual(CDL_SHARE_TYPE, result[0].ShareType);
		Assert.areEqual(CDL_VISIBILITY, result[0].Visibility);
	}

	// ── getByLinkedEntityId (singular) ───────────────────────────────────

	@IsTest
	static void testGetByLinkedEntityId_returnsLink() {
		Opportunity opp = getOpp();
		ContentDocumentLink result = ContentDocumentLinkSelector.getByLinkedEntityId(opp.Id);
		Assert.isNotNull(result, 'Should return the CDL');
		Assert.areEqual(opp.Id, result.LinkedEntityId);
	}

	@IsTest
	static void testGetByLinkedEntityId_noLinks_returnsNull() {
		// Insert an opportunity with no files linked
		Opportunity freshOpp = new Opportunity(
			Name      = 'No Files Opp',
			StageName = 'Prospecting',
			CloseDate = Date.today().addDays(30)
		);
		insert freshOpp;

		ContentDocumentLink result = ContentDocumentLinkSelector.getByLinkedEntityId(freshOpp.Id);
		Assert.isNull(result, 'Should return null when no CDL exists for the record');
	}
}
