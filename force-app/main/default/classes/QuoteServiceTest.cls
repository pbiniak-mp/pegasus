@IsTest
private class QuoteServiceTest {

	private static final Decimal INITIAL_SEQUENCE = 26099;
	private static final String FIRST_NUMBER = '26100';
	private static final String SECOND_NUMBER = '26101';
	private static final String THIRD_NUMBER = '26102';
	private static final Integer BULK_SIZE = 200;

	@TestSetup
	static void setup() {
		Account acc = new Account(Name = 'QS Test Account');
		insert acc;

		Opportunity opp = new Opportunity(
			Name = 'QS Test Opportunity',
			AccountId = acc.Id,
			StageName = 'Qualification',
			CloseDate = Date.today().addDays(30),
			Pricebook2Id = Test.getStandardPricebookId()
		);
		insert opp;

		insert new Quote_Sequence__c(
			SetupOwnerId = UserInfo.getOrganizationId(),
			Last_Number__c = INITIAL_SEQUENCE
		);
	}

	private static Id getOpportunityId() {
		return [SELECT Id FROM Opportunity LIMIT 1].Id;
	}

	private static Quote_Sequence__c getSequence() {
		return [
			SELECT Id, Last_Number__c
			FROM Quote_Sequence__c
			WHERE SetupOwnerId = :UserInfo.getOrganizationId()
			LIMIT 1
		];
	}

	private static List<Quote> insertQuotesBypassed(Integer count) {
		Id oppId = getOpportunityId();
		Id pricebookId = Test.getStandardPricebookId();
		List<Quote> quotes = new List<Quote>();
		for (Integer i = 0; i < count; i++) {
			quotes.add(new Quote(
				Name = 'QS Quote ' + i,
				OpportunityId = oppId,
				Pricebook2Id = pricebookId,
				ExpirationDate = Date.today().addDays(30),
				Quote_Type__c = 'Material'
			));
		}
		TriggerHandler.bypass(Constants.QUOTE_HANDLER_NAME);
		try {
			insert quotes;
		} finally {
			TriggerHandler.clearBypass(Constants.QUOTE_HANDLER_NAME);
		}
		return quotes;
	}

	// ── Service: direct calls ───────────────────────────────────────────

	@IsTest
	static void testAssignQuoteNumbers_singleQuote_assignsNextNumberAndIncrementsSequence() {
		List<Quote> quotes = insertQuotesBypassed(1);

		Test.startTest();
		QuoteService.assignQuoteNumbers(quotes);
		Test.stopTest();

		Quote reloaded = [SELECT Quote_Number__c FROM Quote WHERE Id = :quotes[0].Id];
		Assert.areEqual(FIRST_NUMBER, reloaded.Quote_Number__c);
		Assert.areEqual(26100, getSequence().Last_Number__c, 'Sequence should be incremented by 1');
	}

	@IsTest
	static void testAssignQuoteNumbers_bulk_assignsSequentialUniqueNumbers() {
		List<Quote> quotes = insertQuotesBypassed(3);

		Test.startTest();
		QuoteService.assignQuoteNumbers(quotes);
		Test.stopTest();

		List<Quote> reloaded = [SELECT Id, Quote_Number__c FROM Quote WHERE Id IN :quotes];
		Set<String> numbers = new Set<String>();
		for (Quote q : reloaded) {
			numbers.add(q.Quote_Number__c);
		}
		Assert.areEqual(3, numbers.size(), 'All 3 quotes should have unique numbers');
		Assert.isTrue(numbers.contains(FIRST_NUMBER));
		Assert.isTrue(numbers.contains(SECOND_NUMBER));
		Assert.isTrue(numbers.contains(THIRD_NUMBER));
		Assert.areEqual(26102, getSequence().Last_Number__c);
	}

	@IsTest
	static void testAssignQuoteNumbers_nullList_isNoOp() {
		Test.startTest();
		QuoteService.assignQuoteNumbers(null);
		Test.stopTest();

		Assert.areEqual(INITIAL_SEQUENCE, getSequence().Last_Number__c, 'Null list should not touch the sequence');
	}

