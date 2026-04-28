@IsTest
private class DesignRevisionQuotesControllerTest {

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

		Id pricebookId = Test.getStandardPricebookId();

		insert new Quote_Sequence__c(
			SetupOwnerId = UserInfo.getOrganizationId(),
			Last_Number__c = 26099
		);

		Quote materialQuote = new Quote(
			Name = 'Material Quote',
			OpportunityId = opp.Id,
			Pricebook2Id = pricebookId,
			Design_Revision__c = revision.Id,
			Quote_Type__c = 'Material',
			Status = 'Draft'
		);

		Quote stampQuote = new Quote(
			Name = 'Stamp Quote',
			OpportunityId = opp.Id,
			Pricebook2Id = pricebookId,
			Design_Revision__c = revision.Id,
			Quote_Type__c = 'Stamp',
			Status = 'Accepted'
		);

		insert new List<Quote>{ materialQuote, stampQuote };
	}

	@IsTest
	static void testGetQuotesByRevision_returnsWrappers() {
		Design_Revision__c revision = [SELECT Id FROM Design_Revision__c LIMIT 1];

		Test.startTest();
		List<DesignRevisionQuotesController.QuoteWrapper> result =
			DesignRevisionQuotesController.getQuotesByRevision(revision.Id);
		Test.stopTest();

		Assert.areEqual(2, result.size(), 'Should return 2 quotes');
	}

	@IsTest
	static void testGetQuotesByRevision_wrapperFields() {
		Design_Revision__c revision = [SELECT Id FROM Design_Revision__c LIMIT 1];
		Quote q = [SELECT Id, Name, Status, Quote_Type__c FROM Quote WHERE Quote_Type__c = 'Material' LIMIT 1];

		Test.startTest();
		List<DesignRevisionQuotesController.QuoteWrapper> result =
			DesignRevisionQuotesController.getQuotesByRevision(revision.Id);
		Test.stopTest();

		DesignRevisionQuotesController.QuoteWrapper materialWrapper;
		for (DesignRevisionQuotesController.QuoteWrapper w : result) {
			if (w.quoteType == 'Material') {
				materialWrapper = w;
				break;
			}
		}

		Assert.isNotNull(materialWrapper, 'Material wrapper should exist');
		Assert.areEqual(q.Id, materialWrapper.id);
		Assert.areEqual('Material Quote', materialWrapper.name);
		Assert.areEqual('Draft', materialWrapper.status);
		Assert.areEqual('Material', materialWrapper.quoteType);
		Assert.isTrue(materialWrapper.recordUrl.contains(q.Id), 'recordUrl should contain quote Id');
	}

	@IsTest
	static void testGetQuotesByRevision_emptyRevision() {
		Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

		Design_Revision__c emptyRevision = new Design_Revision__c(
			Opportunity__c = opp.Id,
			Revision_Number__c = '01',
			Revision_Reason__c = 'Customer Revision'
		);
		insert emptyRevision;

		Test.startTest();
		List<DesignRevisionQuotesController.QuoteWrapper> result =
			DesignRevisionQuotesController.getQuotesByRevision(emptyRevision.Id);
		Test.stopTest();

		Assert.areEqual(0, result.size(), 'Should return empty list for revision with no quotes');
	}
}