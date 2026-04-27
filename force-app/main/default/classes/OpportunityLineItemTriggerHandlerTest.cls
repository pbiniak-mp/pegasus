@IsTest
private class OpportunityLineItemTriggerHandlerTest {

	private static final String PROD_WITH_DESC = 'OLI Product With Description';
	private static final String PROD_WITHOUT_DESC = 'OLI Product Without Description';
	private static final String PROD_BLANK_DESC = 'OLI Product Blank Description';
	private static final String DESC_VALUE = 'Standard product description text';
	private static final Integer BULK_SIZE = 200;

	@TestSetup
	static void setup() {
		Id pricebookId = Test.getStandardPricebookId();

		Account acc = new Account(Name = 'OLI Test Account');
		insert acc;

		Opportunity opp = new Opportunity(
			Name = 'OLI Test Opportunity',
			AccountId = acc.Id,
			StageName = 'Qualification',
			CloseDate = Date.today().addDays(30),
			Pricebook2Id = pricebookId
		);
		insert opp;

		Product2 productWithDesc = new Product2(Name = PROD_WITH_DESC, Description = DESC_VALUE, IsActive = true);
		Product2 productWithoutDesc = new Product2(Name = PROD_WITHOUT_DESC, IsActive = true);
		Product2 productBlankDesc = new Product2(Name = PROD_BLANK_DESC, Description = '   ', IsActive = true);
		insert new List<Product2>{ productWithDesc, productWithoutDesc, productBlankDesc };

		insert new List<PricebookEntry>{
			new PricebookEntry(Pricebook2Id = pricebookId, Product2Id = productWithDesc.Id, UnitPrice = 50, IsActive = true),
			new PricebookEntry(Pricebook2Id = pricebookId, Product2Id = productWithoutDesc.Id, UnitPrice = 60, IsActive = true),
			new PricebookEntry(Pricebook2Id = pricebookId, Product2Id = productBlankDesc.Id, UnitPrice = 70, IsActive = true)
		};
	}

	private static Opportunity getOpportunity() {
		return [SELECT Id FROM Opportunity LIMIT 1];
	}

	private static PricebookEntry getEntry(String productName) {
		return [SELECT Id, Product2Id FROM PricebookEntry WHERE Product2.Name = :productName LIMIT 1];
	}

	@IsTest
	static void testBeforeInsert_copiesDescriptionFromProduct() {
		Opportunity opp = getOpportunity();
		PricebookEntry pbe = getEntry(PROD_WITH_DESC);

		OpportunityLineItem oli = new OpportunityLineItem(
			OpportunityId = opp.Id,
			PricebookEntryId = pbe.Id,
			Quantity = 1,
			UnitPrice = 50
		);

		Test.startTest();
		insert oli;
		Test.stopTest();

		OpportunityLineItem reloaded = [SELECT Description FROM OpportunityLineItem WHERE Id = :oli.Id];
		Assert.areEqual(DESC_VALUE, reloaded.Description, 'Description should be copied from Product2');
	}

	@IsTest
	static void testBeforeInsert_productHasNoDescription_leavesDescriptionEmpty() {
		Opportunity opp = getOpportunity();
		PricebookEntry pbe = getEntry(PROD_WITHOUT_DESC);

		OpportunityLineItem oli = new OpportunityLineItem(
			OpportunityId = opp.Id,
			PricebookEntryId = pbe.Id,
			Quantity = 1,
			UnitPrice = 60
		);

		Test.startTest();
		insert oli;
		Test.stopTest();

		OpportunityLineItem reloaded = [SELECT Description FROM OpportunityLineItem WHERE Id = :oli.Id];
		Assert.isTrue(String.isBlank(reloaded.Description), 'Description should remain empty when Product2.Description is null');
	}

	@IsTest
	static void testBeforeInsert_overwritesManualDescriptionWhenProductHasValue() {
		Opportunity opp = getOpportunity();
		PricebookEntry pbe = getEntry(PROD_WITH_DESC);

		OpportunityLineItem oli = new OpportunityLineItem(
			OpportunityId = opp.Id,
			PricebookEntryId = pbe.Id,
			Quantity = 1,
			UnitPrice = 50,
			Description = 'Manual override'
		);

		Test.startTest();
		insert oli;
		Test.stopTest();

		OpportunityLineItem reloaded = [SELECT Description FROM OpportunityLineItem WHERE Id = :oli.Id];
		Assert.areEqual(DESC_VALUE, reloaded.Description, 'Product description should overwrite manual entry on insert');
	}

	@IsTest
	static void testBeforeInsert_lines_appliesToAllRecords() {
		Opportunity opp = getOpportunity();
		PricebookEntry pbeWithDesc = getEntry(PROD_WITH_DESC);
		PricebookEntry pbeWithoutDesc = getEntry(PROD_WITHOUT_DESC);

		List<OpportunityLineItem> lines = new List<OpportunityLineItem>();
		for (Integer i = 0; i < BULK_SIZE; i++) {
			Id entryId = Math.mod(i, 2) == 0 ? pbeWithDesc.Id : pbeWithoutDesc.Id;
			Decimal price = Math.mod(i, 2) == 0 ? 50 : 60;
			lines.add(new OpportunityLineItem(
				OpportunityId = opp.Id,
				PricebookEntryId = entryId,
				Quantity = 1,
				UnitPrice = price
			));
		}

		Test.startTest();
		insert lines;
		Test.stopTest();

		List<OpportunityLineItem> reloaded = [
			SELECT Description, PricebookEntryId
			FROM OpportunityLineItem
			WHERE Id IN :lines
		];
		Assert.areEqual(BULK_SIZE, reloaded.size());

		Integer copied = 0;
		Integer empty = 0;
		for (OpportunityLineItem oli : reloaded) {
			if (oli.PricebookEntryId == pbeWithDesc.Id) {
				Assert.areEqual(DESC_VALUE, oli.Description);
				copied++;
			} else {
				Assert.isTrue(String.isBlank(oli.Description));
				empty++;
			}
		}
		Assert.areEqual(BULK_SIZE / 2, copied);
		Assert.areEqual(BULK_SIZE / 2, empty);
	}

	@IsTest
	static void testService_emptyList_doesNothing() {
		Test.startTest();
		OpportunityLineItemService.populateLineDescriptions(new List<OpportunityLineItem>());
		Test.stopTest();
	}

	@IsTest
	static void testService_nullPricebookEntry_skipsRecord() {
		List<OpportunityLineItem> records = new List<OpportunityLineItem>{
			new OpportunityLineItem(PricebookEntryId = null, Quantity = 1, UnitPrice = 10)
		};

		Test.startTest();
		OpportunityLineItemService.populateLineDescriptions(records);
		Test.stopTest();

		Assert.isTrue(String.isBlank(records[0].Description));
	}
}
