@IsTest
private class QuoteSavePDFControllerTest {

	@TestSetup
	static void setup() {
		Account acc = new Account(Name = 'Test Account');
		insert acc;

		Opportunity opp = new Opportunity(
			Name = 'Test Opportunity',
			AccountId = acc.Id,
			StageName = 'Qualification',
			CloseDate = Date.today().addDays(30)
		);
		insert opp;

		Quote quote = new Quote(
			Name = 'Test Quote',
			OpportunityId = opp.Id,
			Pricebook2Id = Test.getStandardPricebookId()
		);
		insert quote;
	}

	private static Quote getTestQuote() {
		return [SELECT Id FROM Quote LIMIT 1];
	}

	@IsTest
	static void testSavePDFCreatesContentVersion() {
		Quote q = getTestQuote();

		ApexPages.StandardController sc = new ApexPages.StandardController(q);
		QuoteSavePDFController ctrl = new QuoteSavePDFController(sc);

		Test.startTest();
		PageReference result = ctrl.savePDF();
		Test.stopTest();

		List<ContentDocumentLink> links = [
			SELECT ContentDocumentId
			FROM ContentDocumentLink
			WHERE LinkedEntityId = :q.Id
		];

		System.assertEquals(1, links.size(), 'Should have 1 file attached to Quote');
	}

	@IsTest
	static void testSavePDFRedirectsToQuotePage() {
		Quote q = getTestQuote();

		ApexPages.StandardController sc = new ApexPages.StandardController(q);
		QuoteSavePDFController ctrl = new QuoteSavePDFController(sc);

		Test.startTest();
		ctrl.savePDF();
		PageReference result = ctrl.goToQuote();
		Test.stopTest();

		System.assertNotEquals(null, result, 'Should redirect after save');
		System.assert(result.getUrl().contains(String.valueOf(q.Id).substring(0, 15)), 'Should redirect to Quote record');
	}
}