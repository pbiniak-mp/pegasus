@IsTest
private class ProjectIntakeFileServiceTest {
	private static Integer documentCount(Id documentId) {
		return [SELECT COUNT() FROM ContentDocument WHERE Id = :documentId];
	}

	private static String expectError(String token, List<ProjectIntakeRequest.FileRef> refs) {
		try {
			ProjectIntakeFileService.validateFileRefs(token, refs);
		} catch (ProjectIntakeService.IntakeValidationException e) {
			return e.getMessage();
		}
		Assert.fail('Expected IntakeValidationException');
		return null;
	}

	private static ProjectIntakeRequest.FileRef ref(Id versionId, String category) {
		ProjectIntakeRequest.FileRef fileRef = new ProjectIntakeRequest.FileRef();
		fileRef.contentVersionId = versionId;
		fileRef.category = category;
		return fileRef;
	}

	private static Lead insertLead() {
		Lead lead = new Lead(LastName = 'Attach', Company = 'Attach Co');
		insert lead;
		return lead;
	}

	@IsTest
	static void createUploadToken_returns32HexCharacters() {
		String token = ProjectIntakeFileService.createUploadToken();

		Assert.areEqual(32, token.length());
		Assert.isTrue(Pattern.matches(Constants.INTAKE_TOKEN_PATTERN, token));
		Assert.areNotEqual(token, ProjectIntakeFileService.createUploadToken());
	}

	@IsTest
	static void describeUploadedFiles_validFilesAreReturnedAsValid() {
		String token = ProjectIntakeFileService.createUploadToken();
		ContentVersion layout = ProjectIntakeTestData.createLayout(token);
		ContentVersion spec = ProjectIntakeTestData.createSpec(token);

		List<ProjectIntakeFileInfo> result = ProjectIntakeFileService.describeUploadedFiles(
			token,
			new List<Id>{ layout.Id, spec.Id }
		);

		Assert.areEqual(2, result.size());
		Assert.isTrue(result[0].isValid);
		Assert.isNull(result[0].errorMessage);
		Assert.areEqual('LAYOUT', result[0].category);
		Assert.areEqual('pdf', result[0].extension);
		Assert.areEqual('layout', result[0].title);
		Assert.areEqual(layout.ContentSize, result[0].sizeBytes);
		Assert.areEqual('SPEC', result[1].category);
		Assert.areEqual(1, documentCount(layout.ContentDocumentId));
	}

	@IsTest
	static void describeUploadedFiles_emptyInputReturnsEmptyList() {
		String token = ProjectIntakeFileService.createUploadToken();

		Assert.isTrue(ProjectIntakeFileService.describeUploadedFiles(token, null).isEmpty());
		Assert.isTrue(
			ProjectIntakeFileService.describeUploadedFiles(token, new List<Id>()).isEmpty()
		);
	}

	@IsTest
	static void describeUploadedFiles_invalidTokenThrows() {
		try {
			ProjectIntakeFileService.describeUploadedFiles('not-a-token', new List<Id>());
			Assert.fail('Expected IntakeValidationException');
		} catch (ProjectIntakeService.IntakeValidationException e) {
			Assert.areEqual(Constants.INTAKE_ERR_SESSION, e.getMessage());
		}
	}

	@IsTest
	static void describeUploadedFiles_wrongExtensionIsInvalidAndDeleted() {
		String token = ProjectIntakeFileService.createUploadToken();
		ContentVersion exe = ProjectIntakeTestData.createFile(token + '|SPEC', 'malware.exe', 10);
		// dwg is fine for a layout but not for a spec sheet
		ContentVersion dwgSpec = ProjectIntakeTestData.createFile(token + '|SPEC', 'plan.dwg', 10);

		List<ProjectIntakeFileInfo> result = ProjectIntakeFileService.describeUploadedFiles(
			token,
			new List<Id>{ exe.Id, dwgSpec.Id }
		);

		Assert.isFalse(result[0].isValid);
		Assert.areEqual('File type .exe is not allowed.', result[0].errorMessage);
		Assert.isFalse(result[1].isValid);
		Assert.areEqual(0, documentCount(exe.ContentDocumentId), 'Invalid file must be deleted');
		Assert.areEqual(0, documentCount(dwgSpec.ContentDocumentId));
	}