	@IsTest
	static void testAssignQuoteNumbers_emptyList_isNoOp() {
		Test.startTest();
		QuoteService.assignQuoteNumbers(new List<Quote>());
		Test.stopTest();

		Assert.areEqual(INITIAL_SEQUENCE, getSequence().Last_Number__c, 'Empty list should not touch the sequence');
	}

	@IsTest
	static void testAssignQuoteNumbers_missingSequenceRecord_throwsException() {
		delete [SELECT Id FROM Quote_Sequence__c];
		List<Quote> quotes = insertQuotesBypassed(1);

		Test.startTest();
		Boolean threw = false;
		String message = null;
		try {
			QuoteService.assignQuoteNumbers(quotes);
		} catch (QuoteService.QuoteServiceException e) {
			threw = true;
			message = e.getMessage();
		}
		Test.stopTest();

		Assert.isTrue(threw, 'Expected QuoteServiceException when sequence record is missing');
		Assert.isTrue(message != null && message.contains('Quote_Sequence__c'), 'Exception should mention the missing setting');
	}

	@IsTest
	static void testAssignQuoteNumbers_nullLastNumber_startsFromOne() {
		Quote_Sequence__c seq = getSequence();
		seq.Last_Number__c = null;
		update seq;

		List<Quote> quotes = insertQuotesBypassed(1);

		Test.startTest();
		QuoteService.assignQuoteNumbers(quotes);
		Test.stopTest();

		Quote reloaded = [SELECT Quote_Number__c FROM Quote WHERE Id = :quotes[0].Id];
		Assert.areEqual('1', reloaded.Quote_Number__c, 'Null Last_Number__c should be treated as 0 and increment to 1');
		Assert.areEqual(1, getSequence().Last_Number__c);
	}

	@IsTest
	static void testAssignQuoteNumbers_sequentialCalls_doNotReuseNumbers() {
		List<Quote> firstBatch = insertQuotesBypassed(2);
		QuoteService.assignQuoteNumbers(firstBatch);

		List<Quote> secondBatch = insertQuotesBypassed(2);

		Test.startTest();
		QuoteService.assignQuoteNumbers(secondBatch);
		Test.stopTest();

		List<Quote> reloaded = [SELECT Quote_Number__c FROM Quote];
		Set<String> numbers = new Set<String>();
		for (Quote q : reloaded) {
			numbers.add(q.Quote_Number__c);
		}
		Assert.areEqual(4, numbers.size(), 'Numbers must not repeat across consecutive batches');
		Assert.isTrue(numbers.contains(FIRST_NUMBER));
		Assert.isTrue(numbers.contains(SECOND_NUMBER));
		Assert.isTrue(numbers.contains(THIRD_NUMBER));
		Assert.isTrue(numbers.contains('26103'));
	}

	// ── Trigger integration ─────────────────────────────────────────────

	@IsTest
	static void testTrigger_afterInsertSingleQuote_populatesQuoteNumber() {
		Quote q = new Quote(
			Name = 'Trigger Quote',
			OpportunityId = getOpportunityId(),
			Pricebook2Id = Test.getStandardPricebookId(),
			ExpirationDate = Date.today().addDays(30),
			Quote_Type__c = 'Material'
		);

		Test.startTest();
		insert q;
		Test.stopTest();

		Quote reloaded = [SELECT Quote_Number__c FROM Quote WHERE Id = :q.Id];
		Assert.areEqual(FIRST_NUMBER, reloaded.Quote_Number__c);
	}

	@IsTest
	static void testTrigger_bulkInsert_eachQuoteGetsUniqueNumber() {
		Id oppId = getOpportunityId();
		Id pricebookId = Test.getStandardPricebookId();
		List<Quote> quotes = new List<Quote>();
		for (Integer i = 0; i < BULK_SIZE; i++) {
			quotes.add(new Quote(
				Name = 'Bulk Quote ' + i,
				OpportunityId = oppId,
				Pricebook2Id = pricebookId,
				ExpirationDate = Date.today().addDays(30),
				Quote_Type__c = 'Material'
			));
		}

		Test.startTest();
		insert quotes;
		Test.stopTest();

		List<Quote> reloaded = [SELECT Quote_Number__c FROM Quote WHERE Id IN :quotes];
		Set<String> numbers = new Set<String>();
		for (Quote q : reloaded) {
			Assert.isNotNull(q.Quote_Number__c, 'Every quote must have a number');
			numbers.add(q.Quote_Number__c);
		}
		Assert.areEqual(BULK_SIZE, numbers.size(), 'Every quote in the bulk insert must have a unique number');
		Assert.areEqual(INITIAL_SEQUENCE + BULK_SIZE, getSequence().Last_Number__c);
	}

