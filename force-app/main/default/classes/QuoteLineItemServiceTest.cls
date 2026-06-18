@IsTest
private class QuoteLineItemServiceTest {

	private static final Decimal PRODUCT_WEIGHT = 12.5;
	private static final Decimal QLI_QUANTITY = 4;
	// Line_Weight__c = Weight__c * Quantity = 12.5 * 4 = 50 per line
	private static final Decimal EXPECTED_LINE_WEIGHT = 50;

	@TestSetup
	static void setup() {
		Account acc = new Account(Name = 'QLIW Account');
		insert acc;

		Opportunity opp = new Opportunity(
			Name = 'QLIW Opportunity',
			AccountId = acc.Id,
			StageName = 'Qualification',
			CloseDate = Date.today().addDays(30),
			Pricebook2Id = Test.getStandardPricebookId()
		);
		insert opp;

		insert new Quote_Sequence__c(
			SetupOwnerId = UserInfo.getOrganizationId(),
			Last_Number__c = 1000
		);
	}

	private static Id getOpportunityId() {
		return [SELECT Id FROM Opportunity LIMIT 1].Id;
	}

	private static Quote insertQuote() {
		Quote q = new Quote(
			Name = 'QLIW Quote',
			OpportunityId = getOpportunityId(),
			Pricebook2Id = Test.getStandardPricebookId(),
			ExpirationDate = Date.today().addDays(30),
			Quote_Type__c = 'Material'
		);
		insert q;
		return q;
	}

	private static List<QuoteLineItem> addLineItems(Id quoteId, Integer count) {
		Product2 product = new Product2(
			Name = 'QLIW Product ' + Crypto.getRandomLong(),
			Weight__c = PRODUCT_WEIGHT,
			IsActive = true
		);
		insert product;

		PricebookEntry pbe = new PricebookEntry(
			Pricebook2Id = Test.getStandardPricebookId(),
			Product2Id = product.Id,
			UnitPrice = 100,
			IsActive = true
		);
		insert pbe;

		List<QuoteLineItem> qlis = new List<QuoteLineItem>();
		for (Integer i = 0; i < count; i++) {
			qlis.add(new QuoteLineItem(
				QuoteId = quoteId,
				PricebookEntryId = pbe.Id,
				Product2Id = product.Id,
				Quantity = QLI_QUANTITY,
				UnitPrice = 100
			));
		}
		insert qlis;
		return qlis;
	}

	private static Decimal getTotalWeight(Id quoteId) {
		return [SELECT Total_Weight__c FROM Quote WHERE Id = :quoteId].Total_Weight__c;
	}

	@IsTest
	static void testInsertLineItems_sumsTotalWeightOntoQuote() {
		Quote q = insertQuote();

		Test.startTest();
		addLineItems(q.Id, 3);
		Test.stopTest();

		Assert.areEqual(EXPECTED_LINE_WEIGHT * 3, getTotalWeight(q.Id),
			'Total_Weight__c should equal the sum of Line_Weight__c across all QLI');
	}

	@IsTest
	static void testDeleteAllLineItems_setsTotalWeightToZeroNotNull() {
		Quote q = insertQuote();
		List<QuoteLineItem> qlis = addLineItems(q.Id, 2);

		Test.startTest();
		delete qlis;
		Test.stopTest();

		Assert.areEqual(0, getTotalWeight(q.Id),
			'A Quote with no remaining QLI should have Total_Weight__c = 0, not null');
	}

	@IsTest
	static void testUpdateLineItemQuantity_recalculatesTotalWeight() {
		Quote q = insertQuote();
		List<QuoteLineItem> qlis = addLineItems(q.Id, 1);

		Test.startTest();
		qlis[0].Quantity = QLI_QUANTITY * 2;
		update qlis;
		Test.stopTest();

		Assert.areEqual(EXPECTED_LINE_WEIGHT * 2, getTotalWeight(q.Id),
			'Total_Weight__c should reflect the updated quantity');
	}

