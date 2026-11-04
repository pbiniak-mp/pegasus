@IsTest
private class ProjectIntakeUploadSelectorTest {
	@IsTest
	static void getByContentVersionIds_returnsRequestedUploads() {
		String token = ProjectIntakeFileService.createUploadToken();
		ContentVersion layout = ProjectIntakeTestData.createLayout(token);
		ProjectIntakeTestData.createSpec(token);

		List<Project_Intake_Upload__c> result = ProjectIntakeUploadSelector.getByContentVersionIds(
			new Set<String>{ String.valueOf(layout.Id) }
		);

		Assert.areEqual(1, result.size());
		Assert.areEqual(token, result[0].Upload_Token__c);
		Assert.areEqual('LAYOUT', result[0].Category__c);
		Assert.areEqual(layout.ContentDocumentId, result[0].Content_Document_Id__c);
		Assert.areEqual(UserInfo.getUserId(), result[0].CreatedById);
	}

	@IsTest
	static void getUnattachedByTokens_skipsOtherTokensAndAttachedUploads() {
		String token = ProjectIntakeFileService.createUploadToken();
		ContentVersion layout = ProjectIntakeTestData.createLayout(token);
		ProjectIntakeTestData.createSpec(token);
		ProjectIntakeTestData.createLayout(ProjectIntakeFileService.createUploadToken());
		Lead lead = new Lead(LastName = 'Attached', Company = 'Attached Co');
		insert lead;
		Project_Intake_Upload__c attached = ProjectIntakeUploadSelector.getByContentVersionIds(
			new Set<String>{ String.valueOf(layout.Id) }
		)[0];
		attached.Lead__c = lead.Id;
		Database.update(attached, AccessLevel.SYSTEM_MODE);

		List<Project_Intake_Upload__c> result = ProjectIntakeUploadSelector.getUnattachedByTokens(
			new Set<String>{ token }
		);

		Assert.areEqual(1, result.size());
		Assert.areEqual('SPEC', result[0].Category__c);
	}
}
