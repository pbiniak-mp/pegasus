@IsTest
private class QuotePDFValidationServiceTest {

	private static final String ACRONYM = 'PCS';

	@TestSetup
	static void setup() {
		QuotePDFTestDataFactory.createCompleteQuote();
	}

	private static Quote getTestQuote() {
		return [SELECT Id FROM Quote LIMIT 1];
	}

	@IsTest
	static void getMissingFields_completeQuote_returnsNothing() {
		Quote q = getTestQuote();

		Test.startTest();
		List<String> missing = QuotePDFValidationService.getMissingFields(q.Id);
		Test.stopTest();

		Assert.areEqual(
			new List<String>(),
			missing,
			'A fully populated Quote should report no missing PDF fields'
		);
	}

	@IsTest
	static void getMissingFields_nullId_reportsQuoteNotFound() {
		List<String> missing = QuotePDFValidationService.getMissingFields((Id) null);

		Assert.areEqual(1, missing.size(), 'Only the not-found message is expected');
		Assert.areEqual(QuotePDFValidationService.MSG_QUOTE_NOT_FOUND, missing[0]);
	}

	@IsTest
	static void getMissingFields_blankTotalAttachments_isReported() {
		Design_Revision__c revision = [SELECT Id FROM Design_Revision__c LIMIT 1];
		revision.Total_Attachments__c = null;
		update revision;

		Quote q = getTestQuote();

		Test.startTest();
		List<String> missing = QuotePDFValidationService.getMissingFields(q.Id);
		Test.stopTest();

		Assert.areEqual(1, missing.size(), 'Only Total Attachments should be reported: ' + missing);
		Assert.areEqual(
			QuotePDFValidationService.describe(
				QuotePDFValidationService.LABEL_TOTAL_ATTACHMENTS,
				QuotePDFValidationService.RECORD_DESIGN_REVISION + ' REV-' + QuotePDFTestDataFactory.REV_00,
				QuotePDFValidationService.FIELD_TOTAL_ATTACHMENTS
			),
			missing[0],
			'The entry should name the record and field to fix, not just the PDF caption'
		);
	}

	@IsTest
	static void getMissingFields_blankBillingAndContact_areReported() {
		Quote q = [SELECT Id, ContactId, BillingCity FROM Quote LIMIT 1];
		q.ContactId = null;
		q.BillingCity = null;
		update q;

		Test.startTest();
		List<String> missing = QuotePDFValidationService.getMissingFields(q.Id);
		Test.stopTest();

		Assert.isTrue(
			QuotePDFTestDataFactory.mentions(missing, QuotePDFValidationService.LABEL_CUSTOMER_NAME),
			'Missing Contact should surface as Customer Name: ' + missing
		);
		Assert.isTrue(
			QuotePDFTestDataFactory.mentions(missing, QuotePDFValidationService.LABEL_CITY),
			'Missing BillingCity should surface as City: ' + missing
		);
	}

	@IsTest
	static void getMissingFields_withoutDesignRevision_reportsRevisionOnly() {
		Account acc = new Account(Name = 'No Revision Account', Naming_Acronym__c = ACRONYM);
		insert acc;

		Opportunity opp = QuotePDFTestDataFactory.buildOpportunity(acc.Id, 'No Revision Opp');
		insert opp;

		Quote quote = new Quote(
			Name = 'No Revision Quote',
			OpportunityId = opp.Id,
			Pricebook2Id = Test.getStandardPricebookId(),
			Quote_Type__c = Constants.QUOTE_TYPE_MATERIAL
		);
		insert quote;

		Test.startTest();
		List<String> missing = QuotePDFValidationService.getMissingFields(quote.Id);
		Test.stopTest();

		Assert.isTrue(
			QuotePDFTestDataFactory.mentions(missing, QuotePDFValidationService.LABEL_DESIGN_REVISION),
			'A Quote without a Design Revision should report it once: ' + missing
		);
		Assert.isFalse(
			QuotePDFTestDataFactory.mentions(missing, QuotePDFValidationService.LABEL_TOTAL_MODULES),
			'Revision-owned labels should not be listed individually: ' + missing
		);
	}

	@IsTest
	static void getMissingFields_withoutLineItems_isReported() {
		delete [SELECT Id FROM QuoteLineItem];
		Quote q = getTestQuote();

		Test.startTest();
		List<String> missing = QuotePDFValidationService.getMissingFields(q.Id);
		Test.stopTest();

		Assert.areEqual(1, missing.size(), 'Only the empty line-item table should be reported: ' + missing);
		Assert.isTrue(
			QuotePDFTestDataFactory.mentions(missing, QuotePDFValidationService.LABEL_LINE_ITEMS),
			'A Quote with no Racking Components must not produce a PDF: ' + missing
		);
	}

	@IsTest
	static void validate_completeQuote_doesNotThrow() {
		Quote q = getTestQuote();

		Test.startTest();
		QuotePDFValidationService.validate(q.Id);
		Test.stopTest();
	}

	@IsTest
	static void validate_incompleteQuote_throwsWithFieldList() {
		Design_Revision__c revision = [SELECT Id FROM Design_Revision__c LIMIT 1];
		revision.Total_Attachments__c = null;
		update revision;

		Quote q = getTestQuote();
		Boolean thrown = false;

		Test.startTest();
		try {
			QuotePDFValidationService.validate(q.Id);
		} catch (QuotePDFValidationService.IncompleteQuoteException e) {
			thrown = true;
			Assert.isTrue(
				e.getMessage().contains(QuotePDFValidationService.LABEL_TOTAL_ATTACHMENTS),
				'The message should name the empty field: ' + e.getMessage()
			);
		}
		Test.stopTest();

		Assert.isTrue(thrown, 'validate should throw for an incomplete Quote');
	}

	@IsTest
	static void buildMessage_joinsLabels() {
		String message = QuotePDFValidationService.buildMessage(
			new List<String>{ 'City', 'State' }
		);

		Assert.isTrue(message.startsWith(QuotePDFValidationService.MSG_PREFIX), message);
		Assert.isTrue(message.contains('City' + QuotePDFValidationService.MSG_SEPARATOR + 'State'), message);
	}
}
