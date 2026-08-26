@IsTest
private class QuoteSavePDFControllerTest {

	@TestSetup
	static void setup() {
		// Complete by design - savePDF refuses to render a Quote with blanks on it.
		QuotePDFTestDataFactory.createCompleteQuote();
	}

	private static Quote getTestQuote() {
		return [SELECT Id FROM Quote LIMIT 1];
	}

	@IsTest
	static void testSavePDFCreatesContentVersion() {
		QuotePDFTestDataFactory.grantPDFPermission();
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
		QuotePDFTestDataFactory.grantPDFPermission();
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

	@IsTest
	static void testInitialState_showFlagsAreFalse() {
		QuotePDFTestDataFactory.grantPDFPermission();
		Quote q = getTestQuote();
		ApexPages.StandardController sc = new ApexPages.StandardController(q);
		QuoteSavePDFController ctrl = new QuoteSavePDFController(sc);

		Assert.isFalse(ctrl.showSuccess, 'showSuccess should be false on init');
		Assert.isFalse(ctrl.showError, 'showError should be false on init');
	}

	@IsTest
	static void testSavePDF_setsShowSuccessAndSavedFileName() {
		QuotePDFTestDataFactory.grantPDFPermission();
		Quote q = getTestQuote();
		ApexPages.StandardController sc = new ApexPages.StandardController(q);
		QuoteSavePDFController ctrl = new QuoteSavePDFController(sc);

		Test.startTest();
		ctrl.savePDF();
		Test.stopTest();

		Assert.isTrue(ctrl.showSuccess, 'showSuccess should be true after successful save');
		Assert.isFalse(ctrl.showError, 'showError should remain false on success');
		Assert.isNotNull(ctrl.savedFileName, 'savedFileName should be set after successful save');
		Assert.isTrue(
			ctrl.savedFileName.endsWith(QuoteSavePDFController.PDF_EXTENSION),
			'savedFileName should have .pdf extension'
		);
	}

	@IsTest
	static void testSavePDF_withIncompleteQuote_blocksGeneration() {
		QuotePDFTestDataFactory.grantPDFPermission();
		Design_Revision__c revision = [SELECT Id FROM Design_Revision__c LIMIT 1];
		revision.Total_Attachments__c = null;
		update revision;

		Quote q = getTestQuote();
		ApexPages.StandardController sc = new ApexPages.StandardController(q);
		QuoteSavePDFController ctrl = new QuoteSavePDFController(sc);

		Test.startTest();
		ctrl.savePDF();
		Test.stopTest();

		Assert.isTrue(ctrl.showIncomplete, 'showIncomplete should be true for a Quote with blanks');
		Assert.isFalse(ctrl.showSuccess, 'No PDF should be produced');
		Assert.isTrue(
			QuotePDFTestDataFactory.mentions(
				ctrl.missingFields,
				QuotePDFValidationService.LABEL_TOTAL_ATTACHMENTS
			),
			'The empty field should be listed: ' + ctrl.missingFields
		);

		List<ContentDocumentLink> links = [
			SELECT ContentDocumentId
			FROM ContentDocumentLink
			WHERE LinkedEntityId = :q.Id
		];
		Assert.areEqual(0, links.size(), 'No file should be attached to an incomplete Quote');
	}

	@IsTest
	static void testSavePDF_withCompleteQuote_reportsNoMissingFields() {
		QuotePDFTestDataFactory.grantPDFPermission();
		Quote q = getTestQuote();
		ApexPages.StandardController sc = new ApexPages.StandardController(q);
		QuoteSavePDFController ctrl = new QuoteSavePDFController(sc);

		Test.startTest();
		ctrl.savePDF();
		Test.stopTest();

		Assert.isFalse(ctrl.showIncomplete, 'A complete Quote should not be blocked: ' + ctrl.missingFields);
	}

	@IsTest
	static void testSavePDF_withMissingQuote_setsShowError() {
		QuotePDFTestDataFactory.grantPDFPermission();
		// No id → QuoteSelector returns null → savePDF throws NullPointerException → caught
		ApexPages.StandardController sc = new ApexPages.StandardController(new Quote());
		QuoteSavePDFController ctrl = new QuoteSavePDFController(sc);

		Test.startTest();
		ctrl.savePDF();
		Test.stopTest();

		Assert.isTrue(ctrl.showError, 'showError should be true when an exception occurs');
		Assert.isNotNull(ctrl.errorMessage, 'errorMessage should be populated on error');
		Assert.isFalse(ctrl.showSuccess, 'showSuccess should remain false on error');
	}

	@IsTest
	static void testSavePDF_withoutPermission_refusesAndFilesNothing() {
		QuotePDFTestDataFactory.revokePDFPermission();
		Quote q = getTestQuote();

		ApexPages.StandardController sc = new ApexPages.StandardController(q);
		QuoteSavePDFController ctrl = new QuoteSavePDFController(sc);

		Test.startTest();
		ctrl.savePDF();
		Test.stopTest();

		Assert.isTrue(ctrl.showNoPermission, 'An ungranted user should be refused');
		Assert.isFalse(ctrl.showSuccess, 'No PDF should be produced without the permission');
		Assert.isFalse(ctrl.showIncomplete, 'The refusal should not be dressed up as an incomplete Quote');
		Assert.isFalse(ctrl.showError, 'A refusal is not a failure');

		List<ContentDocumentLink> links = [
			SELECT ContentDocumentId
			FROM ContentDocumentLink
			WHERE LinkedEntityId = :q.Id
		];
		Assert.areEqual(0, links.size(), 'No file should be attached without the permission');
	}

	@IsTest
	static void testSavePDF_withoutPermission_isCheckedBeforeCompleteness() {
		// An incomplete Quote plus no permission: the user is told about the
		// permission, not handed a to-do list for a quote they may not send.
		Design_Revision__c revision = [SELECT Id FROM Design_Revision__c LIMIT 1];
		revision.Total_Attachments__c = null;
		update revision;

		QuotePDFTestDataFactory.revokePDFPermission();
		Quote q = getTestQuote();

		ApexPages.StandardController sc = new ApexPages.StandardController(q);
		QuoteSavePDFController ctrl = new QuoteSavePDFController(sc);

		Test.startTest();
		ctrl.savePDF();
		Test.stopTest();

		Assert.isTrue(ctrl.showNoPermission, 'The permission gate should answer first');
		Assert.isFalse(ctrl.showIncomplete, 'The missing-field list should not be built for an ungranted user');
	}

	@IsTest
	static void testInitialState_showNoPermissionIsFalse() {
		QuotePDFTestDataFactory.grantPDFPermission();
		Quote q = getTestQuote();
		ApexPages.StandardController sc = new ApexPages.StandardController(q);
		QuoteSavePDFController ctrl = new QuoteSavePDFController(sc);

		Assert.isFalse(ctrl.showNoPermission, 'showNoPermission should be false on init');
		Assert.isNotNull(ctrl.noPermissionMessage, 'The page needs a message to render');
	}
}
