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

	// ── Quote -> Opportunity field sync ─────────────────────────────────

	private static final Decimal SYNC_WATTAGE_KW = 10;
	private static final Decimal SYNC_QLI_QUANTITY = 2;
	private static final Decimal SYNC_QLI_UNIT_PRICE = 500;
	// 2 * 500 = 1000 -> Expected Revenue; 1000 / (10 * 1000) = 0.10 -> Price Per Watt
	private static final Decimal SYNC_EXPECTED_REVENUE = 1000;
	private static final Decimal SYNC_EXPECTED_PPW = 0.10;

	private static Design_Revision__c insertDesignRevision(Id oppId, Decimal wattageKw) {
		Design_Revision__c rev = new Design_Revision__c(
			Opportunity__c = oppId,
			Project_Wattage_kW__c = wattageKw,
			Revision_Number__c = '00'
		);
		insert rev;
		return rev;
	}

	private static Quote insertQuoteWithLineItem(Id oppId, Id designRevisionId) {
		Id pricebookId = Test.getStandardPricebookId();

		Product2 product = new Product2(Name = 'Sync Test Product ' + Crypto.getRandomLong(), IsActive = true);
		insert product;

		PricebookEntry pbe = new PricebookEntry(
			Pricebook2Id = pricebookId,
			Product2Id = product.Id,
			UnitPrice = SYNC_QLI_UNIT_PRICE,
			IsActive = true
		);
		insert pbe;

		Quote q = new Quote(
			Name = 'Sync Quote',
			OpportunityId = oppId,
			Pricebook2Id = pricebookId,
			ExpirationDate = Date.today().addDays(30),
			Quote_Type__c = 'Material',
			Design_Revision__c = designRevisionId
		);
		insert q;

		insert new QuoteLineItem(
			QuoteId = q.Id,
			PricebookEntryId = pbe.Id,
			Product2Id = product.Id,
			Quantity = SYNC_QLI_QUANTITY,
			UnitPrice = SYNC_QLI_UNIT_PRICE
		);

		return q;
	}

	// IsSyncing is platform-controlled; setting Opportunity.SyncedQuoteId flips it to true.
	private static void startSyncing(Id oppId, Id quoteId) {
		update new Opportunity(Id = oppId, SyncedQuoteId = quoteId);
	}

	@IsTest
	static void testSync_quoteStartsSyncing_copiesFieldsToOpportunity() {
		Id oppId = getOpportunityId();
		Design_Revision__c rev = insertDesignRevision(oppId, SYNC_WATTAGE_KW);
		Quote q = insertQuoteWithLineItem(oppId, rev.Id);

		Test.startTest();
		startSyncing(oppId, q.Id);
		Test.stopTest();

		Opportunity opp = [SELECT Expected_Revenue__c, Price_Per_Watt__c FROM Opportunity WHERE Id = :oppId];
		Assert.areEqual(SYNC_EXPECTED_REVENUE, opp.Expected_Revenue__c,
			'Quote.TotalPrice should be copied to Opportunity.Expected_Revenue__c when the Quote starts syncing');
		Assert.areEqual(SYNC_EXPECTED_PPW, opp.Price_Per_Watt__c,
			'Quote.Price_Per_Watt__c should be copied to Opportunity.Price_Per_Watt__c when the Quote starts syncing');
	}

	@IsTest
	static void testSync_quoteNeverSyncing_doesNotUpdate() {
		Id oppId = getOpportunityId();
		Design_Revision__c rev = insertDesignRevision(oppId, SYNC_WATTAGE_KW);
		Quote q = insertQuoteWithLineItem(oppId, rev.Id);

		Test.startTest();
		q.Description = 'unrelated change';
		update q;
		Test.stopTest();

		Opportunity opp = [SELECT Expected_Revenue__c, Price_Per_Watt__c FROM Opportunity WHERE Id = :oppId];
		Assert.isNull(opp.Expected_Revenue__c,
			'Opportunity should not be touched while the Quote is not syncing');
		Assert.isNull(opp.Price_Per_Watt__c,
			'Opportunity should not be touched while the Quote is not syncing');
	}

	@IsTest
	static void testSync_alreadySyncing_doesNotResyncOnUnrelatedUpdate() {
		Id oppId = getOpportunityId();
		Design_Revision__c rev = insertDesignRevision(oppId, SYNC_WATTAGE_KW);
		Quote q = insertQuoteWithLineItem(oppId, rev.Id);

		// Start syncing once.
		startSyncing(oppId, q.Id);

		// Clear the Opp values to detect any unwanted resync.
		update new Opportunity(Id = oppId, Expected_Revenue__c = null, Price_Per_Watt__c = null);

		Test.startTest();
		// Quote is still syncing; an unrelated change must NOT re-copy the fields.
		q.Description = 'unrelated change';
		update q;
		Test.stopTest();

		Opportunity opp = [SELECT Expected_Revenue__c, Price_Per_Watt__c FROM Opportunity WHERE Id = :oppId];
		Assert.isNull(opp.Expected_Revenue__c,
			'Sync should only fire when the Quote starts syncing, not on every update of a syncing quote');
		Assert.isNull(opp.Price_Per_Watt__c,
			'Sync should only fire when the Quote starts syncing, not on every update of a syncing quote');
	}

	@IsTest
	static void testSync_nullList_isNoOp() {
		Test.startTest();
		QuoteService.syncQuoteFieldsToOpportunity(null, new Map<Id, Quote>());
		QuoteService.syncQuoteFieldsToOpportunity(new List<Quote>(), new Map<Id, Quote>());
		QuoteService.syncQuoteFieldsToOpportunity(new List<Quote>{ new Quote() }, null);
		Test.stopTest();
		// No DML, no exception expected.
	}

	@IsTest
	static void testSync_bulk_multipleOpportunitiesUpdatedInSingleTransaction() {
		Account acc = [SELECT Id FROM Account LIMIT 1];

		List<Opportunity> opps = new List<Opportunity>();
		for (Integer i = 0; i < 5; i++) {
			opps.add(new Opportunity(
				Name = 'Sync Bulk Opp ' + i,
				AccountId = acc.Id,
				StageName = 'Qualification',
				CloseDate = Date.today().addDays(30),
				Pricebook2Id = Test.getStandardPricebookId()
			));
		}
		insert opps;

		Map<Id, Id> quoteIdByOppId = new Map<Id, Id>();
		for (Opportunity opp : opps) {
			Design_Revision__c rev = insertDesignRevision(opp.Id, SYNC_WATTAGE_KW);
			Quote q = insertQuoteWithLineItem(opp.Id, rev.Id);
			quoteIdByOppId.put(opp.Id, q.Id);
		}

		List<Opportunity> toSync = new List<Opportunity>();
		for (Id oppId : quoteIdByOppId.keySet()) {
			toSync.add(new Opportunity(Id = oppId, SyncedQuoteId = quoteIdByOppId.get(oppId)));
		}

		Test.startTest();
		update toSync;
		Test.stopTest();

		Map<Id, Opportunity> reloaded = new Map<Id, Opportunity>(
			[SELECT Expected_Revenue__c, Price_Per_Watt__c FROM Opportunity WHERE Id IN :opps]
		);
		for (Opportunity o : reloaded.values()) {
			Assert.areEqual(SYNC_EXPECTED_REVENUE, o.Expected_Revenue__c,
				'Every Opportunity in the bulk sync should get Expected_Revenue__c');
			Assert.areEqual(SYNC_EXPECTED_PPW, o.Price_Per_Watt__c,
				'Every Opportunity in the bulk sync should get Price_Per_Watt__c');
		}
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
}
