@IsTest
private class LogRetentionSchedulerTest {

	private static Log_Retention_Policy__mdt integrationLogPolicy() {
		return new Log_Retention_Policy__mdt(
			DeveloperName = 'Integration_Log',
			Object_API_Name__c = 'Integration_Log__c',
			Retention_Days__c = 30,
			Active__c = true,
			Hard_Delete__c = true
		);
	}

	private static List<Integration_Log__c> insertAgedLogs(Integer count, Integer daysOld) {
		List<Integration_Log__c> logs = new List<Integration_Log__c>();
		for (Integer i = 0; i < count; i++) {
			logs.add(new Integration_Log__c(Integration_Name__c = 'Scheduler Retention Test ' + i));
		}
		insert logs;
		for (Integration_Log__c log : logs) {
			Test.setCreatedDate(log.Id, Datetime.now().addDays(-daysOld));
		}
		return logs;
	}

	@IsTest
	static void registersOnTheNightlyMidnightExpression() {
		// This test is about the schedule itself, so no policy is active — the deployed
		// metadata is exercised in LogRetentionPolicySelectorTest instead.
		LogRetentionPolicySelector.policyOverride = new List<Log_Retention_Policy__mdt>();

		Test.startTest();
		String jobId = System.schedule(
			Constants.LOG_RETENTION_JOB_NAME,
			Constants.LOG_RETENTION_CRON_MIDNIGHT,
			new LogRetentionScheduler()
		);
		Test.stopTest();

		CronTrigger scheduled = [SELECT CronExpression FROM CronTrigger WHERE Id = :jobId];
		Assert.areEqual(
			Constants.LOG_RETENTION_CRON_MIDNIGHT,
			scheduled.CronExpression,
			'The job should be registered to run at midnight every day'
		);
	}

	@IsTest
	static void executePurgesAgedRecordsForEveryActivePolicy() {
		List<Integration_Log__c> logs = insertAgedLogs(3, 45);
		LogRetentionPolicySelector.policyOverride = new List<Log_Retention_Policy__mdt>{
			integrationLogPolicy()
		};

		// execute() is invoked directly rather than through System.schedule: a batch
		// enqueued by a scheduled job during Test.stopTest() is not reliably run inside
		// the test, and this covers the same code path.
		Test.startTest();
		new LogRetentionScheduler().execute(null);
		Test.stopTest();

		Assert.areEqual(
			0,
			[SELECT COUNT() FROM Integration_Log__c WHERE Id IN :logs],
			'The scheduled run should have purged the aged records'
		);
	}

	@IsTest
	static void executeIsHarmlessWhenNoPolicyIsActive() {
		List<Integration_Log__c> logs = insertAgedLogs(1, 90);
		LogRetentionPolicySelector.policyOverride = new List<Log_Retention_Policy__mdt>();

		Test.startTest();
		new LogRetentionScheduler().execute(null);
		Test.stopTest();

		Assert.areEqual(
			1,
			[SELECT COUNT() FROM Integration_Log__c WHERE Id IN :logs],
			'With no active policy nothing may be deleted, however old the record is'
		);
	}
}
