@IsTest
private class LogRetentionPolicySelectorTest {

	private static Log_Retention_Policy__mdt policy(String developerName, String objectName, Boolean active) {
		return new Log_Retention_Policy__mdt(
			DeveloperName = developerName,
			Object_API_Name__c = objectName,
			Retention_Days__c = 30,
			Active__c = active,
			Hard_Delete__c = true
		);
	}

	@IsTest
	static void returnsOnlyActivePolicies() {
		LogRetentionPolicySelector.policyOverride = new List<Log_Retention_Policy__mdt>{
			policy('Integration_Log', 'Integration_Log__c', true),
			policy('Bolt_Error_Log', 'Bolt_Error_Log__c', false)
		};

		List<Log_Retention_Policy__mdt> active = LogRetentionPolicySelector.getActivePolicies();

		Assert.areEqual(1, active.size(), 'The inactive policy should be filtered out');
		Assert.areEqual(
			'Integration_Log__c',
			active[0].Object_API_Name__c,
			'The remaining policy should be the active one'
		);
	}

	@IsTest
	static void ordersPoliciesByDeveloperName() {
		LogRetentionPolicySelector.policyOverride = new List<Log_Retention_Policy__mdt>{
			policy('Integration_Log', 'Integration_Log__c', true),
			policy('Bolt_Error_Log', 'Bolt_Error_Log__c', true)
		};

		List<Log_Retention_Policy__mdt> active = LogRetentionPolicySelector.getActivePolicies();

		Assert.areEqual(2, active.size(), 'Both active policies should come back');
		Assert.areEqual(
			'Bolt_Error_Log',
			active[0].DeveloperName,
			'Policies should be ordered by developer name so nightly runs stay comparable'
		);
		Assert.areEqual('Integration_Log', active[1].DeveloperName, 'Integration_Log should sort second');
	}

	@IsTest
	static void keepsPoliciesApartWhenDeveloperNameIsMissing() {
		LogRetentionPolicySelector.policyOverride = new List<Log_Retention_Policy__mdt>{
			policy(null, 'Integration_Log__c', true),
			policy(null, 'Bolt_Error_Log__c', true)
		};

		Assert.areEqual(
			2,
			LogRetentionPolicySelector.getActivePolicies().size(),
			'Nameless policies must not collapse into one another'
		);
	}

	@IsTest
	static void returnsEmptyListWhenNothingIsActive() {
		LogRetentionPolicySelector.policyOverride = new List<Log_Retention_Policy__mdt>{
			policy('Integration_Log', 'Integration_Log__c', false)
		};

		Assert.isTrue(
			LogRetentionPolicySelector.getActivePolicies().isEmpty(),
			'No active policy should yield an empty list rather than null'
		);
	}

	@IsTest
	static void readsRealMetadataWhenNoOverrideIsSet() {
		// Exercises the CMDT path. The deployed policies are Integration_Log and
		// Bolt_Error_Log, but the assertion stays permissive so switching one off in
		// production does not break the test.
		List<Log_Retention_Policy__mdt> active = LogRetentionPolicySelector.getActivePolicies();

		Assert.isNotNull(active, 'Reading real metadata should never return null');
		for (Log_Retention_Policy__mdt deployed : active) {
			Assert.isTrue(deployed.Active__c, 'Only active policies may come back from the selector');
		}
	}
}
