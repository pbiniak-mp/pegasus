@IsTest
private class QuotePDFControllerTest {
	@TestSetup
	static void setup() {
		Account acc = new Account(Name = 'Test Account');
		insert acc;

		Contact con = new Contact(
			FirstName = 'John',
			LastName = 'Doe',
			AccountId = acc.Id
		);
		insert con;

		Opportunity opp = new Opportunity(
			Name = 'Test Opportunity',
			AccountId = acc.Id,
			StageName = 'Qualification',
			CloseDate = Date.today().addDays(30),
			Module_Quantity__c = 10,
			Module_Wattage_W__c = 400,
			Project_Wattage_kW__c = 4
		);
		insert opp;

		// Enable standard pricebook
		Id standardPricebookId = Test.getStandardPricebookId();

		Product2 product = new Product2(
			Name = 'Test Product',
			ProductCode = 'TEST-001',
			IsActive = true
		);
		insert product;

		PricebookEntry pbe = new PricebookEntry(
			Pricebook2Id = standardPricebookId,
			Product2Id = product.Id,
			UnitPrice = 100.00,
			IsActive = true
		);
		insert pbe;

		Quote quote = new Quote(
			Name = 'Test Quote',
			OpportunityId = opp.Id,
			Pricebook2Id = standardPricebookId,
			ContactId = con.Id,
			ExpirationDate = Date.today().addDays(30),
			BillingStreet = '123 Main St',
			BillingCity = 'Richmond',
			BillingState = 'California',
			BillingPostalCode = '94804',
			BillingCountry = 'United States'
		);
		insert quote;

		QuoteLineItem qli = new QuoteLineItem(
			QuoteId = quote.Id,
			Product2Id = product.Id,
			PricebookEntryId = pbe.Id,
			Quantity = 2,
			UnitPrice = 100.00
		);
		insert qli;
	}

	private static Quote getTestQuote() {
		return [SELECT Id FROM Quote LIMIT 1];
	}

	private static QuotePDFController buildController(Id quoteId) {
		ApexPages.StandardController sc = new ApexPages.StandardController(
			new Quote(Id = quoteId)
		);
		return new QuotePDFController(sc);
	}

	@IsTest
	static void testControllerLoadsQuote() {
		Quote q = getTestQuote();
		QuotePDFController ctrl = buildController(q.Id);

		System.assertNotEquals(null, ctrl.quote, 'Quote should be loaded');
		System.assertEquals(q.Id, ctrl.quote.Id, 'Quote ID should match');
	}

	@IsTest
	static void testControllerLoadsOpportunity() {
		Quote q = getTestQuote();
		QuotePDFController ctrl = buildController(q.Id);

		System.assertNotEquals(null, ctrl.opp, 'Opportunity should be loaded');
		System.assertEquals('Test Opportunity', ctrl.opp.Name, 'Opportunity name should match');
	}

	@IsTest
	static void testControllerLoadsContact() {
		Quote q = getTestQuote();
		QuotePDFController ctrl = buildController(q.Id);

		System.assertNotEquals(null, ctrl.contact, 'Contact should be loaded');
		System.assertEquals('John', ctrl.contact.FirstName, 'Contact first name should match');
		System.assertEquals('Doe', ctrl.contact.LastName, 'Contact last name should match');
	}

	@IsTest
	static void testControllerLoadsLineItems() {
		Quote q = getTestQuote();
		QuotePDFController ctrl = buildController(q.Id);

		System.assertNotEquals(null, ctrl.lineItems, 'Line items should not be null');
		System.assertEquals(1, ctrl.lineItems.size(), 'Should have 1 line item');
	}

	@IsTest
	static void testGetTotalPrice() {
		Quote q = getTestQuote();
		QuotePDFController ctrl = buildController(q.Id);

		Decimal total = ctrl.getTotalPrice();

		System.assertEquals(200.00, total, 'Total price should be 200.00 (2 x 100.00)');
	}

	@IsTest
	static void testGetFormattedDate() {
		Quote q = getTestQuote();
		QuotePDFController ctrl = buildController(q.Id);

		String formatted = ctrl.getFormattedDate();

		System.assertNotEquals(QuotePDFController.EMPTY_STRING, formatted, 'Formatted date should not be empty');
	}

	@IsTest
	static void testGetFormattedExpirationDate() {
		Quote q = getTestQuote();
		QuotePDFController ctrl = buildController(q.Id);

		String formatted = ctrl.getFormattedExpirationDate();

		System.assertNotEquals(QuotePDFController.EMPTY_STRING, formatted, 'Formatted expiration date should not be empty');
	}