	@IsTest
	static void describeUploadedFiles_dwgAllowedForLayout() {
		String token = ProjectIntakeFileService.createUploadToken();
		ContentVersion dwg = ProjectIntakeTestData.createFile(token + '|LAYOUT', 'plan.DWG', 10);

		List<ProjectIntakeFileInfo> result = ProjectIntakeFileService.describeUploadedFiles(
			token,
			new List<Id>{ dwg.Id }
		);

		Assert.isTrue(result[0].isValid, 'Extension check must be case insensitive');
	}

	@IsTest
	static void describeUploadedFiles_oversizeFileIsInvalid() {
		String token = ProjectIntakeFileService.createUploadToken();
		ContentVersion spec = ProjectIntakeTestData.createFile(token + '|SPEC', 'big.pdf', 50);
		ProjectIntakeFileService.maxBytesOverride.put('SPEC', 10);

		List<ProjectIntakeFileInfo> result = ProjectIntakeFileService.describeUploadedFiles(
			token,
			new List<Id>{ spec.Id }
		);

		Assert.isFalse(result[0].isValid);
		Assert.areEqual('File is larger than 10 bytes.', result[0].errorMessage);
		Assert.areEqual(0, documentCount(spec.ContentDocumentId));
	}

	@IsTest
	static void describeUploadedFiles_sizeLimitMessageUsesReadableUnits() {
		String token = ProjectIntakeFileService.createUploadToken();
		ContentVersion bigSpec = ProjectIntakeTestData.createFile(token + '|SPEC', 'big.pdf', 2200000);
		ContentVersion midLayout = ProjectIntakeTestData.createFile(token + '|LAYOUT', 'mid.pdf', 5000);

		ProjectIntakeFileService.maxBytesOverride.put('SPEC', 2097152);
		ProjectIntakeFileService.maxBytesOverride.put('LAYOUT', 2048);
		List<ProjectIntakeFileInfo> result = ProjectIntakeFileService.describeUploadedFiles(
			token,
			new List<Id>{ bigSpec.Id, midLayout.Id }
		);

		Assert.areEqual('File is larger than 2 MB.', result[0].errorMessage);
		Assert.areEqual('File is larger than 2 KB.', result[1].errorMessage);
	}

	@IsTest
	static void describeUploadedFiles_tooManyFilesRejectsTheExcess() {
		String token = ProjectIntakeFileService.createUploadToken();
		ContentVersion first = ProjectIntakeTestData.createLayout(token);
		ContentVersion second = ProjectIntakeTestData.createFile(token + '|LAYOUT', 'second.pdf', 10);

		List<ProjectIntakeFileInfo> result = ProjectIntakeFileService.describeUploadedFiles(
			token,
			new List<Id>{ second.Id }
		);

		Assert.isFalse(result[0].isValid);
		Assert.areEqual('Only 1 file allowed.', result[0].errorMessage);
		Assert.areEqual(0, documentCount(second.ContentDocumentId));
		Assert.areEqual(1, documentCount(first.ContentDocumentId), 'Earlier upload is kept');
	}

	@IsTest
	static void describeUploadedFiles_specAllowsTwoFilesButNotThree() {
		String token = ProjectIntakeFileService.createUploadToken();
		List<Id> ids = new List<Id>();
		for (Integer i = 0; i < 3; i++) {
			ids.add(ProjectIntakeTestData.createFile(token + '|SPEC', 'spec' + i + '.pdf', 10).Id);
		}

		List<ProjectIntakeFileInfo> result = ProjectIntakeFileService.describeUploadedFiles(token, ids);

		Assert.isTrue(result[0].isValid);
		Assert.isTrue(result[1].isValid);
		Assert.isFalse(result[2].isValid);
		Assert.areEqual('Only 2 files allowed.', result[2].errorMessage);
	}

	@IsTest
	static void describeUploadedFiles_foreignTokenIsNotFoundAndKept() {
		String token = ProjectIntakeFileService.createUploadToken();
		String otherToken = ProjectIntakeFileService.createUploadToken();
		ContentVersion foreign = ProjectIntakeTestData.createLayout(otherToken);

		List<ProjectIntakeFileInfo> result = ProjectIntakeFileService.describeUploadedFiles(
			token,
			new List<Id>{ foreign.Id }
		);

		Assert.isFalse(result[0].isValid);
		Assert.areEqual(Constants.INTAKE_ERR_FILE_NOT_FOUND, result[0].errorMessage);
		Assert.areEqual(1, documentCount(foreign.ContentDocumentId), 'Foreign file must not be deleted');
	}

