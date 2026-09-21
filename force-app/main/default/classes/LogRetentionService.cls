/**
 * Deletes ageing log records according to a Log_Retention_Policy__mdt.
 *
 * Runs `without sharing` deliberately: retention is org-wide housekeeping, so it has to
 * remove every record past its cutoff regardless of who owns it or what the scheduling
 * user happens to see.
 */
public without sharing class LogRetentionService {

	/** Outcome of purging one batch scope; the batch accumulates these across chunks. */
	public class PurgeResult {
		public Integer deleted = 0;
		public Integer failed = 0;
		// True once the recycle bin has actually been emptied for this scope. Emptying it
		// is invisible to a query — ALL ROWS keeps returning the rows either way, inside a
		// test as well as outside — so this flag is the only way to confirm it happened.
		public Boolean recycleBinEmptied = false;
		public List<String> errors = new List<String>();
	}

	/**
	 * Returns null when the policy is safe to run, otherwise the reason it is not.
	 * Callers must run this before enqueuing the batch: a Batchable cannot refuse to
	 * start once it is running, and this is also what guarantees the object name
	 * interpolated into the SOQL below is a real object rather than arbitrary text.
	 *
	 * @param policy the retention policy to validate
	 * @return null when the policy is valid, otherwise the validation error
	 */
	public static String validate(Log_Retention_Policy__mdt policy) {
		if (policy == null) {
			return 'Policy is null.';
		}
		if (String.isBlank(policy.Object_API_Name__c)) {
			return 'Object API Name is blank.';
		}
		if (policy.Retention_Days__c == null || policy.Retention_Days__c < 1) {
			return 'Retention Days must be 1 or more (was: ' + policy.Retention_Days__c + ').';
		}

		SObjectType objectType = Schema.getGlobalDescribe().get(policy.Object_API_Name__c);
		if (objectType == null) {
			return 'Unknown object: ' + policy.Object_API_Name__c;
		}
		if (!objectType.getDescribe().isDeletable()) {
			return 'Object is not deletable: ' + policy.Object_API_Name__c;
		}
		return null;
	}

	public static Datetime cutoffFor(Log_Retention_Policy__mdt policy) {
		return Datetime.now().addDays(-Integer.valueOf(policy.Retention_Days__c));
	}

	/**
	 * Query locator over every record the policy considers expired. Run validate() first.
	 *
	 * @param policy the validated retention policy that defines the object and cutoff
	 * @return a query locator over the records older than the policy cutoff
	 */
	public static Database.QueryLocator expiredRecordsLocator(Log_Retention_Policy__mdt policy) {
		String query =
			'SELECT Id FROM ' + policy.Object_API_Name__c +
			' WHERE ' + Constants.LOG_RETENTION_DATE_FIELD + ' < :cutoff';

		return Database.getQueryLocatorWithBinds(
			query,
			new Map<String, Object>{ 'cutoff' => cutoffFor(policy) },
			AccessLevel.SYSTEM_MODE
		);
	}

	public static PurgeResult purge(List<SObject> scope, Boolean hardDelete) {
		PurgeResult result = new PurgeResult();
		if (scope == null || scope.isEmpty()) {
			return result;
		}

		// allOrNone = false: one record we cannot delete (a lock, a cascade restriction)
		// must not cost us the rest of the chunk.
		List<SObject> deletedRecords = new List<SObject>();
		List<Database.DeleteResult> deleteResults = Database.delete(scope, false);

		for (Integer i = 0; i < deleteResults.size(); i++) {
			Database.DeleteResult deleteResult = deleteResults[i];
			if (deleteResult.isSuccess()) {
				result.deleted++;
				deletedRecords.add(scope[i]);
			} else {
				result.failed++;
				addError(result, scope[i].Id + ': ' + firstError(deleteResult));
			}
		}

		if (hardDelete == true && !deletedRecords.isEmpty()) {
			try {
				Database.emptyRecycleBin(deletedRecords);
				result.recycleBinEmptied = true;
			} catch (Exception e) {
				// The records are deleted either way — they just linger in the recycle bin,
				// and in storage, for another 15 days. Worth reporting, not worth failing on.
				addError(result, 'emptyRecycleBin: ' + e.getMessage());
			}
		}

		return result;
	}

	/**
	 * Keeps a lid on the error list: the batch is Stateful, so an object failing on every
	 * single record would otherwise carry thousands of messages in the heap until finish().
	 *
	 * @param result the purge result whose bounded error list is updated
	 * @param message the error message to add when the limit has not been reached
	 */
	private static void addError(PurgeResult result, String message) {
		if (result.errors.size() < Constants.LOG_RETENTION_MAX_TRACKED_ERRORS) {
			result.errors.add(message);
		}
	}

	private static String firstError(Database.DeleteResult deleteResult) {
		List<Database.Error> errors = deleteResult.getErrors();
		return errors.isEmpty() ? 'Unknown error' : errors[0].getMessage();
	}
}
