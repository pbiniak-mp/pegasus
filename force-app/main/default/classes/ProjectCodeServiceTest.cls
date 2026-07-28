@IsTest
private class ProjectCodeServiceTest {

	private static final String REV_00 = '00';
	private static final String REV_01 = '01';

	private static Id cachedAccountId;

	@TestSetup
	static void setup() {
		insert new Account(Name = 'PCS Test Account');
	}

	// The Closed Won flow creates an Order, which needs an Account on the Opportunity.
	private static Id accountId() {
		if (cachedAccountId == null) {
			cachedAccountId = [SELECT Id FROM Account LIMIT 1].Id;
		}
		return cachedAccountId;
	}

	// The outbound integration is irrelevant here; keep it off so the DML in
	// these tests never queues a callout.
	private static void disableOutboundIntegration() {
		GlideAnalyticsIntegrationService.configOverride = new Outbound_Integration__mdt(Active__c = false);
	}

	private static Opportunity buildOpportunity(String name) {
		return new Opportunity(
			Name = name,
			AccountId = accountId(),
			StageName = 'Qualification',
			CloseDate = Date.today().addDays(30),
			Product_Line__c = 'Flat FX',
			ProjectName__c = 'Hilton Tower',
			Project_State__c = 'Hawaii',
			Project_Wattage_kW__c = 449.6,
			Active_Revision_Number__c = REV_00
		);
	}

	// --- Pure helpers -------------------------------------------------------

	@IsTest
	static void getProductLineCode_mapsProductLineAndHandlesUnknowns() {
		Assert.areEqual('FX', ProjectCodeService.getProductLineCode('Flat FX'));
		Assert.areEqual('GB', ProjectCodeService.getProductLineCode('G-Base'));
		Assert.isNull(ProjectCodeService.getProductLineCode('Not A Product Line'));
		Assert.isNull(ProjectCodeService.getProductLineCode(null));
		Assert.isNull(ProjectCodeService.getProductLineCode(''));
	}

	@IsTest
	static void getShortName_stripsWhitespaceUppercasesAndTruncatesToFive() {
		Assert.areEqual('HILTO', ProjectCodeService.getShortName('Hilton Tower'));
		Assert.areEqual('ABC', ProjectCodeService.getShortName('abc'));
		Assert.areEqual('MARKE', ProjectCodeService.getShortName('  Market Place  '));
		Assert.areEqual('TE30A', ProjectCodeService.getShortName('TE 30 AA'), 'Internal spaces are removed before truncating');
		Assert.areEqual('ABCD', ProjectCodeService.getShortName('a b c d'), 'Whitespace-only gaps do not count toward the 5 chars');
		Assert.isNull(ProjectCodeService.getShortName(null));
		Assert.isNull(ProjectCodeService.getShortName('   '));
	}

	@IsTest
	static void buildCode_assemblesAllSegmentsAndRoundsHalfUp() {
		Assert.areEqual('FX-HILTO-HI-450-R00', ProjectCodeService.buildCode('FX', 'HILTO', 'HI', 449.6, REV_00));
		Assert.areEqual('FX-HILTO-HI-450-R01', ProjectCodeService.buildCode('FX', 'HILTO', 'HI', 449.5, REV_01));
		Assert.areEqual('FX-HILTO-HI-449-R00', ProjectCodeService.buildCode('FX', 'HILTO', 'HI', 449.4, REV_00));
		Assert.areEqual('FX-HILTO-HI-1877-R00', ProjectCodeService.buildCode('FX', 'HILTO', 'HI', 1876.68, REV_00));
	}

	@IsTest
	static void buildCode_returnsNullWhenAnySegmentMissing() {
		Assert.isNull(ProjectCodeService.buildCode(null, 'HILTO', 'HI', 450, REV_00), 'missing TT');
		Assert.isNull(ProjectCodeService.buildCode('FX', null, 'HI', 450, REV_00), 'missing PPPPP');
		Assert.isNull(ProjectCodeService.buildCode('FX', 'HILTO', null, 450, REV_00), 'missing SS');
		Assert.isNull(ProjectCodeService.buildCode('FX', 'HILTO', 'HI', null, REV_00), 'missing kW');
		Assert.isNull(ProjectCodeService.buildCode('FX', 'HILTO', 'HI', 0, REV_00), 'zero kW');
		Assert.isNull(ProjectCodeService.buildCode('FX', 'HILTO', 'HI', -5, REV_00), 'negative kW');
		Assert.isNull(ProjectCodeService.buildCode('FX', 'HILTO', 'HI', 450, null), 'missing revision');
		Assert.isNull(ProjectCodeService.buildCode('FX', 'HILTO', 'HI', 450, '  '), 'blank revision');
	}

