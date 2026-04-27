@IsTest
private class QuoteLineItemTriggerHandlerTest {

	private static final String PROD_WITH_DESC = 'QLI Product With Description';
	private static final String PROD_WITHOUT_DESC = 'QLI Product Without Description';
	private static final String PROD_BLANK_DESC = 'QLI Product Blank Description';
	private static final String DESC_VALUE = 'Quote line product description';
	private static final Integer BULK_SIZE = 200;

	@TestSetup
	static void setup() {
		Id pricebookId = Test.getStandardPricebookId();

		Account acc = new Account(Name = 'QLI Test Account');
		insert acc;

		Opportunity opp = new Opportunity(
			Name = 'QLI Test Opportunity',
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

		Quote quote = new Quote(
			Name = 'QLI Test Quote',
			OpportunityId = opp.Id,
			Pricebook2Id = pricebookId,
			ExpirationDate = Date.today().addDays(30),
			Quote_Type__c = 'Material'
		);
		insert quote;
	}

	private static Quote getQuote() {
		return [SELECT Id FROM Quote LIMIT 1];
	}

	private static PricebookEntry getEntry(String productName) {
		return [SELECT Id, Product2Id FROM PricebookEntry WHERE Product2.Name = :productName LIMIT 1];
	}

	@IsTest
	static void testBeforeInsert_copiesDescriptionFromProduct() {
		Quote q = getQuote();
		PricebookEntry pbe = getEntry(PROD_WITH_DESC);

		QuoteLineItem qli = new QuoteLineItem(
			QuoteId = q.Id,
			Product2Id = pbe.Product2Id,
			PricebookEntryId = pbe.Id,
			Quantity = 1,
			UnitPrice = 50
		);

		Test.startTest();
		insert qli;
		Test.stopTest();

		QuoteLineItem reloaded = [SELECT Description FROM QuoteLineItem WHERE Id = :qli.Id];
		Assert.areEqual(DESC_VALUE, reloaded.Description, 'Description should be copied from Product2');
	}

	@IsTest
	static void testBeforeInsert_productHasNoDescription_leavesDescriptionEmpty() {
		Quote q = getQuote();
		PricebookEntry pbe = getEntry(PROD_WITHOUT_DESC);

		QuoteLineItem qli = new QuoteLineItem(
			QuoteId = q.Id,
			Product2Id = pbe.Product2Id,
			PricebookEntryId = pbe.Id,
			Quantity = 1,
			UnitPrice = 60
		);

		Test.startTest();
		insert qli;
		Test.stopTest();

		QuoteLineItem reloaded = [SELECT Description FROM QuoteLineItem WHERE Id = :qli.Id];
		Assert.isTrue(String.isBlank(reloaded.Description), 'Description should remain empty when Product2.Description is null');
	}

	@IsTest
	static void testBeforeInsert_productHasBlankDescription_doesNotOverwrite() {
		Quote q = getQuote();
		PricebookEntry pbe = getEntry(PROD_BLANK_DESC);

		QuoteLineItem qli = new QuoteLineItem(
			QuoteId = q.Id,
			Product2Id = pbe.Product2Id,
			PricebookEntryId = pbe.Id,
			Quantity = 1,
			UnitPrice = 70,
			Description = 'Manually entered description'
		);

		Test.startTest();
		insert qli;
		Test.stopTest();

		QuoteLineItem reloaded = [SELECT Description FROM QuoteLineItem WHERE Id = :qli.Id];
		Assert.areEqual('Manually entered description', reloaded.Description, 'Manual description should be preserved when product description is blank');
	}

	@IsTest
	static void testBeforeInsert_overwritesManualDescriptionWhenProductHasValue() {
		Quote q = getQuote();
		PricebookEntry pbe = getEntry(PROD_WITH_DESC);

		QuoteLineItem qli = new QuoteLineItem(
			QuoteId = q.Id,
			Product2Id = pbe.Product2Id,
			PricebookEntryId = pbe.Id,
			Quantity = 1,
			UnitPrice = 50,
			Description = 'Manual override'
		);

		Test.startTest();
		insert qli;
		Test.stopTest();

		QuoteLineItem reloaded = [SELECT Description FROM QuoteLineItem WHERE Id = :qli.Id];
		Assert.areEqual(DESC_VALUE, reloaded.Description, 'Product description should overwrite manual entry on insert');
	}

	@IsTest
	static void testBeforeInsert_lines_appliesToAllRecords() {
		Quote q = getQuote();
		PricebookEntry pbeWithDesc = getEntry(PROD_WITH_DESC);
		PricebookEntry pbeWithoutDesc = getEntry(PROD_WITHOUT_DESC);

		List<QuoteLineItem> lines = new List<QuoteLineItem>();
		for (Integer i = 0; i < BULK_SIZE; i++) {
			PricebookEntry source = Math.mod(i, 2) == 0 ? pbeWithDesc : pbeWithoutDesc;
			Decimal price = Math.mod(i, 2) == 0 ? 50 : 60;
			lines.add(new QuoteLineItem(
				QuoteId = q.Id,
				Product2Id = source.Product2Id,
				PricebookEntryId = source.Id,
				Quantity = 1,
				UnitPrice = price
			));
		}

		Test.startTest();
		insert lines;
		Test.stopTest();

		List<QuoteLineItem> reloaded = [
			SELECT Description, PricebookEntryId
			FROM QuoteLineItem
			WHERE Id IN :lines
		];
		Assert.areEqual(BULK_SIZE, reloaded.size());

		Integer copied = 0;
		Integer empty = 0;
		for (QuoteLineItem qli : reloaded) {
			if (qli.PricebookEntryId == pbeWithDesc.Id) {
				Assert.areEqual(DESC_VALUE, qli.Description);
				copied++;
			} else {
				Assert.isTrue(String.isBlank(qli.Description));
				empty++;
			}
		}
		Assert.areEqual(BULK_SIZE / 2, copied);
		Assert.areEqual(BULK_SIZE / 2, empty);
	}

	@IsTest
	static void testBeforeInsert_handlerBypassed_skipsLogic() {
		Quote q = getQuote();
		PricebookEntry pbe = getEntry(PROD_WITH_DESC);

		Test.startTest();
		TriggerHandler.bypass(Constants.QUOTE_LINE_ITEM_HANDLER_NAME);
		QuoteLineItem qli = new QuoteLineItem(
			QuoteId = q.Id,
			Product2Id = pbe.Product2Id,
			PricebookEntryId = pbe.Id,
			Quantity = 1,
			UnitPrice = 50
		);
		insert qli;
		TriggerHandler.clearBypass(Constants.QUOTE_LINE_ITEM_HANDLER_NAME);
		Test.stopTest();

		QuoteLineItem reloaded = [SELECT Description FROM QuoteLineItem WHERE Id = :qli.Id];
		Assert.isTrue(String.isBlank(reloaded.Description), 'Bypassed handler should not copy description');
	}

	@IsTest
	static void testService_emptyList_doesNothing() {
		Test.startTest();
		QuoteLineItemService.populateLineDescriptions(new List<QuoteLineItem>());
		Test.stopTest();
	}

	@IsTest
	static void testService_nullPricebookEntry_skipsRecord() {
		List<QuoteLineItem> records = new List<QuoteLineItem>{
			new QuoteLineItem(PricebookEntryId = null, Quantity = 1, UnitPrice = 10)
		};

		Test.startTest();
		QuoteLineItemService.populateLineDescriptions(records);
		Test.stopTest();

		Assert.isTrue(String.isBlank(records[0].Description));
	}
}
