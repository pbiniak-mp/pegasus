public inherited sharing class AccountSelector {

	public static List<Account> getAccountsByIds(Set<Id> ids) {
		return [
			SELECT
				Id,
				CreatedDate,
				BillingStreet,
				BillingCity,
				BillingState,
				BillingPostalCode,
				BillingCountry,
				BillingLatitude,
				BillingLongitude,
				Created_From_Lead_Conversion__c
			FROM Account
			WHERE Id IN :ids
		];
	}
}
