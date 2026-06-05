@IsTest
private class OpportunityAmountServiceTest {

	private static final String TYPE_MATERIAL = 'Material';
	private static final String TYPE_STAMP = 'Stamp';
	private static final String TYPE_EXTRA = 'Extra';
	private static final Decimal WATTAGE_KW = 10; // 10 kW => 10000 W

	@TestSetup
	static void setup() {
		Account acc = new Account(Name = 'OAS Account');
		insert acc;

		Opportunity opp = new Opportunity(
			Name = 'OAS Opportunity',
			AccountId = acc.Id,
			StageName = 'Qualification',
			CloseDate = Date.today().addDays(30)
		);
		insert opp;

		Product2 product = new Product2(Name = 'OAS Product', IsActive = true);
		insert product;

		insert new PricebookEntry(
			Pricebook2Id = Test.getStandardPricebookId(),
			Product2Id = product.Id,
			UnitPrice = 1,
			IsActive = true
		);
	}

	private static Id getOppId() {
		return [SELECT Id FROM Opportunity LIMIT 1].Id;
	}

	private static Design_Revision__c createRevision(Id oppId) {
		Design_Revision__c dr = new Design_Revision__c(
			Opportunity__c = oppId,
			Revision_Number__c = '00',
			Project_Wattage_kW__c = WATTAGE_KW,
			Is_Active__c = false
		);
		insert dr;
		return dr;
	}

	private static void linkActiveRevision(Id oppId, Id drId) {
		update new Opportunity(Id = oppId, Design_Revision__c = drId);
	}

	private static Quote createQuote(Id oppId, Id drId, String type, Decimal total, Boolean active) {
		PricebookEntry pbe = [SELECT Id, Product2Id FROM PricebookEntry LIMIT 1];

		Quote q = new Quote(
			Name = 'Q ' + type,
			OpportunityId = oppId,
			Pricebook2Id = Test.getStandardPricebookId(),
			ExpirationDate = Date.today().addDays(30),
			Quote_Type__c = type,
			Design_Revision__c = drId,
			Active__c = active
		);
		TriggerHandler.bypass(Constants.QUOTE_HANDLER_NAME);
		try {
			insert q;
		} finally {
			TriggerHandler.clearBypass(Constants.QUOTE_HANDLER_NAME);
		}

		insert new QuoteLineItem(
			QuoteId = q.Id,
			PricebookEntryId = pbe.Id,
			Product2Id = pbe.Product2Id,
			Quantity = 1,
			UnitPrice = total
		);
		return q;
	}

	private static Opportunity reloadOpp(Id oppId) {
		return [
			SELECT Amount_Material__c, Amount_Stamp__c, Amount_Extra__c, Quotes_Total__c, Price_Per_Watt__c
			FROM Opportunity
			WHERE Id = :oppId
		];
	}

	@IsTest
	static void testRecalculate_allThreeTypes() {
		Id oppId = getOppId();
		Design_Revision__c dr = createRevision(oppId);
		createQuote(oppId, dr.Id, TYPE_MATERIAL, 1000, true);
		createQuote(oppId, dr.Id, TYPE_STAMP, 200, true);
		createQuote(oppId, dr.Id, TYPE_EXTRA, 50, true);
		linkActiveRevision(oppId, dr.Id);

		Test.startTest();
		OpportunityAmountService.recalculate(new Set<Id>{ oppId });
		Test.stopTest();

		Opportunity opp = reloadOpp(oppId);
		Assert.areEqual(1000, opp.Amount_Material__c);
		Assert.areEqual(200, opp.Amount_Stamp__c);
		Assert.areEqual(50, opp.Amount_Extra__c);
		Assert.areEqual(1250, opp.Quotes_Total__c, 'Quotes_Total__c formula = Material + Stamp + Extra');
		Assert.areEqual(0.10, opp.Price_Per_Watt__c, 'Price Per Watt = Amount_Material / (wattageKw * 1000)');
	}

	@IsTest
	static void testRecalculate_onlyMaterial() {
		Id oppId = getOppId();
		Design_Revision__c dr = createRevision(oppId);
		createQuote(oppId, dr.Id, TYPE_MATERIAL, 1000, true);
		linkActiveRevision(oppId, dr.Id);

		Test.startTest();
		OpportunityAmountService.recalculate(new Set<Id>{ oppId });
		Test.stopTest();

		Opportunity opp = reloadOpp(oppId);
		Assert.areEqual(1000, opp.Amount_Material__c);
		Assert.areEqual(0, opp.Amount_Stamp__c);
		Assert.areEqual(0, opp.Amount_Extra__c);
	}

	@IsTest
	static void testRecalculate_multipleStamps() {
		Id oppId = getOppId();
		Design_Revision__c dr = createRevision(oppId);
		createQuote(oppId, dr.Id, TYPE_STAMP, 200, true);
		createQuote(oppId, dr.Id, TYPE_STAMP, 300, false);
		linkActiveRevision(oppId, dr.Id);

		Test.startTest();
		OpportunityAmountService.recalculate(new Set<Id>{ oppId });
		Test.stopTest();

		Opportunity opp = reloadOpp(oppId);
		Assert.areEqual(200, opp.Amount_Stamp__c, 'Only the active Stamp Quote should contribute');
	}

