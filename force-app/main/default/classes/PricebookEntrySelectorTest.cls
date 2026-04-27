@IsTest
private class PricebookEntrySelectorTest {

	private static final String PROD_NAME_A = 'PBE Selector Product A';
	private static final String PROD_NAME_B = 'PBE Selector Product B';
	private static final String DESC_A = 'Description for product A';

	@TestSetup
	static void setup() {
		Id pricebookId = Test.getStandardPricebookId();

		Product2 productA = new Product2(Name = PROD_NAME_A, Description = DESC_A, IsActive = true);
		Product2 productB = new Product2(Name = PROD_NAME_B, IsActive = true);
		insert new List<Product2>{ productA, productB };

		insert new List<PricebookEntry>{
			new PricebookEntry(Pricebook2Id = pricebookId, Product2Id = productA.Id, UnitPrice = 10, IsActive = true),
			new PricebookEntry(Pricebook2Id = pricebookId, Product2Id = productB.Id, UnitPrice = 20, IsActive = true)
		};
	}

	@IsTest
	static void testGetEntriesByIds_returnsAllRequestedEntries() {
		List<PricebookEntry> all = [SELECT Id FROM PricebookEntry];
		Set<Id> ids = new Map<Id, PricebookEntry>(all).keySet();

		Test.startTest();
		List<PricebookEntry> result = PricebookEntrySelector.getEntriesByIds(ids);
		Test.stopTest();

		Assert.areEqual(2, result.size(), 'Should return all matching entries');
	}

	@IsTest
	static void testGetEntriesByIds_loadsProductDescription() {
		PricebookEntry source = [
			SELECT Id FROM PricebookEntry WHERE Product2.Name = :PROD_NAME_A LIMIT 1
		];

		Test.startTest();
		List<PricebookEntry> result = PricebookEntrySelector.getEntriesByIds(new Set<Id>{ source.Id });
		Test.stopTest();

		Assert.areEqual(1, result.size());
		Assert.areEqual(DESC_A, result[0].Product2.Description, 'Description should be loaded via relationship');
	}

	@IsTest
	static void testGetEntriesByIds_emptyInput_returnsEmpty() {
		Test.startTest();
		List<PricebookEntry> result = PricebookEntrySelector.getEntriesByIds(new Set<Id>());
		Test.stopTest();

		Assert.areEqual(0, result.size());
	}

	@IsTest
	static void testGetEntryById_returnsRecord() {
		PricebookEntry source = [
			SELECT Id FROM PricebookEntry WHERE Product2.Name = :PROD_NAME_A LIMIT 1
		];

		Test.startTest();
		PricebookEntry result = PricebookEntrySelector.getEntryById(source.Id);
		Test.stopTest();

		Assert.areNotEqual(null, result);
		Assert.areEqual(source.Id, result.Id);
	}

	@IsTest
	static void testGetEntryById_unknownId_returnsNull() {
		Id fakeId = '01u000000000000AAA';

		Test.startTest();
		PricebookEntry result = PricebookEntrySelector.getEntryById(fakeId);
		Test.stopTest();

		Assert.areEqual(null, result);
	}
}