	@IsTest
	static void describeUploadedFiles_expiredFileIsInvalid() {
		String token = ProjectIntakeFileService.createUploadToken();
		ContentVersion layout = ProjectIntakeTestData.createLayout(token);
		ProjectIntakeFileService.maxAgeHours = -1;

		List<ProjectIntakeFileInfo> result = ProjectIntakeFileService.describeUploadedFiles(
			token,
			new List<Id>{ layout.Id }
		);

		Assert.isFalse(result[0].isValid);
		Assert.areEqual(Constants.INTAKE_ERR_FILE_EXPIRED, result[0].errorMessage);
	}

	@IsTest
	static void describeUploadedFiles_fileLinkedToARecordIsInUseAndKept() {
		String token = ProjectIntakeFileService.createUploadToken();
		ContentVersion layout = ProjectIntakeTestData.createLayout(token);
		insert new ContentDocumentLink(
			ContentDocumentId = layout.ContentDocumentId,
			LinkedEntityId = insertLead().Id,
			ShareType = 'V'
		);

		List<ProjectIntakeFileInfo> result = ProjectIntakeFileService.describeUploadedFiles(
			token,
			new List<Id>{ layout.Id }
		);

		Assert.isFalse(result[0].isValid);
		Assert.areEqual(Constants.INTAKE_ERR_FILE_IN_USE, result[0].errorMessage);
		Assert.areEqual(1, documentCount(layout.ContentDocumentId), 'File in use must not be deleted');
	}

	@IsTest
	static void removeUploadedFile_deletesOwnUnlinkedFile() {
		String token = ProjectIntakeFileService.createUploadToken();
		ContentVersion layout = ProjectIntakeTestData.createLayout(token);

		ProjectIntakeFileService.removeUploadedFile(token, layout.Id);

		Assert.areEqual(0, documentCount(layout.ContentDocumentId));
	}

	@IsTest
	static void removeUploadedFile_missingFileOrIdIsIgnored() {
		String token = ProjectIntakeFileService.createUploadToken();
		ContentVersion layout = ProjectIntakeTestData.createLayout(token);
		delete new ContentDocument(Id = layout.ContentDocumentId);

		ProjectIntakeFileService.removeUploadedFile(token, layout.Id);
		ProjectIntakeFileService.removeUploadedFile(token, null);

		Assert.areEqual(0, documentCount(layout.ContentDocumentId));
	}

	@IsTest
	static void removeUploadedFile_foreignTokenThrowsAndKeepsFile() {
		String token = ProjectIntakeFileService.createUploadToken();
		ContentVersion foreign = ProjectIntakeTestData.createLayout(
			ProjectIntakeFileService.createUploadToken()
		);

		try {
			ProjectIntakeFileService.removeUploadedFile(token, foreign.Id);
			Assert.fail('Expected IntakeValidationException');
		} catch (ProjectIntakeService.IntakeValidationException e) {
			Assert.areEqual(Constants.INTAKE_ERR_FILE_REMOVE, e.getMessage());
		}
		Assert.areEqual(1, documentCount(foreign.ContentDocumentId));
	}

	@IsTest
	static void removeUploadedFile_linkedFileThrowsAndKeepsFile() {
		String token = ProjectIntakeFileService.createUploadToken();
		ContentVersion layout = ProjectIntakeTestData.createLayout(token);
		insert new ContentDocumentLink(
			ContentDocumentId = layout.ContentDocumentId,
			LinkedEntityId = insertLead().Id,
			ShareType = 'V'
		);

		try {
			ProjectIntakeFileService.removeUploadedFile(token, layout.Id);
			Assert.fail('Expected IntakeValidationException');
		} catch (ProjectIntakeService.IntakeValidationException e) {
			Assert.areEqual(Constants.INTAKE_ERR_FILE_REMOVE, e.getMessage());
		}
		Assert.areEqual(1, documentCount(layout.ContentDocumentId));
	}

