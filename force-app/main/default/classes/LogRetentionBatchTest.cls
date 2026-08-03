@IsTest
private class LogRetentionBatchTest {

	private static Log_Retention_Policy__mdt policy(String objectName, Decimal days, Boolean hardDelete) {
		return new Log_Retention_Policy__mdt(
			DeveloperName = 'Test_' + objectName,
			Object_API_Name__c = objectName,
			Retention_Days__c = days,
			Active__c = true,
			Hard_Delete__c = hardDelete
		);
	}

	private static List<Integration_Log__c> insertLogs(Integer count) {
		List<Integration_Log__c> logs = new List<Integration_Log__c>();
		for (Integer i = 0; i < count; i++) {
			logs.add(new Integration_Log__c(Integration_Name__c = 'Batch Retention Test ' + i));
		}
		insert logs;
		return logs;
	}

	private static void age(List<Integration_Log__c> logs, Integer fromIndex, Integer toIndex, Integer daysOld) {
		for (Integer i = fromIndex; i < toIndex; i++) {
			Test.setCreatedDate(logs[i].Id, Datetime.now().addDays(-daysOld));
		}
	}

	@IsTest
	static void deletesOnlyRecordsOlderThanTheRetentionWindow() {
		List<Integration_Log__c> logs = insertLogs(5);
		age(logs, 0, 3, 45);

		Test.startTest();
		LogRetentionBatch.run(new List<Log_Retention_Policy__mdt>{ policy('Integration_Log__c', 30, true) });
		Test.stopTest();

		Set<Id> survivors = new Map<Id, Integration_Log__c>(
			[SELECT Id FROM Integration_Log__c WHERE Id IN :logs]
		).keySet();

		Assert.areEqual(2, survivors.size(), 'The two recent records should survive');
		Assert.isTrue(survivors.contains(logs[3].Id), 'A record created today must be kept');
		Assert.isTrue(survivors.contains(logs[4].Id), 'A record created today must be kept');
		Assert.isFalse(survivors.contains(logs[0].Id), 'A 45-day-old record must be purged');
	}

	@IsTest
	static void hardDeleteClearsTheRecycleBin() {
		List<Integration_Log__c> logs = insertLogs(3);
		age(logs, 0, 3, 60);
		Set<Id> ids = new Map<Id, Integration_Log__c>(logs).keySet();

		Test.startTest();
		LogRetentionBatch.run(new List<Log_Retention_Policy__mdt>{ policy('Integration_Log__c', 30, true) });
		Test.stopTest();

		Assert.areEqual(
			0,
			[SELECT COUNT() FROM Integration_Log__c WHERE Id IN :ids ALL ROWS],
			'Hard delete should reclaim the storage rather than parking records in the bin'
		);
	}

	@IsTest
	static void softDeleteLeavesRecordsRecoverable() {
		List<Integration_Log__c> logs = insertLogs(3);
		age(logs, 0, 3, 60);
		Set<Id> ids = new Map<Id, Integration_Log__c>(logs).keySet();

		Test.startTest();
		LogRetentionBatch.run(new List<Log_Retention_Policy__mdt>{ policy('Integration_Log__c', 30, false) });
		Test.stopTest();

		Assert.areEqual(
			0,
			[SELECT COUNT() FROM Integration_Log__c WHERE Id IN :ids],
			'The records should no longer be live'
		);
		Assert.areEqual(
			3,
			[SELECT COUNT() FROM Integration_Log__c WHERE Id IN :ids ALL ROWS],
			'Without hard delete the records stay recoverable from the recycle bin'
		);
	}

	@IsTest
	static void purgesMoreRecordsThanFitInASingleChunk() {
		// Seven aged records against a scope of two forces four chunks — the case where a
		// non-stateful or non-bulkified implementation would drop records or lose counts.
		List<Integration_Log__c> logs = insertLogs(9);
		age(logs, 0, 7, 90);
		LogRetentionBatch.batchSizeOverride = 2;

		Test.startTest();
		LogRetentionBatch.run(new List<Log_Retention_Policy__mdt>{ policy('Integration_Log__c', 30, true) });
		Test.stopTest();

		Set<Id> survivors = new Map<Id, Integration_Log__c>(
			[SELECT Id FROM Integration_Log__c WHERE Id IN :logs]
		).keySet();

		Assert.areEqual(2, survivors.size(), 'Only the two current records should remain');
		Assert.isTrue(survivors.contains(logs[7].Id), 'A record created today must survive every chunk');
		Assert.isTrue(survivors.contains(logs[8].Id), 'A record created today must survive every chunk');
	}

	@IsTest
	static void doesNothingWhenNoRecordHasAgedOut() {
		List<Integration_Log__c> logs = insertLogs(4);

		Test.startTest();
		LogRetentionBatch.run(new List<Log_Retention_Policy__mdt>{ policy('Integration_Log__c', 30, true) });
		Test.stopTest();

		Assert.areEqual(
			4,
			[SELECT COUNT() FROM Integration_Log__c WHERE Id IN :logs],
			'A run with nothing to purge must leave the data untouched'
		);
	}

	@IsTest
	static void skipsInvalidPolicyAndRunsTheNextValidOne() {
		List<Integration_Log__c> logs = insertLogs(2);
		age(logs, 0, 2, 45);

		Test.startTest();
		// The bad policy must not stop the good one behind it from running.
		Id jobId = LogRetentionBatch.run(
			new List<Log_Retention_Policy__mdt>{
				policy('Not_A_Real_Object__c', 30, true),
				policy('Integration_Log__c', 30, true)
			}
		);
		Test.stopTest();

		Assert.isNotNull(jobId, 'The valid policy behind the broken one should still start a job');
		Assert.areEqual(
			0,
			[SELECT COUNT() FROM Integration_Log__c WHERE Id IN :logs],
			'The valid policy should have purged its aged records'
		);
	}

	@IsTest
	static void returnsNullWhenThereIsNothingRunnable() {
		Test.startTest();
		Id fromEmpty = LogRetentionBatch.run(new List<Log_Retention_Policy__mdt>());
		Id fromNull = LogRetentionBatch.run(null);
		Id fromAllInvalid = LogRetentionBatch.run(
			new List<Log_Retention_Policy__mdt>{ policy('Not_A_Real_Object__c', 30, true) }
		);
		Test.stopTest();

		Assert.isNull(fromEmpty, 'An empty queue starts no job');
		Assert.isNull(fromNull, 'A null queue starts no job');
		Assert.isNull(fromAllInvalid, 'A queue of only invalid policies starts no job');
	}

	@IsTest
	static void purgesBoltErrorLogsToo() {
		// The second object in the nightly queue: proves the batch is genuinely generic
		// and not written around Integration_Log__c.
		Bolt_Error_Log__c errorLog = new Bolt_Error_Log__c(
			Error_Message__c = 'Retention test error',
			Source_Type__c = Constants.SOURCE_TYPE_APEX,
			Severity__c = Constants.SEVERITY_ERROR
		);
		insert errorLog;
		Test.setCreatedDate(errorLog.Id, Datetime.now().addDays(-45));

		Test.startTest();
		LogRetentionBatch.run(new List<Log_Retention_Policy__mdt>{ policy('Bolt_Error_Log__c', 30, true) });
		Test.stopTest();

		Assert.areEqual(
			0,
			[SELECT COUNT() FROM Bolt_Error_Log__c WHERE Id = :errorLog.Id],
			'An aged Bolt error log should be purged by the same batch'
		);
	}
}
