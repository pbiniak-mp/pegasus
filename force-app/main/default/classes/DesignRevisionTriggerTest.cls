@IsTest
private class DesignRevisionTriggerTest {
	private static final String OPP_NAME = 'Test Solar Project';
	private static final String OPP_STAGE = 'Prospecting';
	private static final Integer OPP_CLOSE_DAYS = 30;

	private static final String BULK_OPP_1_NAME = 'Bulk Opp 1';
	private static final String BULK_OPP_2_NAME = 'Bulk Opp 2';

	private static final Integer REV_BUILDING_HEIGHT = 20;
	private static final Integer REV_MODULE_WATTAGE = 400;
	private static final String REV_REASON = '--';
	private static final String REV_REASON_PEGASUS = 'Pegasus Revision';
	private static final String REV_NUMBER = '00';

	private static final String REV_SYSTEM_TYPE = 'Pitched Roof';
	private static final String REV_PANEL_TILT = '5°';
	private static final String REV_ROOF_SURFACE = 'Membrane';
	private static final Integer REV_PLANNED_INSTALL_DAYS = 60;

	private static final Integer REV_UPDATED_MODULE_QTY = 99;

	private static final String CDL_SHARE_TYPE = 'V';
	private static final String CDL_VISIBILITY = 'AllUsers';

	@TestSetup
	static void setup() {
		insert new Opportunity(
			Name = OPP_NAME,
			StageName = OPP_STAGE,
			CloseDate = Date.today().addDays(OPP_CLOSE_DAYS)
		);
	}

	@IsTest
	static void testActivation_copiesAllFieldsToOpportunity() {
		Opportunity opp = getOpp();
		Design_Revision__c rev = buildRevision(opp.Id, 20, 8.0);
		rev.System_Type__c = REV_SYSTEM_TYPE;
		rev.Panel_Tilt__c = REV_PANEL_TILT;
		rev.Roof_Surface__c = REV_ROOF_SURFACE;
		rev.Planned_Install_Date__c = Date.today().addDays(REV_PLANNED_INSTALL_DAYS);
		insert rev;

		Test.startTest();
		rev.Is_Active__c = true;
		update rev;
		Test.stopTest();

		Opportunity result = [
			SELECT
				Design_Revision__c,
				Module_Quantity__c,
				Project_Wattage_kW__c,
				System_Type__c,
				Panel_Tilt__c,
				Roof_Surface__c,
				Planned_Install_Date__c
			FROM Opportunity
			WHERE Id = :opp.Id
		];

		Assert.areEqual(rev.Id, result.Design_Revision__c, 'Lookup should point to active revision');
		Assert.areEqual(20, result.Module_Quantity__c, 'Module_Quantity__c should be copied');
		Assert.areEqual(8.0, result.Project_Wattage_kW__c, 'Project_Wattage_kW__c should be copied');
		Assert.areEqual(REV_SYSTEM_TYPE, result.System_Type__c, 'System_Type__c should be copied');
		Assert.areEqual(REV_PANEL_TILT, result.Panel_Tilt__c, 'Panel_Tilt__c should be copied');
		Assert.areEqual(REV_ROOF_SURFACE, result.Roof_Surface__c, 'Roof_Surface__c should be copied');
		Assert.areEqual(Date.today().addDays(REV_PLANNED_INSTALL_DAYS), result.Planned_Install_Date__c, 'Planned_Install_Date__c should be copied');
	}

	@IsTest
	static void testActivation_deactivatesOtherRevisions() {
		Opportunity opp = getOpp();
		Design_Revision__c rev1 = buildRevision(opp.Id, 10, 4.0);
		Design_Revision__c rev2 = buildRevision(opp.Id, 20, 8.0);
		insert new List<Design_Revision__c>{ rev1, rev2 };

		rev1.Is_Active__c = true;
		update rev1;

		Test.startTest();
		rev2.Is_Active__c = true;
		update rev2;
		Test.stopTest();

		Map<Id, Design_Revision__c> revMap = new Map<Id, Design_Revision__c>(
			[SELECT Id, Is_Active__c FROM Design_Revision__c WHERE Opportunity__c = :opp.Id]
		);

		Assert.isFalse(revMap.get(rev1.Id).Is_Active__c, 'Rev1 should be deactivated after Rev2 activated');
		Assert.isTrue(revMap.get(rev2.Id).Is_Active__c, 'Rev2 should remain active');
	}