	@IsTest
	static void validateFileRefs_enforcesCountsAndStructure() {
		String token = ProjectIntakeFileService.createUploadToken();
		ContentVersion layout = ProjectIntakeTestData.createLayout(token);
		ContentVersion spec = ProjectIntakeTestData.createSpec(token);
		ContentVersion spec2 = ProjectIntakeTestData.createFile(token + '|SPEC', 's2.pdf', 10);
		ContentVersion spec3 = ProjectIntakeTestData.createFile(token + '|SPEC', 's3.pdf', 10);
		ContentVersion layout2 = ProjectIntakeTestData.createFile(token + '|LAYOUT', 'l2.pdf', 10);

		Assert.isTrue(expectError(token, null).startsWith('Please upload'), 'null files');
		Assert.isTrue(
			expectError(token, new List<ProjectIntakeRequest.FileRef>{ ref(layout.Id, 'LAYOUT') })
				.contains('Module Spec Sheet'),
			'missing spec'
		);
		Assert.areEqual(
			Constants.INTAKE_ERR_INVALID_SUBMISSION,
			expectError(
				token,
				new List<ProjectIntakeRequest.FileRef>{ ref(layout.Id, 'OTHER'), ref(spec.Id, 'SPEC') }
			)
		);
		Assert.areEqual(
			Constants.INTAKE_ERR_INVALID_SUBMISSION,
			expectError(token, new List<ProjectIntakeRequest.FileRef>{ null })
		);
		Assert.areEqual(
			Constants.INTAKE_ERR_FILE_DUPLICATE,
			expectError(
				token,
				new List<ProjectIntakeRequest.FileRef>{
					ref(layout.Id, 'LAYOUT'),
					ref(layout.Id, 'LAYOUT'),
					ref(spec.Id, 'SPEC')
				}
			)
		);
		Assert.isTrue(
			expectError(
				token,
				new List<ProjectIntakeRequest.FileRef>{
					ref(layout.Id, 'LAYOUT'),
					ref(layout2.Id, 'LAYOUT'),
					ref(spec.Id, 'SPEC')
				}
			)
				.contains('Only 1 file allowed'),
			'two layouts'
		);
		Assert.isTrue(
			expectError(
				token,
				new List<ProjectIntakeRequest.FileRef>{
					ref(layout.Id, 'LAYOUT'),
					ref(spec.Id, 'SPEC'),
					ref(spec2.Id, 'SPEC'),
					ref(spec3.Id, 'SPEC')
				}
			)
				.contains('Only 2 files allowed'),
			'three specs'
		);
	}

	@IsTest
	static void attachFilesToLead_linksFilesPrefixesTitlesAndSetsOwner() {
		String token = ProjectIntakeFileService.createUploadToken();
		ContentVersion layout = ProjectIntakeTestData.createLayout(token);
		ContentVersion spec = ProjectIntakeTestData.createSpec(token);
		Lead lead = insertLead();

		ProjectIntakeFileService.attachFilesToLead(
			lead.Id,
			token,
			new List<ProjectIntakeRequest.FileRef>{ ref(layout.Id, 'LAYOUT'), ref(spec.Id, 'SPEC') }
		);

		List<ContentDocumentLink> links = [
			SELECT ContentDocumentId, ShareType, Visibility
			FROM ContentDocumentLink
			WHERE LinkedEntityId = :lead.Id
		];
		Assert.areEqual(2, links.size());
		Assert.areEqual('I', links[0].ShareType);
		Assert.areEqual('InternalUsers', links[0].Visibility);
		Map<Id, ContentVersion> versions = new Map<Id, ContentVersion>(
			[SELECT Id, Title FROM ContentVersion WHERE Id IN :new Set<Id>{ layout.Id, spec.Id }]
		);
		Assert.areEqual('Module Layout - layout', versions.get(layout.Id).Title);
		Assert.areEqual('Module Spec Sheet - spec', versions.get(spec.Id).Title);
		Assert.areEqual(
			UserInfo.getUserId(),
			[SELECT OwnerId FROM ContentDocument WHERE Id = :layout.ContentDocumentId].OwnerId
		);
	}

