@IsTest
private class DesignRevisionQuoteIntegrationTest {

	private static final String TYPE_MATERIAL = 'Material';
	private static final Decimal WATTAGE_KW = 10;
	private static final Decimal DR1_TOTAL = 1000;
	private static final Decimal DR2_TOTAL = 2000;

	@TestSetup
	static void setup() {
		Account acc = new Account(Name = 'DRQ Account');
		insert acc;

		Opportunity opp = new Opportunity(
			Name = 'DRQ Opportunity',
			AccountId = acc.Id,
			StageName = 'Qualification',
			CloseDate = Date.today().addDays(30)
		);
		insert opp;

		Product2 product = new Product2(Name = 'DRQ Product', IsActive = true);
		insert product;

		insert new PricebookEntry(
			Pricebook2Id = Test.getStandardPricebookId(),
			Product2Id = product.Id,
			UnitPrice = 1,
			IsActive = true
		);

		insert new Quote_Sequence__c(
			SetupOwnerId = UserInfo.getOrganizationId(),
			Last_Number__c = 0
		);

		Design_Revision__c dr1 = new Design_Revision__c(
			Opportunity__c = opp.Id,
			Revision_Number__c = '00',
			Project_Wattage_kW__c = WATTAGE_KW,
			Is_Active__c = false
		);
		Design_Revision__c dr2 = new Design_Revision__c(
			Opportunity__c = opp.Id,
			Revision_Number__c = '01',
			Project_Wattage_kW__c = WATTAGE_KW,
			Is_Active__c = false
		);
		insert new List<Design_Revision__c>{ dr1, dr2 };

		createActiveMaterialQuote(opp.Id, dr1.Id, DR1_TOTAL);
		createActiveMaterialQuote(opp.Id, dr2.Id, DR2_TOTAL);
	}

	private static void createActiveMaterialQuote(Id oppId, Id drId, Decimal total) {
		PricebookEntry pbe = [SELECT Id, Product2Id FROM PricebookEntry LIMIT 1];
		Quote q = new Quote(
			Name = 'DRQ Quote',
			OpportunityId = oppId,
			Pricebook2Id = Test.getStandardPricebookId(),
			ExpirationDate = Date.today().addDays(30),
			Quote_Type__c = TYPE_MATERIAL,
			Design_Revision__c = drId
		);
		insert q; // first Material of the DR -> auto-activated

		insert new QuoteLineItem(
			QuoteId = q.Id,
			PricebookEntryId = pbe.Id,
			Product2Id = pbe.Product2Id,
			Quantity = 1,
			UnitPrice = total
		);
	}

	private static Id getOppId() {
		return [SELECT Id FROM Opportunity LIMIT 1].Id;
	}

	private static Design_Revision__c getRevision(String revisionNumber) {
		return [SELECT Id FROM Design_Revision__c WHERE Revision_Number__c = :revisionNumber LIMIT 1];
	}

	private static Decimal materialAmount(Id oppId) {
		return [SELECT Amount_Material__c FROM Opportunity WHERE Id = :oppId].Amount_Material__c;
	}

	@IsTest
	static void testSetAsActiveUpdatesAmounts() {
		Id oppId = getOppId();
		Design_Revision__c dr2 = getRevision('01');

		Test.startTest();
		update new Design_Revision__c(Id = dr2.Id, Is_Active__c = true);
		Test.stopTest();

		Assert.areEqual(DR2_TOTAL, materialAmount(oppId),
			'Setting DR2 active should populate the Opportunity amounts from DR2 active Quotes');
	}

	@IsTest
	static void testSwitchActiveRevision_amountsSwitch() {
		Id oppId = getOppId();
		Design_Revision__c dr1 = getRevision('00');
		Design_Revision__c dr2 = getRevision('01');

		Test.startTest();
		update new Design_Revision__c(Id = dr1.Id, Is_Active__c = true);
		Assert.areEqual(DR1_TOTAL, materialAmount(oppId), 'After activating DR1 the amount should reflect DR1');

		update new Design_Revision__c(Id = dr2.Id, Is_Active__c = true);
		Test.stopTest();

		Assert.areEqual(DR2_TOTAL, materialAmount(oppId),
			'Switching the active revision to DR2 should switch the Opportunity amounts to DR2');
	}
}
