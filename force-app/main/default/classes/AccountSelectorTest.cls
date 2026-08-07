@IsTest
private class AccountSelectorTest {

	@TestSetup
	static void setup() {
		insert new Account(
			Name             = 'Account Selector Test',
			Naming_Acronym__c = 'AST'
		);
	}

	private static Account getAccount() {
		return [SELECT Id FROM Account LIMIT 1];
	}

	@IsTest
	static void testGetAccountsByIds() {
		Account acc = getAccount();
		List<Account> result = AccountSelector.getAccountsByIds(new Set<Id>{ acc.Id });
		Assert.areEqual(1, result.size(), 'Should return the one account');
		Assert.areEqual(acc.Id, result[0].Id);
	}

	@IsTest
	static void testGetNamingAcronymsByIds() {
		Account acc = getAccount();
		List<Account> result = AccountSelector.getNamingAcronymsByIds(new Set<Id>{ acc.Id });
		Assert.areEqual(1, result.size(), 'Should return the one account');
		Assert.areEqual('AST', result[0].Naming_Acronym__c);
	}
}