	@IsTest
	static void attachFilesToLead_doesNotDoublePrefixTitle() {
		String token = ProjectIntakeFileService.createUploadToken();
		ContentVersion layout = ProjectIntakeTestData.createFile(
			token + '|LAYOUT',
			'Module Layout - plan.pdf',
			10
		);
		ContentVersion spec = ProjectIntakeTestData.createSpec(token);

		ProjectIntakeFileService.attachFilesToLead(
			insertLead().Id,
			token,
			new List<ProjectIntakeRequest.FileRef>{ ref(layout.Id, 'LAYOUT'), ref(spec.Id, 'SPEC') }
		);

		Assert.areEqual(
			'Module Layout - plan',
			[SELECT Title FROM ContentVersion WHERE Id = :layout.Id].Title
		);
	}

	@IsTest
	static void attachFilesToLead_fileOfAnotherTokenIsRejected() {
		String token = ProjectIntakeFileService.createUploadToken();
		ContentVersion layout = ProjectIntakeTestData.createLayout(
			ProjectIntakeFileService.createUploadToken()
		);
		ContentVersion spec = ProjectIntakeTestData.createSpec(token);

		try {
			ProjectIntakeFileService.attachFilesToLead(
				insertLead().Id,
				token,
				new List<ProjectIntakeRequest.FileRef>{ ref(layout.Id, 'LAYOUT'), ref(spec.Id, 'SPEC') }
			);
			Assert.fail('Expected IntakeValidationException');
		} catch (ProjectIntakeService.IntakeValidationException e) {
			Assert.areEqual(Constants.INTAKE_ERR_FILE_NOT_FOUND, e.getMessage());
		}
	}

	@IsTest
	static void attachFilesToLead_categoryMustMatchTheTokenSuffix() {
		String token = ProjectIntakeFileService.createUploadToken();
		ContentVersion layout = ProjectIntakeTestData.createLayout(token);
		ContentVersion spec = ProjectIntakeTestData.createSpec(token);

		try {
			ProjectIntakeFileService.attachFilesToLead(
				insertLead().Id,
				token,
				new List<ProjectIntakeRequest.FileRef>{ ref(layout.Id, 'SPEC'), ref(spec.Id, 'LAYOUT') }
			);
			Assert.fail('Expected IntakeValidationException');
		} catch (ProjectIntakeService.IntakeValidationException e) {
			Assert.areEqual(Constants.INTAKE_ERR_FILE_NOT_FOUND, e.getMessage());
		}
	}

	@IsTest
	static void attachFilesToLead_invalidFileNamesItInTheMessage() {
		String token = ProjectIntakeFileService.createUploadToken();
		ContentVersion layout = ProjectIntakeTestData.createFile(token + '|LAYOUT', 'plan.exe', 10);
		ContentVersion spec = ProjectIntakeTestData.createSpec(token);

		try {
			ProjectIntakeFileService.attachFilesToLead(
				insertLead().Id,
				token,
				new List<ProjectIntakeRequest.FileRef>{ ref(layout.Id, 'LAYOUT'), ref(spec.Id, 'SPEC') }
			);
			Assert.fail('Expected IntakeValidationException');
		} catch (ProjectIntakeService.IntakeValidationException e) {
			Assert.isTrue(e.getMessage().contains('"plan"'), e.getMessage());
			Assert.isTrue(e.getMessage().contains('.exe'), e.getMessage());
		}
	}

	@IsTest
	static void attachFilesToLead_unknownLeadThrowsGenericMessage() {
		String token = ProjectIntakeFileService.createUploadToken();
		ContentVersion layout = ProjectIntakeTestData.createLayout(token);
		ContentVersion spec = ProjectIntakeTestData.createSpec(token);
		Lead lead = insertLead();
		Id deletedLeadId = lead.Id;
		delete lead;

		try {
			ProjectIntakeFileService.attachFilesToLead(
				deletedLeadId,
				token,
				new List<ProjectIntakeRequest.FileRef>{ ref(layout.Id, 'LAYOUT'), ref(spec.Id, 'SPEC') }
			);
			Assert.fail('Expected IntakeValidationException');
		} catch (ProjectIntakeService.IntakeValidationException e) {
			Assert.areEqual(Constants.INTAKE_ERR_GENERIC, e.getMessage());
		}
	}
}
