@IsTest
private class ProjectCodeServiceTest {

	private static final String REV_00 = '00';
	private static final String REV_01 = '01';
	// Revision_Reason_Required blocks '--' on anything past REV 00.
	private static final String REV_REASON = 'Pegasus Revision';

	private static final String ACRONYM = 'GTR';
	private static final String ACCOUNT_WITH_ACRONYM = 'PCS Test Account';
	private static final String ACCOUNT_WITHOUT_ACRONYM = 'PCS Unknown Customer';

	private static Map<String, Id> cachedAccountIds;

	@TestSetup
	static void setup() {
		insert new List<Account>{
			new Account(Name = ACCOUNT_WITH_ACRONYM, Naming_Acronym__c = ACRONYM),
			new Account(Name = ACCOUNT_WITHOUT_ACRONYM)
		};
	}

	// The Closed Won flow creates an Order, which needs an Account on the Opportunity.
	private static Id accountId(String accountName) {
		if (cachedAccountIds == null) {
			cachedAccountIds = new Map<String, Id>();
			for (Account acc : [SELECT Id, Name FROM Account]) {
				cachedAccountIds.put(acc.Name, acc.Id);
			}
		}
		return cachedAccountIds.get(accountName);
	}

	// The outbound integration is irrelevant here; keep it off so the DML in
	// these tests never queues a callout.
	private static void disableOutboundIntegration() {
		GlideAnalyticsIntegrationService.configOverride = new Outbound_Integration__mdt(Active__c = false);
	}

	private static Opportunity buildOpportunity(String name) {
		return buildOpportunity(name, ACCOUNT_WITH_ACRONYM);
	}