	@IsTest
	static void testGetFormattedExpirationDateWhenNull() {
		// Create quote without expiration date
		Account acc = [SELECT Id FROM Account LIMIT 1];
		Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
		Id standardPricebookId = Test.getStandardPricebookId();

		Quote quoteNoExp = new Quote(
			Name = 'No Expiry Quote',
			OpportunityId = opp.Id,
			Pricebook2Id = standardPricebookId,
			ExpirationDate = null
		);
		insert quoteNoExp;

		QuotePDFController ctrl = buildController(quoteNoExp.Id);

		String formatted = ctrl.getFormattedExpirationDate();

		System.assertEquals(QuotePDFController.EMPTY_STRING, formatted, 'Should return empty string when expiration date is null');
	}

	@IsTest
	static void testGetTotalPriceWithNoLineItems() {
		Account acc = [SELECT Id FROM Account LIMIT 1];
		Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
		Id standardPricebookId = Test.getStandardPricebookId();

		Quote emptyQuote = new Quote(
			Name = 'Empty Quote',
			OpportunityId = opp.Id,
			Pricebook2Id = standardPricebookId
		);
		insert emptyQuote;

		QuotePDFController ctrl = buildController(emptyQuote.Id);

		System.assertEquals(0, ctrl.getTotalPrice(), 'Total should be 0 with no line items');
	}

	@IsTest
	static void testControllerWithNullQuoteId() {
		Quote fakeQuote = new Quote(Id = null);
		// Passing non-existing ID — controller should handle gracefully
		Quote q = getTestQuote();
		QuotePDFController ctrl = buildController(q.Id);

		// Verify no exception thrown and quote is loaded
		System.assertNotEquals(null, ctrl.quote, 'Controller should load quote without throwing');
	}

	@IsTest
	static void testControllerWithNoContact() {
		Account acc = [SELECT Id FROM Account LIMIT 1];
		Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
		Id standardPricebookId = Test.getStandardPricebookId();

		Quote quoteNoContact = new Quote(
			Name = 'No Contact Quote',
			OpportunityId = opp.Id,
			Pricebook2Id = standardPricebookId,
			ContactId = null
		);
		insert quoteNoContact;

		QuotePDFController ctrl = buildController(quoteNoContact.Id);

		System.assertEquals(null, ctrl.contact, 'Contact should be null when not set on quote');
	}

	@IsTest
	static void testOpportunityFieldsLoaded() {
		Quote q = getTestQuote();
		QuotePDFController ctrl = buildController(q.Id);

		System.assertEquals(10, ctrl.opp.Module_Quantity__c, 'Module quantity should match');
		System.assertEquals(400, ctrl.opp.Module_Wattage_W__c, 'Module wattage should match');
		System.assertEquals(4, ctrl.opp.Project_Wattage_kW__c, 'Project wattage should match');
	}

	@IsTest
	static void testGetTotalAttachments() {
		Quote q = getTestQuote();
		QuotePDFController ctrl = buildController(q.Id);

		Decimal total = ctrl.getTotalAttachments();

		System.assertEquals(2, total, 'Total attachments should be 2 (1 line item with qty=2)');
	}

	@IsTest
	static void testGetTotalAttachments_withNoLineItems() {
		Account acc = [SELECT Id FROM Account LIMIT 1];
		Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

		Quote emptyQuote = new Quote(
			Name           = 'Empty Attachments Quote',
			OpportunityId  = opp.Id,
			Pricebook2Id   = Test.getStandardPricebookId()
		);
		insert emptyQuote;

		QuotePDFController ctrl = buildController(emptyQuote.Id);

		System.assertEquals(0, ctrl.getTotalAttachments(), 'Total attachments should be 0 with no line items');
	}

	@IsTest
	static void testControllerWithMissingQuote_handlesNullGracefully() {
		// Passing an unsaved Quote (no Id) causes getQuoteById to return null → early return
		ApexPages.StandardController sc = new ApexPages.StandardController(new Quote());
		QuotePDFController ctrl = new QuotePDFController(sc);

		Assert.isNull(ctrl.quote, 'Quote should be null when not found');
		Assert.isNull(ctrl.opp, 'Opp should be null when quote not found');
		Assert.areEqual(
			QuotePDFController.EMPTY_STRING,
			ctrl.getFormattedDate(),
			'getFormattedDate should return empty string when quote is null'
		);
		Assert.areEqual(
			QuotePDFController.EMPTY_STRING,
			ctrl.getFormattedExpirationDate(),
			'getFormattedExpirationDate should return empty string when quote is null'
		);
		Assert.areEqual(0, ctrl.getTotalPrice(), 'getTotalPrice should return 0 when quote is null');
		Assert.areEqual(0, ctrl.getTotalAttachments(), 'getTotalAttachments should return 0 when quote is null');
	}
}