	@IsTest
	static void testTrigger_handlerBypassed_skipsAssignment() {
		Quote q = new Quote(
			Name = 'Bypassed Quote',
			OpportunityId = getOpportunityId(),
			Pricebook2Id = Test.getStandardPricebookId(),
			ExpirationDate = Date.today().addDays(30),
			Quote_Type__c = 'Material'
		);

		Test.startTest();
		TriggerHandler.bypass(Constants.QUOTE_HANDLER_NAME);
		try {
			insert q;
		} finally {
			TriggerHandler.clearBypass(Constants.QUOTE_HANDLER_NAME);
		}
		Test.stopTest();

		Quote reloaded = [SELECT Quote_Number__c FROM Quote WHERE Id = :q.Id];
		Assert.isTrue(String.isBlank(reloaded.Quote_Number__c), 'Bypassed handler should not assign a number');
		Assert.areEqual(INITIAL_SEQUENCE, getSequence().Last_Number__c, 'Bypassed handler should not move the sequence');
	}

	// ── Global Discount ─────────────────────────────────────────────────

	@IsTest
	static void testApplyGlobalDiscount_updatesAllQuoteLineItemDiscounts() {
		Id pricebookId = Test.getStandardPricebookId();
		Id oppId = getOpportunityId();

		Product2 product = new Product2(Name = 'GD Test Product', IsActive = true);
		insert product;

		PricebookEntry pbe = new PricebookEntry(
			Pricebook2Id = pricebookId,
			Product2Id = product.Id,
			UnitPrice = 100,
			IsActive = true
		);
		insert pbe;

		Quote q = new Quote(
			Name = 'Discount Quote',
			OpportunityId = oppId,
			Pricebook2Id = pricebookId,
			ExpirationDate = Date.today().addDays(30),
			Quote_Type__c = 'Material'
		);
		insert q;

		List<QuoteLineItem> qlis = new List<QuoteLineItem>();
		for (Integer i = 0; i < 3; i++) {
			qlis.add(new QuoteLineItem(
				QuoteId = q.Id,
				PricebookEntryId = pbe.Id,
				Product2Id = product.Id,
				Quantity = 2,
				UnitPrice = 100
			));
		}
		insert qlis;

		Test.startTest();
		q.Global_Discount__c = 50;
		update q;
		Test.stopTest();

		List<QuoteLineItem> reloaded = [SELECT Discount FROM QuoteLineItem WHERE QuoteId = :q.Id];
		Assert.areEqual(3, reloaded.size());
		for (QuoteLineItem qli : reloaded) {
			Assert.areEqual(50, qli.Discount, 'Each QLI Discount should match Global_Discount__c');
		}
	}

	@IsTest
	static void testApplyGlobalDiscount_zeroResetsLineItemDiscounts() {
		Id pricebookId = Test.getStandardPricebookId();
		Id oppId = getOpportunityId();

		Product2 product = new Product2(Name = 'GD Zero Product', IsActive = true);
		insert product;

		PricebookEntry pbe = new PricebookEntry(
			Pricebook2Id = pricebookId,
			Product2Id = product.Id,
			UnitPrice = 100,
			IsActive = true
		);
		insert pbe;

		Quote q = new Quote(
			Name = 'Zero Discount Quote',
			OpportunityId = oppId,
			Pricebook2Id = pricebookId,
			ExpirationDate = Date.today().addDays(30),
			Quote_Type__c = 'Material'
		);
		insert q;

		List<QuoteLineItem> qlis = new List<QuoteLineItem>();
		for (Integer i = 0; i < 3; i++) {
			qlis.add(new QuoteLineItem(
				QuoteId = q.Id,
				PricebookEntryId = pbe.Id,
				Product2Id = product.Id,
				Quantity = 2,
				UnitPrice = 100
			));
		}
		insert qlis;

		// First set a non-zero discount so there is something to reset.
		q.Global_Discount__c = 40;
		update q;
		for (QuoteLineItem qli : [SELECT Discount FROM QuoteLineItem WHERE QuoteId = :q.Id]) {
			Assert.areEqual(40, qli.Discount, 'Precondition: a positive Global Discount should propagate');
		}

		Test.startTest();
		q.Global_Discount__c = 0;
		update q;
		Test.stopTest();

		List<QuoteLineItem> reloaded = [SELECT Discount FROM QuoteLineItem WHERE QuoteId = :q.Id];
		Assert.areEqual(3, reloaded.size());
		for (QuoteLineItem qli : reloaded) {
			Assert.areEqual(0, qli.Discount, 'Setting Global Discount to 0 must reset every line item Discount to 0');
		}
	}

