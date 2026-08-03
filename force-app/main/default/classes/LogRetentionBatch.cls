/**
 * Deletes expired records for one Log_Retention_Policy__mdt, then chains itself for the
 * next policy in the queue. One batch handles one object because a QueryLocator is tied
 * to a single sObject type; chaining keeps the whole nightly clean-up behind a single
 * scheduled entry point.
 *
 * Stateful so the per-chunk counts survive into finish(), where the run is reported.
 * Runs `without sharing` for the same reason as LogRetentionService: housekeeping has to
 * see every ageing record, not just the ones the scheduling user owns.
 *
 * How to tell whether a run went through: every execution leaves an AsyncApexJob row
 * (Setup -> Apex Jobs) carrying Status and NumberOfErrors, and finish() writes a
 * one-line summary to the debug log. Only genuine failures reach BoltErrorLogger, so a
 * clean night stays silent instead of generating noise.
 */
public without sharing class LogRetentionBatch implements Database.Batchable<SObject>, Database.Stateful {

	private static final String CLASS_NAME = 'LogRetentionBatch';

	private final Log_Retention_Policy__mdt policy;
	private final List<Log_Retention_Policy__mdt> remaining;

	private Integer deleted = 0;
	private Integer failed = 0;
	private final List<String> errors = new List<String>();

	private LogRetentionBatch(Log_Retention_Policy__mdt policy, List<Log_Retention_Policy__mdt> remaining) {
		this.policy = policy;
		this.remaining = remaining;
	}

	/**
	 * Starts the clean-up for the first policy that passes validation and returns its job
	 * Id, or null when nothing is left to run. Invalid policies are logged and skipped
	 * rather than aborting the run — one bad config row should not stop the other objects
	 * from being purged.
	 */
	public static Id run(List<Log_Retention_Policy__mdt> policies) {
		List<Log_Retention_Policy__mdt> queue = (policies == null)
			? new List<Log_Retention_Policy__mdt>()
			: policies.clone();

		while (!queue.isEmpty()) {
			Log_Retention_Policy__mdt next = queue.remove(0);
			String problem = LogRetentionService.validate(next);

			if (problem == null) {
				return Database.executeBatch(
					new LogRetentionBatch(next, queue),
					Constants.LOG_RETENTION_BATCH_SIZE
				);
			}

			logError('run', 'Skipping policy ' + next.DeveloperName + ' - ' + problem);
		}
		return null;
	}

	public Database.QueryLocator start(Database.BatchableContext context) {
		return LogRetentionService.expiredRecordsLocator(policy);
	}

	public void execute(Database.BatchableContext context, List<SObject> scope) {
		LogRetentionService.PurgeResult result = LogRetentionService.purge(scope, policy.Hard_Delete__c == true);

		deleted += result.deleted;
		failed += result.failed;
		for (String error : result.errors) {
			if (errors.size() < Constants.LOG_RETENTION_MAX_TRACKED_ERRORS) {
				errors.add(error);
			}
		}
	}

	public void finish(Database.BatchableContext context) {
		System.debug(Constants.LOG_RETENTION_DEBUG_PREFIX + summary());

		if (failed > 0 || !errors.isEmpty()) {
			logError('finish', summary() + ' | ' + String.join(errors, ' ; '));
		}

		// A test context allows only one batch per transaction, so chaining is skipped
		// there; LogRetentionBatchTest covers the queue handling directly instead.
		if (!Test.isRunningTest()) {
			run(remaining);
		}
	}

	@TestVisible
	private String summary() {
		return policy.Object_API_Name__c +
			': deleted ' + deleted +
			', failed ' + failed +
			' (older than ' + policy.Retention_Days__c + ' days)';
	}

	private static void logError(String methodName, String message) {
		BoltErrorLogger.logError(
			CLASS_NAME,
			methodName,
			Constants.LOG_RETENTION_ERROR_CATEGORY + ': ' + message,
			null,
			Constants.SOURCE_TYPE_APEX,
			Constants.SEVERITY_ERROR,
			UserInfo.getUserId(),
			null
		);
	}
}
