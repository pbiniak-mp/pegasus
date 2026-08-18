@IsTest
private class QuoteSendControllerTest {

	private static final String PDF_TITLE = 'Test Quote_2026_08_10.pdf';
	private static final String SECOND_PDF_TITLE = 'Test Quote_2026_08_11.pdf';
	private static final String STATUS_DRAFT = 'Draft';
	private static final String STATUS_PRESENTED = 'Presented';
	private static final String STATUS_ACCEPTED = 'Accepted';

	@TestSetup
	static void setupData() {
		Account acc = new Account(Name = 'Test Account');
		insert acc;

		Opportunity opp = new Opportunity(
			Name = 'Test Opp',
			AccountId = acc.Id,
			StageName = 'New/Unassigned',
			CloseDate = Date.today().addDays(30)
		);
		insert opp;

		Design_Revision__c revision = new Design_Revision__c(
			Opportunity__c = opp.Id,
			Revision_Number__c = '00'
		);
		insert revision;

		insert new Quote_Sequence__c(
			SetupOwnerId = UserInfo.getOrganizationId(),
			Last_Number__c = 26099
		);

		insert new Quote(
			Name = 'Test Quote',
			OpportunityId = opp.Id,
			Pricebook2Id = Test.getStandardPricebookId(),
			Design_Revision__c = revision.Id,
			Quote_Type__c = 'Material',
			Status = STATUS_DRAFT
		);
	}

	private static Quote getQuote() {
		return [SELECT Id, Status FROM Quote LIMIT 1];
	}