	@IsTest
	static void testUndeleteLineItems_recalculatesTotalWeight() {
		Quote q = insertQuote();
		List<QuoteLineItem> qlis = addLineItems(q.Id, 2);
		delete qlis;

		Test.startTest();
		undelete qlis;
		Test.stopTest();

		Assert.areEqual(EXPECTED_LINE_WEIGHT * 2, getTotalWeight(q.Id),
			'Undeleted QLI should be summed back into Total_Weight__c');
	}

	@IsTest
	static void testRecalculate_nullAndEmpty_isNoOp() {
		Test.startTest();
		QuoteLineItemService.recalculateQuoteTotalWeight(null);
		QuoteLineItemService.recalculateQuoteTotalWeight(new Set<Id>());
		QuoteLineItemService.recalculateQuoteTotalWeight(new Set<Id>{ null });
		Test.stopTest();
		// No DML, no exception expected.
	}

	@IsTest
	static void testRecalculate_bulkQuotes_eachQuoteGetsOwnSum() {
		List<Quote> quotes = new List<Quote>();
		for (Integer i = 0; i < 5; i++) {
			Quote q = insertQuote();
			addLineItems(q.Id, 2);
			quotes.add(q);
		}

		Set<Id> quoteIds = new Map<Id, Quote>(quotes).keySet();

		Test.startTest();
		QuoteLineItemService.recalculateQuoteTotalWeight(quoteIds);
		Test.stopTest();

		for (Quote q : quotes) {
			Assert.areEqual(EXPECTED_LINE_WEIGHT * 2, getTotalWeight(q.Id),
				'Each Quote should be summed independently in a bulk recalculation');
		}
	}

	@IsTest
	static void testApplyQuoteGlobalDiscount_skipsFixedPriceProductsOnInsert() {
		Id pricebookId = Test.getStandardPricebookId();

		Quote q = new Quote(
			Name = 'QLIW Fixed Price Quote',
			OpportunityId = getOpportunityId(),
			Pricebook2Id = pricebookId,
			ExpirationDate = Date.today().addDays(30),
			Quote_Type__c = 'Material',
			Global_Discount__c = 50
		);
		insert q;

		Product2 normalProduct = new Product2(Name = 'QLIW Normal Product', IsActive = true);
		Product2 fixedProduct = new Product2(
			Name = 'QLIW Fixed Price Product',
			Family = Constants.PRODUCT_FAMILY_FIXED_PRICE,
			IsActive = true
		);
		insert new List<Product2>{ normalProduct, fixedProduct };

		PricebookEntry normalPbe = new PricebookEntry(
			Pricebook2Id = pricebookId, Product2Id = normalProduct.Id, UnitPrice = 100, IsActive = true
		);
		PricebookEntry fixedPbe = new PricebookEntry(
			Pricebook2Id = pricebookId, Product2Id = fixedProduct.Id, UnitPrice = 100, IsActive = true
		);
		insert new List<PricebookEntry>{ normalPbe, fixedPbe };

		Test.startTest();
		insert new List<QuoteLineItem>{
			new QuoteLineItem(QuoteId = q.Id, PricebookEntryId = normalPbe.Id, Product2Id = normalProduct.Id, Quantity = 2, UnitPrice = 100),
			new QuoteLineItem(QuoteId = q.Id, PricebookEntryId = fixedPbe.Id, Product2Id = fixedProduct.Id, Quantity = 2, UnitPrice = 100)
		};
		Test.stopTest();

		for (QuoteLineItem qli : [SELECT Discount, Product2.Family FROM QuoteLineItem WHERE QuoteId = :q.Id]) {
			if (qli.Product2.Family == Constants.PRODUCT_FAMILY_FIXED_PRICE) {
				Assert.isNull(qli.Discount, 'Fixed-price products must not inherit the Quote Global Discount on insert');
			} else {
				Assert.areEqual(50, qli.Discount, 'Non fixed-price products should inherit the Quote Global Discount on insert');
			}
		}
	}
}