	@IsTest
	static void testActivation_deactivatesMultipleOtherRevisions() {
		Opportunity opp = getOpp();
		Design_Revision__c rev1 = buildRevision(opp.Id, 10, 4.0);
		Design_Revision__c rev2 = buildRevision(opp.Id, 20, 8.0);
		Design_Revision__c rev3 = buildRevision(opp.Id, 30, 12.0);
		insert new List<Design_Revision__c>{ rev1, rev2, rev3 };

		rev1.Is_Active__c = true;
		update rev1;
		rev2.Is_Active__c = true;
		update rev2;

		Test.startTest();
		rev3.Is_Active__c = true;
		update rev3;
		Test.stopTest();

		Map<Id, Design_Revision__c> revMap = new Map<Id, Design_Revision__c>(
			[SELECT Id, Is_Active__c FROM Design_Revision__c WHERE Opportunity__c = :opp.Id]
		);

		Assert.isFalse(revMap.get(rev1.Id).Is_Active__c, 'Rev1 should be deactivated');
		Assert.isFalse(revMap.get(rev2.Id).Is_Active__c, 'Rev2 should be deactivated');
		Assert.isTrue(revMap.get(rev3.Id).Is_Active__c, 'Rev3 should be the only active revision');
	}

	@IsTest
	static void testActivation_linksRevisionFilesToOpportunity() {
		Opportunity opp = getOpp();
		Design_Revision__c rev = buildRevision(opp.Id, 15, 6.0);
		insert rev;

		ContentVersion cv = insertFile('Design Drawing');
		linkFileToRecord(cv.ContentDocumentId, rev.Id);

		Test.startTest();
		rev.Is_Active__c = true;
		update rev;
		Test.stopTest();

		Set<Id> oppDocIds = getLinkedDocIds(opp.Id);
		Assert.isTrue(oppDocIds.contains(cv.ContentDocumentId), 'Revision file should be linked to Opportunity');
	}

	@IsTest
	static void testActivation_linksMultipleFilesToOpportunity() {
		Opportunity opp = getOpp();
		Design_Revision__c rev = buildRevision(opp.Id, 15, 6.0);
		insert rev;

		ContentVersion cv1 = insertFile('Drawing A');
		ContentVersion cv2 = insertFile('Drawing B');
		linkFileToRecord(cv1.ContentDocumentId, rev.Id);
		linkFileToRecord(cv2.ContentDocumentId, rev.Id);

		Test.startTest();
		rev.Is_Active__c = true;
		update rev;
		Test.stopTest();

		Set<Id> oppDocIds = getLinkedDocIds(opp.Id);
		Assert.isTrue(oppDocIds.contains(cv1.ContentDocumentId), 'First file should be linked to Opportunity');
		Assert.isTrue(oppDocIds.contains(cv2.ContentDocumentId), 'Second file should be linked to Opportunity');
	}

	@IsTest
	static void testReactivation_replacesOldFilesWithNewOnes() {
		Opportunity opp = getOpp();
		Design_Revision__c rev1 = buildRevision(opp.Id, 10, 4.0);
		Design_Revision__c rev2 = buildRevision(opp.Id, 20, 8.0);
		insert new List<Design_Revision__c>{ rev1, rev2 };

		ContentVersion cv1 = insertFile('Rev1 Drawing');
		ContentVersion cv2 = insertFile('Rev2 Drawing');
		linkFileToRecord(cv1.ContentDocumentId, rev1.Id);
		linkFileToRecord(cv2.ContentDocumentId, rev2.Id);

		rev1.Is_Active__c = true;
		update rev1;

		Test.startTest();
		rev2.Is_Active__c = true;
		update rev2;
		Test.stopTest();

		Set<Id> oppDocIds = getLinkedDocIds(opp.Id);
		Assert.isFalse(oppDocIds.contains(cv1.ContentDocumentId), 'Rev1 file should be removed from Opportunity');
		Assert.isTrue(oppDocIds.contains(cv2.ContentDocumentId), 'Rev2 file should be linked to Opportunity');
	}

	@IsTest
	static void testActivation_onInsert_withIsActiveTrue() {
		Opportunity opp = getOpp();

		Test.startTest();
		Design_Revision__c rev = buildRevision(opp.Id, 25, 10.0);
		rev.Is_Active__c = true;
		insert rev;
		Test.stopTest();

		Opportunity result = [SELECT Design_Revision__c, Module_Quantity__c FROM Opportunity WHERE Id = :opp.Id];
		Assert.areEqual(rev.Id, result.Design_Revision__c, 'Lookup should be set on insert');
		Assert.areEqual(25, result.Module_Quantity__c, 'Fields should be copied on insert');
	}

