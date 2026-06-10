@IsTest
private class ModuleCoverageBatchTest {

	private static final String PROD_A = 'MC Batch Product A';
	private static final String PROD_B = 'MC Batch Product B';

	@TestSetup
	static void setup() {
		Account acc = new Account(Name = 'MC Batch Account');
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

		// Opp1: 500 W, 100 kW => Module Quantity 200 ;  Opp2: 500 W, 50 kW => Module Quantity 100
		Opportunity opp1 = newOpportunity('MC Batch Opp 1', acc.Id, pricebookId, 100);
		Opportunity opp2 = newOpportunity('MC Batch Opp 2', acc.Id, pricebookId, 50);
		insert new List<Opportunity>{ opp1, opp2 };

		// Ratios 800 / 200 = 4 and 600 / 100 = 6  =>  average = 5
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

	private static Decimal avgFor(String name) {
		return [SELECT Avg_SKU_Per_Module__c FROM Product2 WHERE Name = :name LIMIT 1].Avg_SKU_Per_Module__c;
	}

	@IsTest
	static void testBatch_populatesAveragesAcrossCatalogue() {
		Test.startTest();
		Database.executeBatch(new ModuleCoverageBatch(), 200);
		Test.stopTest();

		Assert.areEqual(5, avgFor(PROD_A), 'Batch should set Product A average to 5');
		Assert.isNull(avgFor(PROD_B), 'Product B has no line items and should stay null');
	}

	@IsTest
	static void testScheduler_enqueuesBatchThatPopulatesAverages() {
		Test.startTest();
		new ModuleCoverageScheduler().execute(null);
		Test.stopTest();

		Assert.areEqual(5, avgFor(PROD_A), 'Scheduler should run the batch and set Product A average to 5');
	}
}