	// --- Trigger integration ------------------------------------------------

	@IsTest
	static void insert_assemblesFullCodeWhenAllSegmentsPresent() {
		disableOutboundIntegration();
		Opportunity opp = buildOpportunity('Hilton Insert');

		Test.startTest();
		insert opp;
		Test.stopTest();

		opp = [
			SELECT Project_Code__c, Product_Line_Code__c, Short_Project_Name__c, Project_State_Code__c
			FROM Opportunity
			WHERE Id = :opp.Id
		];
		Assert.areEqual('FX', opp.Product_Line_Code__c);
		Assert.areEqual('HILTO', opp.Short_Project_Name__c);
		Assert.areEqual('HI', opp.Project_State_Code__c);
		Assert.areEqual('FX-HILTO-HI-450-R00', opp.Project_Code__c);
	}

	@IsTest
	static void insert_leavesCodeBlankWhenNoActiveRevision() {
		disableOutboundIntegration();
		Opportunity opp = buildOpportunity('No Revision');
		opp.Active_Revision_Number__c = null;

		Test.startTest();
		insert opp;
		Test.stopTest();

		opp = [SELECT Project_Code__c, Product_Line_Code__c FROM Opportunity WHERE Id = :opp.Id];
		Assert.areEqual('FX', opp.Product_Line_Code__c, 'Segment fields still populate');
		Assert.isNull(opp.Project_Code__c, 'Whole code stays blank until a Design Revision is active');
	}

	@IsTest
	static void insert_preservesManualShortNameOverride() {
		disableOutboundIntegration();
		Opportunity opp = buildOpportunity('Manual Short');
		opp.Short_Project_Name__c = 'CUST';

		Test.startTest();
		insert opp;
		Test.stopTest();

		opp = [SELECT Project_Code__c, Short_Project_Name__c FROM Opportunity WHERE Id = :opp.Id];
		Assert.areEqual('CUST', opp.Short_Project_Name__c, 'Manually entered short name is preserved');
		Assert.areEqual('FX-CUST-HI-450-R00', opp.Project_Code__c);
	}

	@IsTest
	static void insert_overwritesManuallySuppliedProductLineCode() {
		disableOutboundIntegration();
		Opportunity opp = buildOpportunity('Manual PLCode');
		opp.Product_Line_Code__c = 'SN'; // manual value must not survive

		Test.startTest();
		insert opp;
		Test.stopTest();

		opp = [SELECT Product_Line_Code__c FROM Opportunity WHERE Id = :opp.Id];
		Assert.areEqual('FX', opp.Product_Line_Code__c, 'Product Line Code is always re-derived from Product Line');
	}

	@IsTest
	static void update_recomputesCodeWhenSourceFieldChanges() {
		disableOutboundIntegration();
		Opportunity opp = buildOpportunity('Recompute');
		insert opp;

		Test.startTest();
		opp.Project_Wattage_kW__c = 1000;
		opp.Product_Line__c = 'G-Base';
		opp.Active_Revision_Number__c = REV_01;
		update opp;
		Test.stopTest();

		opp = [SELECT Project_Code__c FROM Opportunity WHERE Id = :opp.Id];
		Assert.areEqual('GB-HILTO-HI-1000-R01', opp.Project_Code__c);
	}

	@IsTest
	static void update_reDerivesShortNameWhenProjectNameChanges() {
		disableOutboundIntegration();
		Opportunity opp = buildOpportunity('Renamed Project');
		insert opp;

		Test.startTest();
		opp.ProjectName__c = 'Market Place';
		update opp;
		Test.stopTest();

		opp = [SELECT Project_Code__c, Short_Project_Name__c FROM Opportunity WHERE Id = :opp.Id];
		Assert.areEqual('MARKE', opp.Short_Project_Name__c, 'Short name follows a changed project name');
		Assert.areEqual('FX-MARKE-HI-450-R00', opp.Project_Code__c);
	}