	@IsTest
	static void testNoActivation_doesNotCopyFields() {
		Opportunity opp = getOpp();
		Design_Revision__c rev = buildRevision(opp.Id, 30, 12.0);
		insert rev;

		Test.startTest();
		rev.Module_Quantity__c = REV_UPDATED_MODULE_QTY;
		update rev;
		Test.stopTest();

		Opportunity result = [SELECT Module_Quantity__c FROM Opportunity WHERE Id = :opp.Id];
		Assert.areNotEqual(REV_UPDATED_MODULE_QTY, result.Module_Quantity__c, 'Fields should not be copied when Is_Active__c stays false');
	}

	@IsTest
	static void testBulkActivation_acrossMultipleOpportunities() {
		List<Opportunity> opps = new List<Opportunity>{
			new Opportunity(Name = BULK_OPP_1_NAME, StageName = OPP_STAGE, CloseDate = Date.today().addDays(OPP_CLOSE_DAYS)),
			new Opportunity(Name = BULK_OPP_2_NAME, StageName = OPP_STAGE, CloseDate = Date.today().addDays(OPP_CLOSE_DAYS))
		};
		insert opps;

		List<Design_Revision__c> revisions = new List<Design_Revision__c>{
			buildRevision(opps[0].Id, 10, 4.0),
			buildRevision(opps[1].Id, 20, 8.0)
		};
		insert revisions;

		Test.startTest();
		revisions[0].Is_Active__c = true;
		revisions[1].Is_Active__c = true;
		update revisions;
		Test.stopTest();

		Map<Id, Opportunity> oppMap = new Map<Id, Opportunity>(
			[SELECT Id, Design_Revision__c, Module_Quantity__c FROM Opportunity WHERE Id IN :opps]
		);

		Assert.areEqual(revisions[0].Id, oppMap.get(opps[0].Id).Design_Revision__c, 'Opp1 lookup should be set');
		Assert.areEqual(10, oppMap.get(opps[0].Id).Module_Quantity__c, 'Opp1 qty should be copied');
		Assert.areEqual(revisions[1].Id, oppMap.get(opps[1].Id).Design_Revision__c, 'Opp2 lookup should be set');
		Assert.areEqual(20, oppMap.get(opps[1].Id).Module_Quantity__c, 'Opp2 qty should be copied');
	}

	@IsTest
	static void testActivation_alreadyActive_noRedundantProcessing() {
		// Insert revision as active → activates on insert, copies Module_Quantity__c = 25
		Opportunity opp = getOpp();
		Design_Revision__c rev = buildRevision(opp.Id, 25, 10.0);
		rev.Is_Active__c = true;
		insert rev;

		Opportunity afterInsert = [SELECT Module_Quantity__c FROM Opportunity WHERE Id = :opp.Id];
		Assert.areEqual(25, afterInsert.Module_Quantity__c, 'Fields should be copied on initial activation');

		Test.startTest();
		// Update a non-activation field — Is_Active__c stays true (wasActive = true → not re-activated)
		rev.Module_Quantity__c = REV_UPDATED_MODULE_QTY;
		update rev;
		Test.stopTest();

		Opportunity afterUpdate = [SELECT Module_Quantity__c FROM Opportunity WHERE Id = :opp.Id];
		Assert.areEqual(
			25,
			afterUpdate.Module_Quantity__c,
			'Opportunity fields should not be overwritten when revision was already active'
		);
	}

	@IsTest
	static void testBuildNames_setsNameOnInsertAndRevisionNumberChange() {
		Opportunity opp = getOpp();

		Test.startTest();
		Design_Revision__c rev = buildRevision(opp.Id, 10, 4.0);
		insert rev;
		Test.stopTest();

		Design_Revision__c afterInsert = [SELECT Id, Name FROM Design_Revision__c WHERE Id = :rev.Id];
		Assert.isTrue(
			afterInsert.Name.contains('00'),
			'Name should contain revision number after insert: ' + afterInsert.Name
		);

		rev.Revision_Number__c = '01';
		rev.Revision_Reason__c = REV_REASON_PEGASUS;
		update rev;

		Design_Revision__c afterUpdate = [SELECT Id, Name FROM Design_Revision__c WHERE Id = :rev.Id];
		Assert.isTrue(
			afterUpdate.Name.contains('REV01'),
			'Name should update when Revision_Number__c changes: ' + afterUpdate.Name
		);
	}