	@IsTest
	static void testApplyGlobalDiscount_skipsFixedPriceProducts() {
		Id pricebookId = Test.getStandardPricebookId();
		Id oppId = getOpportunityId();

		Product2 normalProduct = new Product2(Name = 'GD Normal Product', IsActive = true);
		Product2 fixedProduct = new Product2(
			Name = 'GD Fixed Price Product',
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

		Quote q = new Quote(
			Name = 'Fixed Price Discount Quote',
			OpportunityId = oppId,
			Pricebook2Id = pricebookId,
			ExpirationDate = Date.today().addDays(30),
			Quote_Type__c = 'Material'
		);
		insert q;

		insert new List<QuoteLineItem>{
			new QuoteLineItem(QuoteId = q.Id, PricebookEntryId = normalPbe.Id, Product2Id = normalProduct.Id, Quantity = 2, UnitPrice = 100),
			new QuoteLineItem(QuoteId = q.Id, PricebookEntryId = fixedPbe.Id, Product2Id = fixedProduct.Id, Quantity = 2, UnitPrice = 100)
		};

		Test.startTest();
		q.Global_Discount__c = 50;
		update q;
		Test.stopTest();

		for (QuoteLineItem qli : [SELECT Discount, Product2.Family FROM QuoteLineItem WHERE QuoteId = :q.Id]) {
			if (qli.Product2.Family == Constants.PRODUCT_FAMILY_FIXED_PRICE) {
				Assert.isNull(qli.Discount, 'Fixed-price products must not receive the Global Discount');
			} else {
				Assert.areEqual(50, qli.Discount, 'Non fixed-price products should receive the Global Discount');
			}
		}
	}

	@IsTest
	static void testApplyAccountDefaultDiscount_skipsStampType() {
		Account acc = [SELECT Id FROM Account LIMIT 1];
		update new Account(Id = acc.Id, Default_Discount__c = 25);
		Id oppId = getOpportunityId();
		Id pricebookId = Test.getStandardPricebookId();

		Quote material = new Quote(
			Name = 'Acct Material',
			OpportunityId = oppId,
			Pricebook2Id = pricebookId,
			ExpirationDate = Date.today().addDays(30),
			Quote_Type__c = 'Material'
		);
		Quote stamp = new Quote(
			Name = 'Acct Stamp',
			OpportunityId = oppId,
			Pricebook2Id = pricebookId,
			ExpirationDate = Date.today().addDays(30),
			Quote_Type__c = 'Stamp'
		);

		Test.startTest();
		insert new List<Quote>{ material, stamp };
		Test.stopTest();

		Quote reloadedMaterial = [SELECT Global_Discount__c FROM Quote WHERE Id = :material.Id];
		Quote reloadedStamp = [SELECT Global_Discount__c FROM Quote WHERE Id = :stamp.Id];
		Assert.areEqual(25, reloadedMaterial.Global_Discount__c,
			'Material Quote should inherit the Account default discount');
		Assert.isNull(reloadedStamp.Global_Discount__c,
			'Stamp Quote must NOT inherit the Account default discount');
	}

	@IsTest
	static void testTrigger_doesNotRecurse_internalUpdateBypassesHandler() {
		Quote q = new Quote(
			Name = 'Recursion Quote',
			OpportunityId = getOpportunityId(),
			Pricebook2Id = Test.getStandardPricebookId(),
			ExpirationDate = Date.today().addDays(30),
			Quote_Type__c = 'Material'
		);

		Test.startTest();
		insert q;
		Test.stopTest();

		Assert.areEqual(26100, getSequence().Last_Number__c, 'Sequence must advance exactly once per insert (no recursion)');
	}

	// ── Active__c lifecycle: manual activation, deactivation & delete ────

	private static final String TYPE_MATERIAL = 'Material';
	private static final String TYPE_STAMP = 'Stamp';
	private static final Decimal ACTIVE_WATTAGE_KW = 10;

	private static Design_Revision__c createRevision(Id oppId) {
		Design_Revision__c dr = new Design_Revision__c(
			Opportunity__c = oppId,
			Revision_Number__c = '00',
			Project_Wattage_kW__c = ACTIVE_WATTAGE_KW,
			Is_Active__c = false
		);
		insert dr;
		return dr;
	}

	private static Quote createQuoteViaTrigger(Id oppId, Id drId, String type) {
		Quote q = new Quote(
			Name = 'Q ' + type,
			OpportunityId = oppId,
			Pricebook2Id = Test.getStandardPricebookId(),
			ExpirationDate = Date.today().addDays(30),
			Quote_Type__c = type,
			Design_Revision__c = drId
		);
		insert q;
		return q;
	}

	private static void addLineItem(Id quoteId, Decimal total) {
		Id pbId = Test.getStandardPricebookId();
		List<PricebookEntry> pbes = [SELECT Id, Product2Id FROM PricebookEntry WHERE Pricebook2Id = :pbId LIMIT 1];
		PricebookEntry pbe;
		if (pbes.isEmpty()) {
			Product2 product = new Product2(Name = 'QS Active Product ' + Crypto.getRandomLong(), IsActive = true);
			insert product;
			pbe = new PricebookEntry(Pricebook2Id = pbId, Product2Id = product.Id, UnitPrice = 1, IsActive = true);
			insert pbe;
		} else {
			pbe = pbes[0];
		}
		insert new QuoteLineItem(
			QuoteId = quoteId,
			PricebookEntryId = pbe.Id,
			Product2Id = pbe.Product2Id,
			Quantity = 1,
			UnitPrice = total
		);
	}

	private static Boolean isActive(Id quoteId) {
		return [SELECT Active__c FROM Quote WHERE Id = :quoteId].Active__c;
	}

	@IsTest
	static void testManualActivation_deactivatesOthers() {
		Id oppId = getOpportunityId();
		Design_Revision__c dr = createRevision(oppId);
		Quote first = createQuoteViaTrigger(oppId, dr.Id, TYPE_MATERIAL);
		Quote second = createQuoteViaTrigger(oppId, dr.Id, TYPE_MATERIAL);

		Test.startTest();
		update new Quote(Id = second.Id, Active__c = true);
		Test.stopTest();

		Assert.isFalse(isActive(first.Id), 'Activating the second Quote must deactivate the first of the same type/DR');
		Assert.isTrue(isActive(second.Id), 'The newly activated Quote should be active');
	}

	@IsTest
	static void testManualActivation_doesNotAffectOtherTypes() {
		Id oppId = getOpportunityId();
		Design_Revision__c dr = createRevision(oppId);
		Quote material = createQuoteViaTrigger(oppId, dr.Id, TYPE_MATERIAL);
		Quote stampA = createQuoteViaTrigger(oppId, dr.Id, TYPE_STAMP);
		Quote stampB = createQuoteViaTrigger(oppId, dr.Id, TYPE_STAMP);

		Test.startTest();
		update new Quote(Id = stampB.Id, Active__c = true);
		Test.stopTest();

		Assert.isTrue(isActive(material.Id), 'Activating a Stamp Quote must not affect the Material Quote');
		Assert.isFalse(isActive(stampA.Id), 'The previously active Stamp Quote should be deactivated');
		Assert.isTrue(isActive(stampB.Id), 'The newly activated Stamp Quote should be active');
	}

	@IsTest
	static void testManualActivation_doesNotAffectOtherDRs() {
		Id oppId = getOpportunityId();
		Design_Revision__c dr1 = createRevision(oppId);
		Design_Revision__c dr2 = new Design_Revision__c(
			Opportunity__c = oppId,
			Revision_Number__c = '01',
			Revision_Reason__c = 'Customer Revision',
			Is_Active__c = false
		);
		insert dr2;

		Quote dr1First = createQuoteViaTrigger(oppId, dr1.Id, TYPE_MATERIAL);
		Quote dr1Second = createQuoteViaTrigger(oppId, dr1.Id, TYPE_MATERIAL);
		Quote dr2Quote = createQuoteViaTrigger(oppId, dr2.Id, TYPE_MATERIAL);

		Test.startTest();
		update new Quote(Id = dr1Second.Id, Active__c = true);
		Test.stopTest();

		Assert.isFalse(isActive(dr1First.Id), 'The first DR1 Material Quote should be deactivated');
		Assert.isTrue(isActive(dr1Second.Id), 'The newly activated DR1 Quote should be active');
		Assert.isTrue(isActive(dr2Quote.Id), 'The DR2 Material Quote must be unaffected');
	}

	@IsTest
	static void testDeactivation_doesNotRecalculate_ifDRNotActive() {
		Id oppId = getOpportunityId();
		Design_Revision__c dr = createRevision(oppId); // stays inactive
		Quote first = createQuoteViaTrigger(oppId, dr.Id, TYPE_MATERIAL);
		Quote second = createQuoteViaTrigger(oppId, dr.Id, TYPE_MATERIAL);

		Test.startTest();
		update new Quote(Id = second.Id, Active__c = true);
		Test.stopTest();

		Opportunity opp = [SELECT Amount_Material__c FROM Opportunity WHERE Id = :oppId];
		Assert.isNull(opp.Amount_Material__c, 'No recalculation should occur while the parent DR is not active');
		Assert.isFalse(isActive(first.Id), 'Deactivation of the superseded Quote should still happen');
	}

	@IsTest
	static void testDeleteActiveQuote_amountDropsToZero() {
		Id oppId = getOpportunityId();
		Design_Revision__c dr = createRevision(oppId);
		Quote active = createQuoteViaTrigger(oppId, dr.Id, TYPE_MATERIAL);
		addLineItem(active.Id, 1000);

		// Activating the DR links it to the Opportunity and recalculates amounts.
		update new Design_Revision__c(Id = dr.Id, Is_Active__c = true);
		Opportunity before = [SELECT Amount_Material__c FROM Opportunity WHERE Id = :oppId];
		Assert.areEqual(1000, before.Amount_Material__c, 'Precondition: active Quote total should be reflected');

		Test.startTest();
		delete active;
		Test.stopTest();

		Opportunity after = [SELECT Amount_Material__c FROM Opportunity WHERE Id = :oppId];
		Assert.areEqual(0, after.Amount_Material__c, 'Deleting the only active Material Quote should drop the amount to zero');
	}

	@IsTest
	static void testDeleteInactiveQuote_noRecalc() {
		Id oppId = getOpportunityId();
		Design_Revision__c dr = createRevision(oppId);
		Quote active = createQuoteViaTrigger(oppId, dr.Id, TYPE_MATERIAL);
		Quote inactive = createQuoteViaTrigger(oppId, dr.Id, TYPE_MATERIAL);
		addLineItem(active.Id, 1000);
		addLineItem(inactive.Id, 500);

		update new Design_Revision__c(Id = dr.Id, Is_Active__c = true);
		Opportunity before = [SELECT Amount_Material__c FROM Opportunity WHERE Id = :oppId];
		Assert.areEqual(1000, before.Amount_Material__c, 'Precondition: only the active Quote contributes');

		Test.startTest();
		delete inactive;
		Test.stopTest();

		Opportunity after = [SELECT Amount_Material__c FROM Opportunity WHERE Id = :oppId];
		Assert.areEqual(1000, after.Amount_Material__c, 'Deleting an inactive Quote must not change the amount');
	}

	@IsTest
	static void testNoBypassRecursion() {
		Id oppId = getOpportunityId();
		Design_Revision__c dr = createRevision(oppId);
		Quote first = createQuoteViaTrigger(oppId, dr.Id, TYPE_MATERIAL);
		Quote second = createQuoteViaTrigger(oppId, dr.Id, TYPE_MATERIAL);

		Test.startTest();
		// If the bypass did not work, the internal deactivation update would re-enter
		// the handler and could leave the data inconsistent or hit limits.
		update new Quote(Id = second.Id, Active__c = true);
		Test.stopTest();

		Integer activeCount = [
			SELECT COUNT()
			FROM Quote
			WHERE Design_Revision__c = :dr.Id AND Quote_Type__c = :TYPE_MATERIAL AND Active__c = true
		];
		Assert.areEqual(1, activeCount, 'Exactly one Material Quote may remain active after the bypassed deactivation');
		Assert.isFalse(isActive(first.Id), 'The superseded Quote should be deactivated exactly once');
	}

	// ── Line item & global discount changes re-sync the Opportunity ─────

	private static Decimal oppMaterial(Id oppId) {
		return [SELECT Amount_Material__c FROM Opportunity WHERE Id = :oppId].Amount_Material__c;
	}

	private static Decimal oppPricePerWatt(Id oppId) {
		return [SELECT Price_Per_Watt__c FROM Opportunity WHERE Id = :oppId].Price_Per_Watt__c;
	}

	@IsTest
	static void testLineItemInsert_recalculatesOpportunity() {
		Id oppId = getOpportunityId();
		Design_Revision__c dr = createRevision(oppId); // wattage 10 kW
		Quote q = createQuoteViaTrigger(oppId, dr.Id, TYPE_MATERIAL);
		addLineItem(q.Id, 1000);
		update new Design_Revision__c(Id = dr.Id, Is_Active__c = true);
		Assert.areEqual(1000, oppMaterial(oppId), 'Precondition: 1000 after activation');
		Assert.areEqual(0.10, oppPricePerWatt(oppId), 'Precondition: 1000 / 10000 W = 0.10');

		Test.startTest();
		addLineItem(q.Id, 500); // TotalPrice -> 1500
		Test.stopTest();

		Assert.areEqual(1500, oppMaterial(oppId), 'Adding a line item must re-sync Amount Material');
		Assert.areEqual(0.15, oppPricePerWatt(oppId), '1500 / 10000 W = 0.15');
	}

	@IsTest
	static void testLineItemDelete_recalculatesOpportunity() {
		Id oppId = getOpportunityId();
		Design_Revision__c dr = createRevision(oppId);
		Quote q = createQuoteViaTrigger(oppId, dr.Id, TYPE_MATERIAL);
		addLineItem(q.Id, 1000);
		addLineItem(q.Id, 500);
		update new Design_Revision__c(Id = dr.Id, Is_Active__c = true);
		Assert.areEqual(1500, oppMaterial(oppId), 'Precondition: 1500 after activation');

		Test.startTest();
		delete [SELECT Id FROM QuoteLineItem WHERE QuoteId = :q.Id AND UnitPrice = 500 LIMIT 1];
		Test.stopTest();

		Assert.areEqual(1000, oppMaterial(oppId), 'Deleting a line item must re-sync Amount Material');
		Assert.areEqual(0.10, oppPricePerWatt(oppId), '1000 / 10000 W = 0.10');
	}

	@IsTest
	static void testGlobalDiscountChange_recalculatesOpportunity() {
		Id oppId = getOpportunityId();
		Design_Revision__c dr = createRevision(oppId);
		Quote q = createQuoteViaTrigger(oppId, dr.Id, TYPE_MATERIAL);
		addLineItem(q.Id, 1000);
		update new Design_Revision__c(Id = dr.Id, Is_Active__c = true);
		Assert.areEqual(1000, oppMaterial(oppId), 'Precondition: 1000 before discount');

		Test.startTest();
		update new Quote(Id = q.Id, Global_Discount__c = 50); // 50% off -> TotalPrice 500
		Test.stopTest();

		Assert.areEqual(500, oppMaterial(oppId),
			'A global discount change must re-sync the Opportunity even though the QLI trigger is bypassed');
		Assert.areEqual(0.05, oppPricePerWatt(oppId), '500 / 10000 W = 0.05');
	}
}