	@IsTest
	static void update_freezesCodeAfterOpportunityIsWon() {
		disableOutboundIntegration();
		Opportunity opp = buildOpportunity('Freeze');
		insert opp;

		// Winning update still recomputes (old record was not yet won).
		opp.StageName = 'Closed Won';
		update opp;
		String wonCode = [SELECT Project_Code__c FROM Opportunity WHERE Id = :opp.Id].Project_Code__c;
		Assert.areEqual('FX-HILTO-HI-450-R00', wonCode);

		Test.startTest();
		// Post-win change must NOT alter the frozen code.
		opp.Project_Wattage_kW__c = 9999;
		opp.Active_Revision_Number__c = REV_01;
		update opp;
		Test.stopTest();

		Opportunity frozen = [SELECT Project_Code__c, Project_Wattage_kW__c FROM Opportunity WHERE Id = :opp.Id];
		Assert.areEqual(9999, frozen.Project_Wattage_kW__c, 'Wattage still updates');
		Assert.areEqual(wonCode, frozen.Project_Code__c, 'Project code is frozen once the Opportunity is Won');
	}

	// --- Design Revision driven -------------------------------------------

	@IsTest
	static void activateRevision_rebuildsCodeFromTheActiveRevision() {
		disableOutboundIntegration();
		Opportunity opp = buildOpportunity('Activation');
		opp.Active_Revision_Number__c = null;
		insert opp;
		Assert.isNull(
			[SELECT Project_Code__c FROM Opportunity WHERE Id = :opp.Id].Project_Code__c,
			'No code before a revision is active'
		);

		Design_Revision__c rev = new Design_Revision__c(
			Opportunity__c = opp.Id,
			Revision_Number__c = REV_01,
			Revision_Reason__c = '--',
			Product_Line__c = 'SN2',
			ProjectName__c = 'Market Place',
			Project_Wattage_kW__c = 1200.4
		);
		insert rev;

		Test.startTest();
		rev.Is_Active__c = true;
		update rev;
		Test.stopTest();

		Opportunity result = [
			SELECT Project_Code__c, Active_Revision_Number__c, Product_Line_Code__c, Short_Project_Name__c
			FROM Opportunity
			WHERE Id = :opp.Id
		];
		Assert.areEqual(REV_01, result.Active_Revision_Number__c, 'Revision number is mirrored from the active revision');
		Assert.areEqual('SN', result.Product_Line_Code__c);
		Assert.areEqual('MARKE', result.Short_Project_Name__c);
		Assert.areEqual('SN-MARKE-HI-1200-R01', result.Project_Code__c);
	}

	@IsTest
	static void revisionNumberChangeOnActiveRevision_updatesCode() {
		disableOutboundIntegration();
		Opportunity opp = buildOpportunity('Renumber');
		insert opp;

		Design_Revision__c rev = new Design_Revision__c(
			Opportunity__c = opp.Id,
			Revision_Number__c = REV_00,
			Revision_Reason__c = '--',
			Product_Line__c = 'Flat FX',
			ProjectName__c = 'Hilton Tower',
			Project_Wattage_kW__c = 449.6
		);
		insert rev;
		rev.Is_Active__c = true;
		update rev;

		Test.startTest();
		rev.Revision_Number__c = REV_01;
		update rev;
		Test.stopTest();

		Opportunity result = [SELECT Project_Code__c, Active_Revision_Number__c FROM Opportunity WHERE Id = :opp.Id];
		Assert.areEqual(REV_01, result.Active_Revision_Number__c);
		Assert.areEqual('FX-HILTO-HI-450-R01', result.Project_Code__c);
	}

	@IsTest
	static void bulk_insertAssemblesCodesFor200Records() {
		disableOutboundIntegration();
		List<Opportunity> opps = new List<Opportunity>();
		for (Integer i = 0; i < 200; i++) {
			opps.add(buildOpportunity('PCS Bulk ' + i));
		}

		Test.startTest();
		insert opps;
		Test.stopTest();

		Integer coded = 0;
		for (Opportunity opp : [SELECT Project_Code__c FROM Opportunity WHERE Id IN :opps]) {
			if (opp.Project_Code__c == 'FX-HILTO-HI-450-R00') coded++;
		}
		Assert.areEqual(200, coded);
	}
}