	private static Opportunity buildOpportunity(String name, String accountName) {
		return new Opportunity(
			Name = name,
			AccountId = accountId(accountName),
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
	static void getShortName_stripsPunctuationUppercasesAndTruncatesToFive() {
		Assert.areEqual('HILTO', ProjectCodeService.getShortName('Hilton Tower'));
		Assert.areEqual('ABC', ProjectCodeService.getShortName('abc'));
		Assert.areEqual('MARKE', ProjectCodeService.getShortName('  Market Place  '));
		Assert.areEqual('TE30A', ProjectCodeService.getShortName('TE 30 AA'), 'Internal spaces are removed before truncating');
		Assert.areEqual('ABCD', ProjectCodeService.getShortName('a b c d'), 'Whitespace-only gaps do not count toward the 5 chars');
		Assert.isNull(ProjectCodeService.getShortName(null));
		Assert.isNull(ProjectCodeService.getShortName('   '));
		Assert.isNull(ProjectCodeService.getShortName('.-_'), 'Nothing alphanumeric left');
	}

	@IsTest
	static void getShortName_cleansTheNamesThatUsedToBreakTheCode() {
		// Real project names that produced unparseable codes before the sanitisation.
		Assert.areEqual('STLUK', ProjectCodeService.getShortName('ST. Lukes United Meth Ch AT Wi'));
		Assert.areEqual('STJUD', ProjectCodeService.getShortName('St. Jude of The Lake'));
		Assert.areEqual('0050C', ProjectCodeService.getShortName('0050. CannaGrow Solar'));
		Assert.areEqual('POPEJ', ProjectCodeService.getShortName('Pope_John_Paul'));
		Assert.areEqual('TXSYN', ProjectCodeService.getShortName('TX - Synergen Green Energy'));
		Assert.areEqual('603NS', ProjectCodeService.getShortName('603 - NSA EAST BANK APARTMENTS'));
		Assert.areEqual('6298S', ProjectCodeService.getShortName('6298-Shawnee Mission UN Church'));
	}

	@IsTest
	static void getShortName_isIdempotentSoItCanNormaliseAStoredValue() {
		Assert.areEqual('STLUK', ProjectCodeService.getShortName(ProjectCodeService.getShortName('ST. Lukes United')));
		Assert.areEqual('HILTO', ProjectCodeService.getShortName('HILTO'));
	}

	@IsTest
	static void buildCode_assemblesAllSegmentsAndRoundsHalfUp() {
		Assert.areEqual('GTR-FX-HILTO-00-HI-450', ProjectCodeService.buildCode(ACRONYM, 'FX', 'HILTO', REV_00, 'HI', 449.6));
		Assert.areEqual('GTR-FX-HILTO-01-HI-450', ProjectCodeService.buildCode(ACRONYM, 'FX', 'HILTO', REV_01, 'HI', 449.5));
		Assert.areEqual('GTR-FX-HILTO-00-HI-449', ProjectCodeService.buildCode(ACRONYM, 'FX', 'HILTO', REV_00, 'HI', 449.4));
		Assert.areEqual('GTR-FX-HILTO-00-HI-1877', ProjectCodeService.buildCode(ACRONYM, 'FX', 'HILTO', REV_00, 'HI', 1876.68));
	}

	@IsTest
	static void buildCode_returnsNullWhenAnySegmentMissing() {
		Assert.isNull(ProjectCodeService.buildCode(null, 'FX', 'HILTO', REV_00, 'HI', 450), 'missing CCC');
		Assert.isNull(ProjectCodeService.buildCode(ACRONYM, null, 'HILTO', REV_00, 'HI', 450), 'missing TT');
		Assert.isNull(ProjectCodeService.buildCode(ACRONYM, 'FX', null, REV_00, 'HI', 450), 'missing PPPPP');
		Assert.isNull(ProjectCodeService.buildCode(ACRONYM, 'FX', 'HILTO', null, 'HI', 450), 'missing revision');
		Assert.isNull(ProjectCodeService.buildCode(ACRONYM, 'FX', 'HILTO', '  ', 'HI', 450), 'blank revision');
		Assert.isNull(ProjectCodeService.buildCode(ACRONYM, 'FX', 'HILTO', REV_00, null, 450), 'missing SS');
		Assert.isNull(ProjectCodeService.buildCode(ACRONYM, 'FX', 'HILTO', REV_00, 'HI', null), 'missing kW');
		Assert.isNull(ProjectCodeService.buildCode(ACRONYM, 'FX', 'HILTO', REV_00, 'HI', 0), 'zero kW');
		Assert.isNull(ProjectCodeService.buildCode(ACRONYM, 'FX', 'HILTO', REV_00, 'HI', -5), 'negative kW');
	}

	@IsTest
	static void buildCode_stripsPunctuationFromEverySegment() {
		Assert.areEqual(
			'GTR-FX-STLU-01-HI-450',
			ProjectCodeService.buildCode('gt.r', 'FX', 'ST.LU', 'R-01', 'hi', 450),
			'No segment may smuggle a separator into the code'
		);
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
		Assert.areEqual('GTR-FX-HILTO-00-HI-450', opp.Project_Code__c);
	}

	@IsTest
	static void insert_leavesCodeBlankWhenAccountHasNoAcronym() {
		disableOutboundIntegration();
		Opportunity opp = buildOpportunity('No Acronym', ACCOUNT_WITHOUT_ACRONYM);

		Test.startTest();
		insert opp;
		Test.stopTest();

		opp = [SELECT Project_Code__c, Product_Line_Code__c FROM Opportunity WHERE Id = :opp.Id];
		Assert.areEqual('FX', opp.Product_Line_Code__c, 'Segment fields still populate');
		Assert.isNull(opp.Project_Code__c, 'Whole code stays blank until the customer has a Naming Acronym');
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
		Assert.areEqual('GTR-FX-CUST-00-HI-450', opp.Project_Code__c);
	}

	@IsTest
	static void insert_normalisesManualShortNameOverride() {
		disableOutboundIntegration();
		Opportunity opp = buildOpportunity('Dirty Manual Short');
		opp.Short_Project_Name__c = 'ST.LU';

		Test.startTest();
		insert opp;
		Test.stopTest();

		opp = [SELECT Project_Code__c, Short_Project_Name__c FROM Opportunity WHERE Id = :opp.Id];
		Assert.areEqual('STLU', opp.Short_Project_Name__c, 'A hand-typed override is stripped of punctuation too');
		Assert.areEqual('GTR-FX-STLU-00-HI-450', opp.Project_Code__c);
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
		Assert.areEqual('GTR-GB-HILTO-01-HI-1000', opp.Project_Code__c);
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
		Assert.areEqual('GTR-FX-MARKE-00-HI-450', opp.Project_Code__c);
	}

	@IsTest
	static void update_picksUpANewAcronymOnlyWhenTheOpportunityIsSaved() {
		disableOutboundIntegration();
		Opportunity opp = buildOpportunity('Recoded Customer');
		insert opp;

		Test.startTest();
		update new Account(Id = accountId(ACCOUNT_WITH_ACRONYM), Naming_Acronym__c = 'ABC');
		Assert.areEqual(
			'GTR-FX-HILTO-00-HI-450',
			[SELECT Project_Code__c FROM Opportunity WHERE Id = :opp.Id].Project_Code__c,
			'Recoding the Account does not reach the Opportunity on its own'
		);

		update opp;
		Test.stopTest();

		opp = [SELECT Project_Code__c FROM Opportunity WHERE Id = :opp.Id];
		Assert.areEqual('ABC-FX-HILTO-00-HI-450', opp.Project_Code__c, 'The next save picks the new acronym up');
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
		Assert.areEqual('GTR-FX-HILTO-00-HI-450', wonCode);

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
			Revision_Reason__c = REV_REASON,
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
		Assert.areEqual('GTR-SN-MARKE-01-HI-1200', result.Project_Code__c);
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
		rev.Revision_Reason__c = REV_REASON; // required once the revision moves past REV 00
		update rev;
		Test.stopTest();

		Opportunity result = [SELECT Project_Code__c, Active_Revision_Number__c FROM Opportunity WHERE Id = :opp.Id];
		Assert.areEqual(REV_01, result.Active_Revision_Number__c);
		Assert.areEqual('GTR-FX-HILTO-01-HI-450', result.Project_Code__c);
	}

	@IsTest
	static void bulk_insertAssemblesCodesFor200Records() {
		disableOutboundIntegration();
		List<Opportunity> opps = new List<Opportunity>();
		for (Integer i = 0; i < 200; i++) {
			opps.add(buildOpportunity('PCS Bulk ' + i));
		}

		Test.startTest();
		Integer queriesBefore = Limits.getQueries();
		insert opps;
		Integer queriesUsed = Limits.getQueries() - queriesBefore;
		Test.stopTest();

		Integer coded = 0;
		for (Opportunity opp : [SELECT Project_Code__c FROM Opportunity WHERE Id IN :opps]) {
			if (opp.Project_Code__c == 'GTR-FX-HILTO-00-HI-450') coded++;
		}
		Assert.areEqual(200, coded);
		Assert.isTrue(queriesUsed <= 5, 'Acronyms are read in one bulk query, not one per record (used ' + queriesUsed + ')');
	}
}
