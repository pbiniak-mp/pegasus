@IsTest
private class ProjectIntakeControllerTest {
	@IsTest
	static void getFormOptions_returnsOptions() {
		ProjectIntakeOptions options = ProjectIntakeController.getFormOptions();

		Assert.areEqual(3, options.countries.size());
		Assert.isFalse(options.statesByCountry.get('US').isEmpty());
	}

	@IsTest
	static void createUploadToken_returnsHexToken() {
		Assert.areEqual(32, ProjectIntakeController.createUploadToken().length());
	}

	@IsTest
	static void getUploadedFiles_andRemove_roundTrip() {
		String token = ProjectIntakeController.createUploadToken();
		ContentVersion layout = ProjectIntakeTestData.createLayout(token);

		List<ProjectIntakeFileInfo> files = ProjectIntakeController.getUploadedFiles(
			token,
			new List<Id>{ layout.Id }
		);
		Assert.isTrue(files[0].isValid);

		ProjectIntakeController.removeUploadedFile(token, layout.Id);
		Assert.areEqual(
			0,
			[SELECT COUNT() FROM ContentDocument WHERE Id = :layout.ContentDocumentId]
		);
	}

	@IsTest
	static void getUploadedFiles_invalidTokenShowsValidationMessage() {
		try {
			ProjectIntakeController.getUploadedFiles('bad', new List<Id>());
			Assert.fail('Expected AuraHandledException');
		} catch (AuraHandledException e) {
			Assert.areEqual(Constants.INTAKE_ERR_SESSION, e.getMessage());
		}
	}

	@IsTest
	static void removeUploadedFile_invalidTokenShowsValidationMessage() {
		try {
			ProjectIntakeController.removeUploadedFile('bad', null);
			Assert.fail('Expected AuraHandledException');
		} catch (AuraHandledException e) {
			Assert.areEqual(Constants.INTAKE_ERR_SESSION, e.getMessage());
		}
	}

	@IsTest
	static void submitIntake_createsLead() {
		String token = ProjectIntakeController.createUploadToken();
		ContentVersion layout = ProjectIntakeTestData.createLayout(token);
		ContentVersion spec = ProjectIntakeTestData.createSpec(token);

		ProjectIntakeController.submitIntake(
			JSON.serialize(ProjectIntakeTestData.validRequest(token, layout, spec))
		);

		Assert.areEqual(1, [SELECT COUNT() FROM Lead WHERE Company = 'Intake Test Co']);
	}

	@IsTest
	static void submitIntake_validationErrorKeepsItsMessage() {
		try {
			ProjectIntakeController.submitIntake('{}');
			Assert.fail('Expected AuraHandledException');
		} catch (AuraHandledException e) {
			Assert.isTrue(e.getMessage().contains('Project Name is required.'), e.getMessage());
		}
	}

	@IsTest
	static void submitIntake_unexpectedErrorReturnsGenericMessage() {
		Profile platformProfile = [
			SELECT Id
			FROM Profile
			WHERE Name = 'Minimum Access - Salesforce'
			LIMIT 1
		];
		String uniqueName = 'intake' + String.valueOf(Crypto.getRandomInteger()).replace('-', 'x');
		User noLeadAccess = new User(
			Alias = 'nolead',
			Email = uniqueName + '@example.com',
			EmailEncodingKey = 'UTF-8',
			LastName = 'NoLead',
			LanguageLocaleKey = 'en_US',
			LocaleSidKey = 'en_US',
			ProfileId = platformProfile.Id,
			TimeZoneSidKey = 'America/Phoenix',
			Username = uniqueName + '@example.com.intake'
		);
		insert noLeadAccess;

		System.runAs(noLeadAccess) {
			// Files are created by the running user so the file checks pass and the Lead insert fails.
			String token = ProjectIntakeController.createUploadToken();
			ContentVersion layout = ProjectIntakeTestData.createLayout(token);
			ContentVersion spec = ProjectIntakeTestData.createSpec(token);
			String requestJson = JSON.serialize(ProjectIntakeTestData.validRequest(token, layout, spec));
			try {
				ProjectIntakeController.submitIntake(requestJson);
				Assert.fail('Expected AuraHandledException');
			} catch (AuraHandledException e) {
				Assert.areEqual(Constants.INTAKE_ERR_GENERIC, e.getMessage());
			}
		}
	}
}