	@IsTest
	static void testCreateNewRevision_clonesFieldsAndSetsParent() {
		Opportunity opp = getOpp();
		Design_Revision__c rev = buildRevision(opp.Id, 20, 8.0);
		rev.System_Type__c = REV_SYSTEM_TYPE;
		rev.Panel_Tilt__c = REV_PANEL_TILT;
		rev.Roof_Surface__c = REV_ROOF_SURFACE;
		insert rev;

		Test.startTest();
		Id newRevId = DesignRevisionService.createNewRevision(rev.Id, REV_REASON_PEGASUS, 'Some notes');
		Test.stopTest();

		Design_Revision__c newRev = [
			SELECT
				Id,
				Name,
				Opportunity__c,
				Parent_Revision__c,
				Revision_Number__c,
				Revision_Reason__c,
				Project_Notes__c,
				Is_Active__c,
				Status__c,
				Module_Quantity__c,
				System_Type__c,
				Panel_Tilt__c,
				Roof_Surface__c
			FROM Design_Revision__c
			WHERE Id = :newRevId
		];

		Assert.areEqual(opp.Id, newRev.Opportunity__c, 'Should be linked to same Opportunity');
		Assert.areEqual(rev.Id, newRev.Parent_Revision__c, 'Parent should be original revision');
		Assert.areEqual('01', newRev.Revision_Number__c, 'Next revision number should be 01');
		Assert.areEqual(REV_REASON_PEGASUS, newRev.Revision_Reason__c, 'Revision reason should be set');
		Assert.areEqual('Some notes', newRev.Project_Notes__c, 'Project notes should be set');
		Assert.isFalse(newRev.Is_Active__c, 'New revision should not be active');
		Assert.areEqual('Not Started', newRev.Status__c, 'Status should be Not Started');
		Assert.areEqual(20, newRev.Module_Quantity__c, 'Module_Quantity__c should be cloned');
		Assert.areEqual(REV_SYSTEM_TYPE, newRev.System_Type__c, 'System_Type__c should be cloned');
		Assert.areEqual(REV_PANEL_TILT, newRev.Panel_Tilt__c, 'Panel_Tilt__c should be cloned');
		Assert.areEqual(REV_ROOF_SURFACE, newRev.Roof_Surface__c, 'Roof_Surface__c should be cloned');
		Assert.isTrue(newRev.Name.contains('REV01'), 'Name should contain REV01');
	}

	@IsTest
	static void testCreateNewRevision_invocable_returnsNewRevisionId() {
		Opportunity opp = getOpp();
		Design_Revision__c rev = buildRevision(opp.Id, 10, 4.0);
		insert rev;

		CreateDesignRevisionInvocable.Request req = new CreateDesignRevisionInvocable.Request();
		req.revisionId = rev.Id;
		req.revisionReason = REV_REASON_PEGASUS;
		req.projectNotes = null;

		Test.startTest();
		List<CreateDesignRevisionInvocable.Result> results = CreateDesignRevisionInvocable.createNewRevision(
			new List<CreateDesignRevisionInvocable.Request>{ req }
		);
		Test.stopTest();

		Assert.areEqual(1, results.size(), 'Should return one result');
		Assert.isNotNull(results[0].newRevisionId, 'New revision Id should not be null');

		Design_Revision__c newRev = [
			SELECT Revision_Number__c, Parent_Revision__c
			FROM Design_Revision__c
			WHERE Id = :results[0].newRevisionId
		];
		Assert.areEqual('01', newRev.Revision_Number__c, 'Revision number should be 01');
		Assert.areEqual(rev.Id, newRev.Parent_Revision__c, 'Parent should be set');
	}

	private static Set<Id> getLinkedDocIds(Id recordId) {
		Set<Id> result = new Set<Id>();
		for (ContentDocumentLink cdl : [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :recordId]) {
			result.add(cdl.ContentDocumentId);
		}
		return result;
	}

	private static Opportunity getOpp() {
		return [SELECT Id FROM Opportunity LIMIT 1];
	}

	private static Design_Revision__c buildRevision(Id oppId, Decimal moduleQty, Decimal wattageKw) {
		return new Design_Revision__c(
			Opportunity__c = oppId,
			Building_Height_ft__c = REV_BUILDING_HEIGHT,
			Module_Quantity__c = moduleQty,
			Module_Wattage_W__c = REV_MODULE_WATTAGE,
			Project_Wattage_kW__c = wattageKw,
			Revision_Reason__c = REV_REASON,
			Revision_Number__c = REV_NUMBER
		);
	}

	private static ContentVersion insertFile(String title) {
		ContentVersion cv = new ContentVersion(
			Title = title,
			PathOnClient = title + '.txt',
			VersionData = Blob.valueOf(Test.isRunningTest() ? 'unit test' : title),
			IsMajorVersion = true
		);
		insert cv;
		return [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
	}

	private static void linkFileToRecord(Id contentDocumentId, Id recordId) {
		insert new ContentDocumentLink(
			ContentDocumentId = contentDocumentId,
			LinkedEntityId = recordId,
			ShareType = CDL_SHARE_TYPE,
			Visibility = CDL_VISIBILITY
		);
	}
}
