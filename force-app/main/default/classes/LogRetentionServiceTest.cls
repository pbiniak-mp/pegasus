@IsTest
private class LogRetentionServiceTest {

	private static Log_Retention_Policy__mdt policy(String objectName, Decimal days) {
		return new Log_Retention_Policy__mdt(
			DeveloperName = 'Test_Policy',
			Object_API_Name__c = objectName,
			Retention_Days__c = days,
			Active__c = true,
			Hard_Delete__c = true
		);
	}

	private static List<Integration_Log__c> insertLogs(Integer count) {
		List<Integration_Log__c> logs = new List<Integration_Log__c>();
		for (Integer i = 0; i < count; i++) {
			logs.add(new Integration_Log__c(Integration_Name__c = 'Retention Test ' + i));
		}
		insert logs;
		return logs;
	}

	@IsTest
	static void validateAcceptsAWellFormedPolicy() {
		Assert.isNull(
			LogRetentionService.validate(policy('Integration_Log__c', 30)),
			'A deletable object with a positive retention window should validate'
		);
	}

	@IsTest
	static void validateRejectsMissingPolicy() {
		Assert.isNotNull(LogRetentionService.validate(null), 'A null policy must be rejected');
	}

	@IsTest
	static void validateRejectsBlankObjectName() {
		Assert.isNotNull(
			LogRetentionService.validate(policy('', 30)),
			'A blank object name must be rejected'
		);
	}

	@IsTest
	static void validateRejectsUnknownObject() {
		String problem = LogRetentionService.validate(policy('Not_A_Real_Object__c', 30));

		Assert.isNotNull(problem, 'An object that does not exist must be rejected');
		Assert.isTrue(
			problem.contains('Not_A_Real_Object__c'),
			'The message should name the offending object, was: ' + problem
		);
	}

	@IsTest
	static void validateRejectsNonDeletableObject() {
		// AsyncApexJob is queryable but the platform never allows deleting it.
		Assert.isNotNull(
			LogRetentionService.validate(policy('AsyncApexJob', 30)),
			'An object the platform refuses to delete must be rejected'
		);
	}

	@IsTest
	static void validateRejectsNonPositiveRetentionWindow() {
		Assert.isNotNull(
			LogRetentionService.validate(policy('Integration_Log__c', null)),
			'A null retention window must be rejected'
		);
		Assert.isNotNull(
			LogRetentionService.validate(policy('Integration_Log__c', 0)),
			'Zero days would delete records the moment they are written'
		);
		Assert.isNotNull(
			LogRetentionService.validate(policy('Integration_Log__c', -5)),
			'A negative retention window must be rejected'
		);
	}

	@IsTest
	static void cutoffSitsTheConfiguredNumberOfDaysInThePast() {
		Datetime before = Datetime.now().addDays(-30);
		Datetime cutoff = LogRetentionService.cutoffFor(policy('Integration_Log__c', 30));
		Datetime after = Datetime.now().addDays(-30);

		Assert.isTrue(
			cutoff >= before && cutoff <= after,
			'Cutoff should be roughly 30 days ago, was: ' + cutoff
		);
	}

	@IsTest
	static void purgeWithHardDeleteEmptiesTheRecycleBin() {
		List<Integration_Log__c> logs = insertLogs(3);
		Set<Id> ids = new Map<Id, Integration_Log__c>(logs).keySet();

		Test.startTest();
		LogRetentionService.PurgeResult result = LogRetentionService.purge(logs, true);
		Test.stopTest();

		Assert.areEqual(3, result.deleted, 'All three records should be reported deleted');
		Assert.areEqual(0, result.failed, 'No record should have failed');
		Assert.isTrue(result.errors.isEmpty(), 'A clean purge should report no errors');
		// The recycle bin cannot be observed from Apex — an ALL ROWS query returns the
		// deleted rows whether or not the bin was emptied — so the flag set alongside the
		// successful emptyRecycleBin call is what proves the storage was reclaimed.
		Assert.isTrue(result.recycleBinEmptied, 'Hard delete should have emptied the recycle bin');
		Assert.areEqual(
			0,
			[SELECT COUNT() FROM Integration_Log__c WHERE Id IN :ids],
			'The records should no longer be live'
		);
	}

	@IsTest
	static void purgeWithoutHardDeleteLeavesRecordsInTheRecycleBin() {
		List<Integration_Log__c> logs = insertLogs(2);
		Set<Id> ids = new Map<Id, Integration_Log__c>(logs).keySet();

		Test.startTest();
		LogRetentionService.PurgeResult result = LogRetentionService.purge(logs, false);
		Test.stopTest();

		Assert.areEqual(2, result.deleted, 'Both records should be reported deleted');
		Assert.isFalse(
			result.recycleBinEmptied,
			'Soft delete must leave the recycle bin alone so the records stay recoverable'
		);
		Assert.areEqual(
			0,
			[SELECT COUNT() FROM Integration_Log__c WHERE Id IN :ids],
			'The records should no longer be live'
		);
		Assert.areEqual(
			2,
			[SELECT COUNT() FROM Integration_Log__c WHERE Id IN :ids ALL ROWS],
			'Without hard delete the records should still sit in the recycle bin'
		);
	}

	@IsTest
	static void purgeHandlesAnEmptyScope() {
		LogRetentionService.PurgeResult fromEmpty = LogRetentionService.purge(new List<SObject>(), true);
		LogRetentionService.PurgeResult fromNull = LogRetentionService.purge(null, true);

		Assert.areEqual(0, fromEmpty.deleted, 'An empty scope deletes nothing');
		Assert.areEqual(0, fromNull.deleted, 'A null scope deletes nothing');
		Assert.isTrue(fromNull.errors.isEmpty(), 'A null scope is not an error condition');
	}

	@IsTest
	static void purgeHandlesABulkScope() {
		List<Integration_Log__c> logs = insertLogs(200);

		Test.startTest();
		LogRetentionService.PurgeResult result = LogRetentionService.purge(logs, true);
		Test.stopTest();

		Assert.areEqual(200, result.deleted, 'A full batch scope should be deleted in one pass');
		Assert.areEqual(0, result.failed, 'No record should have failed');
	}

	@IsTest
	static void expiredRecordsLocatorSelectsOnlyRecordsPastTheCutoff() {
		List<Integration_Log__c> logs = insertLogs(4);
		// Age the first two well past a 30-day window; leave the others current.
		Test.setCreatedDate(logs[0].Id, Datetime.now().addDays(-45));
		Test.setCreatedDate(logs[1].Id, Datetime.now().addDays(-31));

		Test.startTest();
		Database.QueryLocator locator = LogRetentionService.expiredRecordsLocator(
			policy('Integration_Log__c', 30)
		);
		Database.QueryLocatorIterator iterator = locator.iterator();
		Set<Id> selected = new Set<Id>();
		while (iterator.hasNext()) {
			selected.add(iterator.next().Id);
		}
		Test.stopTest();

		Assert.areEqual(2, selected.size(), 'Only the two aged records should be selected');
		Assert.isTrue(selected.contains(logs[0].Id), 'The 45-day-old record should be selected');
		Assert.isTrue(selected.contains(logs[1].Id), 'The 31-day-old record should be selected');
		Assert.isFalse(selected.contains(logs[2].Id), 'A record created today must be kept');
	}
}
