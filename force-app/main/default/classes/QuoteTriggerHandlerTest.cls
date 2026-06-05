@IsTest
private class QuoteTriggerHandlerTest {

	private static final String TYPE_MATERIAL = 'Material';
	private static final String TYPE_STAMP = 'Stamp';
	private static final Decimal INITIAL_SEQUENCE = 1000;

	@TestSetup
	static void setup() {
		Account acc = new Account(Name = 'QTH Account');
		insert acc;

		Opportunity opp = new Opportunity(
			Name = 'QTH Opportunity',
			AccountId = acc.Id,
			StageName = 'Qualification',
			CloseDate = Date.today().addDays(30)
		);
		insert opp;

		Design_Revision__c dr = new Design_Revision__c(
			Opportunity__c = opp.Id,
			Revision_Number__c = '00',
			Is_Active__c = false
		);
		insert dr;

		insert new Quote_Sequence__c(
			SetupOwnerId = UserInfo.getOrganizationId(),
			Last_Number__c = INITIAL_SEQUENCE
		);
	}

	private static Id getOppId() {
		return [SELECT Id FROM Opportunity LIMIT 1].Id;
	}

	private static Id getDrId() {
		return [SELECT Id FROM Design_Revision__c LIMIT 1].Id;
	}

	private static Quote buildQuote(Id oppId, Id drId, String type) {
		return new Quote(
			Name = 'Q ' + type,
			OpportunityId = oppId,
			Pricebook2Id = Test.getStandardPricebookId(),
			ExpirationDate = Date.today().addDays(30),
			Quote_Type__c = type,
			Design_Revision__c = drId
		);
	}

	@IsTest
	static void testAutoActivate_firstQuoteOfType() {
		Quote q = buildQuote(getOppId(), getDrId(), TYPE_MATERIAL);

		Test.startTest();
		insert q;
		Test.stopTest();

		Quote reloaded = [SELECT Active__c FROM Quote WHERE Id = :q.Id];
		Assert.isTrue(reloaded.Active__c, 'First Quote of its type under a Design Revision must be auto-activated');
	}

	@IsTest
	static void testNoAutoActivate_secondQuoteOfType() {
		Id oppId = getOppId();
		Id drId = getDrId();

		Quote first = buildQuote(oppId, drId, TYPE_MATERIAL);
		insert first;

		Quote second = buildQuote(oppId, drId, TYPE_MATERIAL);

		Test.startTest();
		insert second;
		Test.stopTest();

		Quote reloadedSecond = [SELECT Active__c FROM Quote WHERE Id = :second.Id];
		Assert.isFalse(reloadedSecond.Active__c, 'Second Quote of an existing type must NOT be auto-activated');

		Quote reloadedFirst = [SELECT Active__c FROM Quote WHERE Id = :first.Id];
		Assert.isTrue(reloadedFirst.Active__c, 'The first Quote should remain active');
	}

	@IsTest
	static void testAutoActivate_differentTypes() {
		Id oppId = getOppId();
		Id drId = getDrId();

		List<Quote> quotes = new List<Quote>{
			buildQuote(oppId, drId, TYPE_MATERIAL),
			buildQuote(oppId, drId, TYPE_STAMP)
		};

		Test.startTest();
		insert quotes;
		Test.stopTest();

		Map<Id, Quote> byId = new Map<Id, Quote>([SELECT Active__c FROM Quote WHERE Id IN :quotes]);
		for (Quote q : quotes) {
			Assert.isTrue(byId.get(q.Id).Active__c, 'First Quote of each distinct type must be auto-activated');
		}
	}

	@IsTest
	static void testBulkInsert_sameTypeSameDR() {
		Id oppId = getOppId();
		Id drId = getDrId();

		List<Quote> quotes = new List<Quote>();
		for (Integer i = 0; i < 50; i++) {
			quotes.add(buildQuote(oppId, drId, TYPE_MATERIAL));
		}

		Test.startTest();
		insert quotes;
		Test.stopTest();

		Integer activeCount = [SELECT COUNT() FROM Quote WHERE Id IN :quotes AND Active__c = true];
		Assert.areEqual(1, activeCount, 'Exactly one Quote of the same type/DR may be auto-activated in a bulk insert');
	}

	@IsTest
	static void testBulkInsert_differentDRs() {
		Id oppId = getOppId();

		List<Design_Revision__c> revisions = new List<Design_Revision__c>();
		for (Integer i = 0; i < 50; i++) {
			revisions.add(new Design_Revision__c(
				Opportunity__c = oppId,
				Revision_Number__c = String.valueOf(100 + i),
				Is_Active__c = false
			));
		}
		insert revisions;

		List<Quote> quotes = new List<Quote>();
		for (Design_Revision__c dr : revisions) {
			quotes.add(buildQuote(oppId, dr.Id, TYPE_MATERIAL));
		}

		Test.startTest();
		insert quotes;
		Test.stopTest();

		Integer activeCount = [SELECT COUNT() FROM Quote WHERE Id IN :quotes AND Active__c = true];
		Assert.areEqual(50, activeCount, 'The first Material Quote under each distinct DR must be auto-activated');
	}
}
