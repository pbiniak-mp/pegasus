@IsTest
private class ModuleCoverageServiceTest {

	private static final String PROD_A = 'MC Test Product A';
	private static final String PROD_B = 'MC Test Product B';

	@TestSetup
	static void setup() {
		Account acc = new Account(Name = 'MC Account');
		insert acc;

		Product2 prodA = new Product2(Name = PROD_A, IsActive = true);
		Product2 prodB = new Product2(Name = PROD_B, IsActive = true);
		insert new List<Product2>{ prodA, prodB };

		Id pricebookId = Test.getStandardPricebookId();
		PricebookEntry pbeA = new PricebookEntry(
			Pricebook2Id = pricebookId,
			Product2Id = prodA.Id,
			UnitPrice = 100,
			IsActive = true
		);
		insert pbeA;

		// Opp1: 500 W module, 100 kW project => Module Quantity = CEILING(100000 / 500) = 200
		// Opp2: 500 W module,  50 kW project => Module Quantity = CEILING( 50000 / 500) = 100
		Opportunity opp1 = newOpportunity('MC Opp 1', acc.Id, pricebookId, 100);
		Opportunity opp2 = newOpportunity('MC Opp 2', acc.Id, pricebookId, 50);
		insert new List<Opportunity>{ opp1, opp2 };

		// Product A ratios: 800 / 200 = 4 and 600 / 100 = 6  =>  average = 5
		insert new List<OpportunityLineItem>{
			new OpportunityLineItem(OpportunityId = opp1.Id, PricebookEntryId = pbeA.Id, Quantity = 800, UnitPrice = 100),
			new OpportunityLineItem(OpportunityId = opp2.Id, PricebookEntryId = pbeA.Id, Quantity = 600, UnitPrice = 100)
		};
	}

	private static Opportunity newOpportunity(String name, Id accountId, Id pricebookId, Decimal projectKw) {
		return new Opportunity(
			Name = name,
			AccountId = accountId,
			StageName = 'Qualification',
			CloseDate = Date.today().addDays(30),
			Pricebook2Id = pricebookId,
			Module_Wattage__c = '500',
			Project_Wattage_kW__c = projectKw
		);
	}

	private static List<Product2> productsForRecalc() {
		return [SELECT Id, Avg_SKU_Per_Module__c FROM Product2 ORDER BY Name];
	}

	private static Product2 getProduct(String name) {
		return [
			SELECT Id, Name, Avg_SKU_Per_Module__c, On_Hand__c, Committed__c, Available__c, Module_Coverage__c
			FROM Product2
			WHERE Name = :name
			LIMIT 1
		];
	}

	@IsTest
	static void testRecalculate_averagesRatioPerProduct_andLeavesEmptyProductNull() {
		Test.startTest();
		ModuleCoverageService.recalculateAverageSkuPerModule(productsForRecalc());
		Test.stopTest();

		Assert.areEqual(5, getProduct(PROD_A).Avg_SKU_Per_Module__c, 'Product A should average (4 + 6) / 2 = 5');
		Assert.isNull(getProduct(PROD_B).Avg_SKU_Per_Module__c, 'Product B has no line items and should stay null');
	}

	@IsTest
	static void testRecalculate_resetsStaleAverageToNull() {
		update new Product2(Id = getProduct(PROD_B).Id, Avg_SKU_Per_Module__c = 9);

		Test.startTest();
		ModuleCoverageService.recalculateAverageSkuPerModule(productsForRecalc());
		Test.stopTest();

		Assert.isNull(getProduct(PROD_B).Avg_SKU_Per_Module__c, 'Stale average should be cleared when no line items remain');
	}

	@IsTest
	static void testRecalculate_populatesModuleCoverageFormula() {
		update new Product2(Id = getProduct(PROD_A).Id, On_Hand__c = 800, Committed__c = 0);

		Test.startTest();
		ModuleCoverageService.recalculateAverageSkuPerModule(productsForRecalc());
		Test.stopTest();

		Product2 refreshed = getProduct(PROD_A);
		Assert.areEqual(5, refreshed.Avg_SKU_Per_Module__c, 'Average should be 5');
		Assert.areEqual(800, refreshed.Available__c, 'Available should be On Hand (800) minus Committed (0)');
		Assert.areEqual(160, refreshed.Module_Coverage__c, 'Module Coverage = Available 800 / Avg 5 = 160');
	}

	@IsTest
	static void testRecalculate_usesSingleSoqlAndSingleDml() {
		List<Product2> products = productsForRecalc();

		Test.startTest();
		Integer soqlBefore = Limits.getQueries();
		Integer dmlBefore = Limits.getDmlStatements();
		ModuleCoverageService.recalculateAverageSkuPerModule(products);
		Assert.areEqual(1, Limits.getQueries() - soqlBefore, 'Should issue exactly one aggregate SOQL');
		Assert.areEqual(1, Limits.getDmlStatements() - dmlBefore, 'Should issue exactly one DML (only the changed product)');
		Test.stopTest();
	}

	@IsTest
	static void testRecalculate_noValueChange_issuesNoDml() {
		// First pass writes the averages.
		ModuleCoverageService.recalculateAverageSkuPerModule(productsForRecalc());

		// Second pass over the now up-to-date values must change nothing.
		List<Product2> products = productsForRecalc();
		Test.startTest();
		Integer dmlBefore = Limits.getDmlStatements();
		ModuleCoverageService.recalculateAverageSkuPerModule(products);
		Assert.areEqual(0, Limits.getDmlStatements() - dmlBefore, 'No values changed, so no DML should be issued');
		Test.stopTest();
	}

	@IsTest
	static void testRecalculate_updateFailure_isLoggedAndRethrown() {
		// An Id whose record no longer exists forces the update to throw,
		// exercising the BoltErrorLogger / rethrow path.
		Product2 ghost = new Product2(Name = 'MC Ghost Product', IsActive = true);
		insert ghost;
		Id ghostId = ghost.Id;
		delete ghost;

		Boolean threw = false;
		Test.startTest();
		try {
			ModuleCoverageService.recalculateAverageSkuPerModule(new List<Product2>{
				new Product2(Id = ghostId, Avg_SKU_Per_Module__c = 5)
			});
		} catch (Exception e) {
			threw = true;
		}
		Test.stopTest();

		Assert.isTrue(threw, 'A failed update should be logged and rethrown');
	}

	@IsTest
	static void testRecalculate_nullList_isNoOp() {
		Test.startTest();
		Integer dmlBefore = Limits.getDmlStatements();
		ModuleCoverageService.recalculateAverageSkuPerModule(null);
		Assert.areEqual(dmlBefore, Limits.getDmlStatements(), 'Null list should not issue DML');
		Test.stopTest();
	}

	@IsTest
	static void testRecalculate_emptyList_isNoOp() {
		Test.startTest();
		Integer dmlBefore = Limits.getDmlStatements();
		ModuleCoverageService.recalculateAverageSkuPerModule(new List<Product2>());
		Assert.areEqual(dmlBefore, Limits.getDmlStatements(), 'Empty list should not issue DML');
		Test.stopTest();
	}
}
