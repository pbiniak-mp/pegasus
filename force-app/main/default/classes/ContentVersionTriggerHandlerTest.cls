@IsTest
private class ContentVersionTriggerHandlerTest {
	@IsTest
	static void insert_intakeUploadIsRecorded() {
		String token = ProjectIntakeFileService.createUploadToken();

		ContentVersion layout = ProjectIntakeTestData.createLayout(token);

		Assert.areEqual(
			1,
			[
				SELECT COUNT()
				FROM Project_Intake_Upload__c
				WHERE Content_Version_Id__c = :String.valueOf(layout.Id)
				WITH SYSTEM_MODE
			]
		);
	}

	@IsTest
	static void insert_otherFilesAreNotTouched() {
		List<ContentVersion> versions = new List<ContentVersion>();
		for (Integer i = 0; i < 200; i++) {
			versions.add(
				new ContentVersion(
					Title = 'doc' + i,
					PathOnClient = 'doc' + i + '.exe',
					VersionData = Blob.valueOf('x')
				)
			);
		}

		insert versions;

		Assert.areEqual(200, [SELECT COUNT() FROM ContentVersion WHERE Title LIKE 'doc%']);
		Assert.areEqual(0, [SELECT COUNT() FROM Project_Intake_Upload__c WITH SYSTEM_MODE]);
	}

	@IsTest
	static void insert_bypassedHandlerSkipsIntakeProcessing() {
		String token = ProjectIntakeFileService.createUploadToken();
		TriggerHandler.bypass('ContentVersionTriggerHandler');

		ContentVersion layout = ProjectIntakeTestData.createFile(token + '|LAYOUT', 'plan.exe', 10);

		TriggerHandler.clearBypass('ContentVersionTriggerHandler');
		Assert.areEqual('plan', layout.Title);
		Assert.areEqual(0, [SELECT COUNT() FROM Project_Intake_Upload__c WITH SYSTEM_MODE]);
	}
}