	private static ContentVersion attachPdf(Id quoteId, String title) {
		ContentVersion cv = new ContentVersion(
			Title = title,
			PathOnClient = title,
			VersionData = Blob.valueOf('PDF_PLACEHOLDER'),
			FirstPublishLocationId = quoteId
		);
		insert cv;
		return [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
	}

	@IsTest
	static void getSendState_noDocuments_returnsUnsentStateWithEmptyList() {
		Quote q = getQuote();

		Test.startTest();
		QuoteSendController.SendState state = QuoteSendController.getSendState(q.Id);
		Test.stopTest();

		Assert.isFalse(state.sent, 'A fresh Quote has not been sent');
		Assert.isNull(state.sentAt, 'No send timestamp expected');
		Assert.areEqual(0, state.documents.size(), 'No PDFs attached yet');
	}

	@IsTest
	static void getSendState_withDocuments_returnsThemOldestFirst() {
		Quote q = getQuote();
		ContentVersion first = attachPdf(q.Id, PDF_TITLE);
		ContentVersion second = attachPdf(q.Id, SECOND_PDF_TITLE);

		Test.startTest();
		QuoteSendController.SendState state = QuoteSendController.getSendState(q.Id);
		Test.stopTest();

		Assert.areEqual(2, state.documents.size(), 'Both PDFs should be listed');
		Set<String> returnedIds = new Set<String>();
		for (QuoteSendController.QuoteDocument doc : state.documents) {
			returnedIds.add(doc.contentVersionId);
		}
		Assert.isTrue(returnedIds.contains(first.Id), 'First PDF should be listed');
		Assert.isTrue(returnedIds.contains(second.Id), 'Second PDF should be listed');
	}

	@IsTest
	static void markAsSent_stampsSendFieldsAndPresentsQuote() {
		Quote q = getQuote();
		ContentVersion cv = attachPdf(q.Id, PDF_TITLE);

		Test.startTest();
		QuoteSendController.markAsSent(q.Id, cv.Id);
		Test.stopTest();

		Quote reloaded = [
			SELECT Status, Sent_To_Client__c, Sent_To_Client_At__c, Sent_To_Client_By__c,
				Sent_Quote_Document__c, Sent_Quote_Amount__c, TotalPrice
			FROM Quote
			WHERE Id = :q.Id
		];
		Assert.isTrue(reloaded.Sent_To_Client__c, 'Formula checkbox should follow the timestamp');
		Assert.isNotNull(reloaded.Sent_To_Client_At__c, 'Send timestamp should be stamped');
		Assert.areEqual(UserInfo.getUserId(), reloaded.Sent_To_Client_By__c, 'Sender should be the running user');
		Assert.areEqual(String.valueOf(cv.Id), reloaded.Sent_Quote_Document__c, 'The chosen PDF should be recorded');
		Assert.areEqual(reloaded.TotalPrice, reloaded.Sent_Quote_Amount__c, 'Amount should snapshot the total');
		Assert.areEqual(STATUS_PRESENTED, reloaded.Status, 'Sending should present the Quote');
	}

	@IsTest
	static void markAsSent_doesNotDowngradeAnAlreadyAcceptedQuote() {
		Quote q = getQuote();
		ContentVersion cv = attachPdf(q.Id, PDF_TITLE);
		update new Quote(Id = q.Id, Status = STATUS_ACCEPTED);

		Test.startTest();
		QuoteSendController.markAsSent(q.Id, cv.Id);
		Test.stopTest();

		Quote reloaded = [SELECT Status, Sent_To_Client__c FROM Quote WHERE Id = :q.Id];
		Assert.areEqual(STATUS_ACCEPTED, reloaded.Status, 'Accepted must not be dragged back to Presented');
		Assert.isTrue(reloaded.Sent_To_Client__c, 'The send is still recorded');
	}

	@IsTest
	static void markAsSent_secondAttemptIsRejected() {
		Quote q = getQuote();
		ContentVersion cv = attachPdf(q.Id, PDF_TITLE);
		QuoteSendController.markAsSent(q.Id, cv.Id);

		Boolean threw = false;
		Test.startTest();
		try {
			QuoteSendController.markAsSent(q.Id, cv.Id);
		} catch (Exception e) {
			threw = true;
		}
		Test.stopTest();

		Assert.isTrue(threw, 'A Quote can only be marked as sent once');
	}

	@IsTest
	static void markAsSent_rejectsDocumentFromAnotherRecord() {
		Quote q = getQuote();
		attachPdf(q.Id, PDF_TITLE);

		Account other = new Account(Name = 'Other Account');
		insert other;
		ContentVersion foreign = attachPdf(other.Id, 'Somebody elses file.pdf');

		Boolean threw = false;
		Test.startTest();
		try {
			QuoteSendController.markAsSent(q.Id, foreign.Id);
		} catch (Exception e) {
			threw = true;
		}
		Test.stopTest();

		Assert.isTrue(threw, 'Only a PDF attached to this Quote may be recorded as sent');
		Quote reloaded = [SELECT Sent_To_Client__c FROM Quote WHERE Id = :q.Id];
		Assert.isFalse(reloaded.Sent_To_Client__c, 'Nothing should have been stamped');
	}

	@IsTest
	static void markAsSent_withoutADocumentIsRejected() {
		Quote q = getQuote();

		Boolean threw = false;
		Test.startTest();
		try {
			QuoteSendController.markAsSent(q.Id, null);
		} catch (Exception e) {
			threw = true;
		}
		Test.stopTest();

		Assert.isTrue(threw, 'A send declaration must name the document that went out');
	}

	@IsTest
	static void belongsToQuote_isFalseForNullArguments() {
		Test.startTest();
		Boolean result = QuoteDocumentSelector.belongsToQuote(null, null);
		Datetime lastChange = QuoteDocumentSelector.getLastPriceChange(null);
		List<ContentVersion> pdfs = QuoteDocumentSelector.getQuotePdfs(null);
		Test.stopTest();

		Assert.isFalse(result, 'Null arguments cannot match a document');
		Assert.isNull(lastChange, 'Null Quote has no price history');
		Assert.areEqual(0, pdfs.size(), 'Null Quote has no documents');
	}
}
