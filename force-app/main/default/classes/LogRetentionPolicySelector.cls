/**
 * All reads of Log_Retention_Policy__mdt — the admin-owned configuration saying which
 * log object gets purged, how old a record must be before it goes, and whether the
 * recycle bin is emptied afterwards.
 *
 * Policies come back sorted by developer name so the nightly run always processes them
 * in the same order. The batch chains one policy to the next, so a stable order keeps
 * the Apex Jobs history readable from one night to the next.
 */
public inherited sharing class LogRetentionPolicySelector {

	// CMDT rows cannot be inserted in a test, so tests inject their own policies here.
	@TestVisible
	private static List<Log_Retention_Policy__mdt> policyOverride;

	public static List<Log_Retention_Policy__mdt> getActivePolicies() {
		Map<String, Log_Retention_Policy__mdt> byName = new Map<String, Log_Retention_Policy__mdt>();
		for (Log_Retention_Policy__mdt policy : allPolicies()) {
			if (policy.Active__c == true) {
				// A blank developer name only happens for policies built in a test; keying
				// on the map size keeps them from silently overwriting each other.
				String key = String.isBlank(policy.DeveloperName)
					? String.valueOf(byName.size())
					: policy.DeveloperName;
				byName.put(key, policy);
			}
		}

		List<String> names = new List<String>(byName.keySet());
		names.sort();

		List<Log_Retention_Policy__mdt> ordered = new List<Log_Retention_Policy__mdt>();
		for (String name : names) {
			ordered.add(byName.get(name));
		}
		return ordered;
	}

	private static List<Log_Retention_Policy__mdt> allPolicies() {
		if (policyOverride != null) {
			return policyOverride;
		}
		return Log_Retention_Policy__mdt.getAll().values();
	}
}