	@IsTest
	static void testRecalculate_noActiveQuotes() {
		Id oppId = getOppId();
		Design_Revision__c dr = createRevision(oppId);
		createQuote(oppId, dr.Id, TYPE_MATERIAL, 1000, false);
		linkActiveRevision(oppId, dr.Id);

		Test.startTest();
		OpportunityAmountService.recalculate(new Set<Id>{ oppId });
		Test.stopTest();

		Opportunity opp = reloadOpp(oppId);
		Assert.areEqual(0, opp.Amount_Material__c);
		Assert.areEqual(0, opp.Amount_Stamp__c);
		Assert.areEqual(0, opp.Amount_Extra__c);
		Assert.isNull(opp.Price_Per_Watt__c, 'No active Material means no price per watt');
	}

	@IsTest
	static void testRecalculate_noActiveDR() {
		Id oppId = getOppId();
		// Opportunity.Design_Revision__c stays null.

		Test.startTest();
		OpportunityAmountService.recalculate(new Set<Id>{ oppId });
		Test.stopTest();

		Opportunity opp = reloadOpp(oppId);
		Assert.areEqual(0, opp.Amount_Material__c);
		Assert.areEqual(0, opp.Amount_Stamp__c);
		Assert.areEqual(0, opp.Amount_Extra__c);
		Assert.isNull(opp.Price_Per_Watt__c);
	}

	@IsTest
	static void testRecalculate_bulk() {
		Account acc = [SELECT Id FROM Account LIMIT 1];
		PricebookEntry pbe = [SELECT Id, Product2Id FROM PricebookEntry LIMIT 1];
		Id pbId = Test.getStandardPricebookId();

		Integer total = 50;

		List<Opportunity> opps = new List<Opportunity>();
		for (Integer i = 0; i < total; i++) {
			opps.add(new Opportunity(
				Name = 'Bulk Opp ' + i,
				AccountId = acc.Id,
				StageName = 'Qualification',
				CloseDate = Date.today().addDays(30)
			));
		}
		insert opps;

		List<Design_Revision__c> revisions = new List<Design_Revision__c>();
		for (Opportunity opp : opps) {
			revisions.add(new Design_Revision__c(
				Opportunity__c = opp.Id,
				Revision_Number__c = '00',
				Project_Wattage_kW__c = WATTAGE_KW,
				Is_Active__c = false
			));
		}
		insert revisions;

		List<Quote> quotes = new List<Quote>();
		for (Integer i = 0; i < total; i++) {
			quotes.add(new Quote(
				Name = 'Bulk Q ' + i,
				OpportunityId = opps[i].Id,
				Pricebook2Id = pbId,
				ExpirationDate = Date.today().addDays(30),
				Quote_Type__c = TYPE_MATERIAL,
				Design_Revision__c = revisions[i].Id,
				Active__c = true
			));
		}
		TriggerHandler.bypass(Constants.QUOTE_HANDLER_NAME);
		try {
			insert quotes;
		} finally {
			TriggerHandler.clearBypass(Constants.QUOTE_HANDLER_NAME);
		}

		List<QuoteLineItem> qlis = new List<QuoteLineItem>();
		for (Quote q : quotes) {
			qlis.add(new QuoteLineItem(
				QuoteId = q.Id,
				PricebookEntryId = pbe.Id,
				Product2Id = pbe.Product2Id,
				Quantity = 1,
				UnitPrice = 1000
			));
		}
		insert qlis;

		List<Opportunity> oppLinks = new List<Opportunity>();
		Set<Id> oppIds = new Set<Id>();
		for (Integer i = 0; i < total; i++) {
			oppLinks.add(new Opportunity(Id = opps[i].Id, Design_Revision__c = revisions[i].Id));
			oppIds.add(opps[i].Id);
		}
		update oppLinks;

		Test.startTest();
		OpportunityAmountService.recalculate(oppIds);
		Test.stopTest();

		List<Opportunity> reloaded = [SELECT Amount_Material__c FROM Opportunity WHERE Id IN :oppIds];
		Assert.areEqual(total, reloaded.size());
		for (Opportunity opp : reloaded) {
			Assert.areEqual(1000, opp.Amount_Material__c, 'Every Opportunity in the bulk run should aggregate its active Material Quote');
		}
	}

	@IsTest
	static void testSetAsActive_triggersRecalculate() {
		Id oppId = getOppId();
		Design_Revision__c dr = createRevision(oppId);
		createQuote(oppId, dr.Id, TYPE_MATERIAL, 1000, true);

		Test.startTest();
		update new Design_Revision__c(Id = dr.Id, Is_Active__c = true);
		Test.stopTest();

		Opportunity opp = reloadOpp(oppId);
		Assert.areEqual(1000, opp.Amount_Material__c,
			'Activating the Design Revision should trigger Opportunity amount recalculation');
	}

	@IsTest
	static void testRecalculate_pricePerWattRoundsToCents() {
		Id oppId = getOppId();
		Design_Revision__c dr = new Design_Revision__c(
			Opportunity__c = oppId,
			Revision_Number__c = '00',
			Project_Wattage_kW__c = 6, // 6000 W
			Is_Active__c = false
		);
		insert dr;
		createQuote(oppId, dr.Id, TYPE_MATERIAL, 1000, true);
		linkActiveRevision(oppId, dr.Id);

		Test.startTest();
		OpportunityAmountService.recalculate(new Set<Id>{ oppId });
		Test.stopTest();

		Opportunity opp = reloadOpp(oppId);
		// 1000 / 6000 = 0.16666... -> rounded HALF_UP to 0.17 at the Currency field.
		Assert.areEqual(0.17, opp.Price_Per_Watt__c,
			'Price Per Watt must round to cents the same way the Quote formula does');
	}
}
