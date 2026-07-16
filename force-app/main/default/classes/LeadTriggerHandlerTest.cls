@IsTest
private class LeadTriggerHandlerTest {

	private static final String LEAD_STREET = '123 Solar Ave';
	private static final String LEAD_CITY = 'Phoenix';
	private static final String LEAD_STATE = 'Arizona';
	private static final String LEAD_POSTAL = '85001';
	private static final String LEAD_COUNTRY = 'United States';

	private static Lead buildLead(String suffix) {
		return new Lead(
			FirstName = 'Test',
			LastName = 'Lead ' + suffix,
			Company = 'Acme ' + suffix,
			Status = 'New',
			Distributor_Type__c = 'Direct',
			Street = LEAD_STREET,
			City = LEAD_CITY,
			State = LEAD_STATE,
			PostalCode = LEAD_POSTAL,
			Country = LEAD_COUNTRY
		);
	}

	private static Database.LeadConvertResult convert(Lead l, Id existingAccountId) {
		Database.LeadConvert lc = new Database.LeadConvert();
		lc.setLeadId(l.Id);
		LeadStatus convertedStatus = [SELECT MasterLabel FROM LeadStatus WHERE IsConverted = true LIMIT 1];
		lc.setConvertedStatus(convertedStatus.MasterLabel);
		if (existingAccountId != null) {
			lc.setAccountId(existingAccountId);
		}
		return Database.convertLead(lc);
	}

	@IsTest
	static void convert_newAccount_clearsBillingAndPopulatesOpportunity() {
		Lead l = buildLead('new');
		insert l;

		Test.startTest();
		Database.LeadConvertResult result = convert(l, null);
		Test.stopTest();

		Assert.isTrue(result.isSuccess(), 'Lead conversion should succeed');

		Account acc = [
			SELECT BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry,
				BillingLatitude, BillingLongitude, Created_From_Lead_Conversion__c
			FROM Account
			WHERE Id = :result.getAccountId()
		];
		Assert.isTrue(acc.Created_From_Lead_Conversion__c, 'Flag should be set on new account');
		Assert.isNull(acc.BillingStreet, 'Billing street should be cleared on new account');
		Assert.isNull(acc.BillingCity);
		Assert.isNull(acc.BillingState);
		Assert.isNull(acc.BillingPostalCode);
		Assert.isNull(acc.BillingCountry);
		Assert.isNull(acc.BillingLatitude);
		Assert.isNull(acc.BillingLongitude);

		Opportunity opp = [
			SELECT Project_Street__c, Project_City__c, Project_State__c, Project_State_Code__c,
				Project_PostalCode__c, Project_Country__c
			FROM Opportunity
			WHERE Id = :result.getOpportunityId()
		];
		Assert.areEqual(LEAD_STREET, opp.Project_Street__c);
		Assert.areEqual(LEAD_CITY, opp.Project_City__c);
		Assert.areEqual(LEAD_STATE, opp.Project_State__c);
		Assert.areEqual('AZ', opp.Project_State_Code__c, 'State code should be copied from Lead.StateCode on conversion');
		Assert.areEqual(LEAD_POSTAL, opp.Project_PostalCode__c);
		Assert.areEqual(LEAD_COUNTRY, opp.Project_Country__c);
	}

	@IsTest
	static void nonConversionUpdate_doesNotChangeOpportunityOrAccount() {
		Lead l = buildLead('plain');
		insert l;

		Test.startTest();
		l.Priority__c = 'Medium';
		l.Discount__c = 10;
		l.Status = 'Working';
		update l;
		Test.stopTest();

		Assert.areEqual(0, [SELECT COUNT() FROM Opportunity]);
		Assert.areEqual(0, [SELECT COUNT() FROM Account]);
	}
}
