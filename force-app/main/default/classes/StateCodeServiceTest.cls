@IsTest
private class StateCodeServiceTest {

	private static Opportunity buildOpportunity(String name) {
		return new Opportunity(
			Name = name,
			StageName = 'Qualification',
			CloseDate = Date.today().addDays(30)
		);
	}

	@IsTest
	static void getCode_mapsUsStatesCanadianProvincesAndHandlesUnknowns() {
		Assert.areEqual('AZ', StateCodeService.getCode('Arizona'));
		Assert.areEqual('DC', StateCodeService.getCode('District of Columbia'));
		Assert.areEqual('ON', StateCodeService.getCode('Ontario'));
		Assert.areEqual('QC', StateCodeService.getCode('Quebec'));
		Assert.areEqual('CA', StateCodeService.getCode('  california  '), 'Lookup should be case-insensitive and trimmed');
		Assert.isNull(StateCodeService.getCode('Not A State'));
		Assert.isNull(StateCodeService.getCode(null));
		Assert.isNull(StateCodeService.getCode(''));
	}

	@IsTest
	static void insert_populatesStateCodeFromStateName() {
		Opportunity opp = buildOpportunity('SCS Insert');
		opp.Project_Country__c = 'United States';
		opp.Project_State__c = 'Maryland';

		Test.startTest();
		insert opp;
		Test.stopTest();

		opp = [SELECT Project_State_Code__c FROM Opportunity WHERE Id = :opp.Id];
		Assert.areEqual('MD', opp.Project_State_Code__c);
	}

	@IsTest
	static void update_recomputesStateCodeOnStateChangeAndClearsWhenStateCleared() {
		Opportunity opp = buildOpportunity('SCS Update');
		opp.Project_Country__c = 'United States';
		opp.Project_State__c = 'Maryland';
		insert opp;

		Test.startTest();
		opp.Project_State__c = 'Texas';
		update opp;
		Assert.areEqual('TX', [SELECT Project_State_Code__c FROM Opportunity WHERE Id = :opp.Id].Project_State_Code__c);

		opp.Project_State__c = null;
		update opp;
		Test.stopTest();

		Assert.isNull(
			[SELECT Project_State_Code__c FROM Opportunity WHERE Id = :opp.Id].Project_State_Code__c,
			'Clearing the state should clear the code'
		);
	}

	@IsTest
	static void update_explicitCodeInSameDmlWins() {
		Opportunity opp = buildOpportunity('SCS Explicit');
		insert opp;

		Test.startTest();
		opp.Project_Country__c = 'United States';
		opp.Project_State__c = 'Maryland';
		opp.Project_State_Code__c = 'MD-X';
		update opp;
		Test.stopTest();

		Assert.areEqual(
			'MD-X',
			[SELECT Project_State_Code__c FROM Opportunity WHERE Id = :opp.Id].Project_State_Code__c,
			'A code set explicitly in the same DML (e.g. by LeadService from Lead.StateCode) must not be overwritten'
		);
	}

	@IsTest
	static void update_untouchedStateLeavesCodeAlone() {
		Opportunity opp = buildOpportunity('SCS NoChange');
		opp.Project_Country__c = 'United States';
		opp.Project_State__c = 'Maryland';
		insert opp;

		Test.startTest();
		opp.Amount = 1000;
		update opp;
		Test.stopTest();

		Assert.areEqual('MD', [SELECT Project_State_Code__c FROM Opportunity WHERE Id = :opp.Id].Project_State_Code__c);
	}

	@IsTest
	static void bulk_insertPopulatesCodesFor200Records() {
		List<Opportunity> opps = new List<Opportunity>();
		for (Integer i = 0; i < 200; i++) {
			Opportunity opp = buildOpportunity('SCS Bulk ' + i);
			opp.Project_Country__c = Math.mod(i, 2) == 0 ? 'United States' : 'Canada';
			opp.Project_State__c = Math.mod(i, 2) == 0 ? 'Illinois' : 'Ontario';
			opps.add(opp);
		}

		Test.startTest();
		insert opps;
		Test.stopTest();

		Integer illinoisCount = 0, ontarioCount = 0;
		for (Opportunity opp : [SELECT Project_State_Code__c FROM Opportunity WHERE Name LIKE 'SCS Bulk %']) {
			if (opp.Project_State_Code__c == 'IL') illinoisCount++;
			if (opp.Project_State_Code__c == 'ON') ontarioCount++;
		}
		Assert.areEqual(100, illinoisCount);
		Assert.areEqual(100, ontarioCount);
	}
}
