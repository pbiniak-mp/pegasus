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
