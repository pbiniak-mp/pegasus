@IsTest
private class ProjectIntakeFileServiceTest {
	private static Integer documentCount(Id documentId) {
		return [SELECT COUNT() FROM ContentDocument WHERE Id = :documentId];
	}

	private static Project_Intake_Upload__c uploadOf(ContentVersion version) {
		return [
			SELECT Id, Upload_Token__c, Category__c, Content_Document_Id__c, File_Name__c,
				File_Extension__c, Size_Bytes__c, Lead__c
			FROM Project_Intake_Upload__c
			WHERE Content_Version_Id__c = :String.valueOf(version.Id)
			WITH SYSTEM_MODE
		];
	}

	/** Inserts an intake file and returns the error that rejected it. */
	private static String expectUploadError(String tokenValue, String fileName, Integer sizeChars) {
		try {
			ProjectIntakeTestData.createFile(tokenValue, fileName, sizeChars);
		} catch (DmlException e) {
			return e.getDmlMessage(0);
		}
		Assert.fail('Expected the upload to be rejected');
		return null;
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

	private static String expectAttachError(Id leadId, String token, List<ProjectIntakeRequest.FileRef> refs) {
		try {
			ProjectIntakeFileService.attachFilesToLead(leadId, token, refs);
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

	/** A syntactically valid ContentVersion Id for structural checks. */
	private static Id fakeVersionId(Integer index) {
		return Id.valueOf('068' + String.valueOf(index).leftPad(12, '0'));
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

	// ---- upload transaction (trigger) ------------------------------------------

	@IsTest
	static void upload_validFileIsRecordedAndPrefixed() {
		String token = ProjectIntakeFileService.createUploadToken();

		ContentVersion layout = ProjectIntakeTestData.createLayout(token);

		Assert.areEqual('Module Layout - layout', layout.Title);
		Project_Intake_Upload__c upload = uploadOf(layout);
		Assert.areEqual(token, upload.Upload_Token__c);
		Assert.areEqual('LAYOUT', upload.Category__c);
		Assert.areEqual(layout.ContentDocumentId, upload.Content_Document_Id__c);
		Assert.areEqual('layout', upload.File_Name__c);
		Assert.areEqual('pdf', upload.File_Extension__c);
		Assert.areEqual(layout.ContentSize, upload.Size_Bytes__c);
		Assert.isNull(upload.Lead__c);
	}

	@IsTest
	static void upload_existingPrefixIsNotDoubled() {
		String token = ProjectIntakeFileService.createUploadToken();

		ContentVersion layout = ProjectIntakeTestData.createFile(
			token + '|LAYOUT',
			'Module Layout - plan.pdf',
			10
		);

		Assert.areEqual('Module Layout - plan', layout.Title);
		Assert.areEqual('plan', uploadOf(layout).File_Name__c);
	}

	@IsTest
	static void upload_fileWithoutIntakeTokenIsIgnored() {
		ContentVersion version = new ContentVersion(
			Title = 'internal',
			PathOnClient = 'internal.exe',
			VersionData = Blob.valueOf('x')
		);

		insert version;

		Assert.areEqual(0, [SELECT COUNT() FROM Project_Intake_Upload__c WITH SYSTEM_MODE]);
		Assert.areEqual('internal', [SELECT Title FROM ContentVersion WHERE Id = :version.Id].Title);
	}

	@IsTest
	static void upload_invalidTokenOrCategoryIsRejected() {
		String token = ProjectIntakeFileService.createUploadToken();

		Assert.areEqual(Constants.INTAKE_ERR_SESSION, expectUploadError('short|LAYOUT', 'a.pdf', 10));
		Assert.areEqual(Constants.INTAKE_ERR_SESSION, expectUploadError(token + '|OTHER', 'a.pdf', 10));
		Assert.areEqual(Constants.INTAKE_ERR_SESSION, expectUploadError(token, 'a.pdf', 10));
		Assert.areEqual(0, [SELECT COUNT() FROM Project_Intake_Upload__c WITH SYSTEM_MODE]);
	}

	@IsTest
	static void upload_wrongExtensionIsRejected() {
		String token = ProjectIntakeFileService.createUploadToken();

		Assert.areEqual(
			'File type .exe is not allowed.',
			expectUploadError(token + '|SPEC', 'malware.exe', 10)
		);
		// dwg is fine for a layout but not for a spec sheet
		Assert.areEqual(
			'File type .dwg is not allowed.',
			expectUploadError(token + '|SPEC', 'plan.dwg', 10)
		);
		Assert.areEqual(0, [SELECT COUNT() FROM Project_Intake_Upload__c WITH SYSTEM_MODE]);
	}

	@IsTest
	static void upload_extensionCheckIsCaseInsensitive() {
		String token = ProjectIntakeFileService.createUploadToken();

		ContentVersion dwg = ProjectIntakeTestData.createFile(token + '|LAYOUT', 'plan.DWG', 10);

		Assert.areEqual('dwg', uploadOf(dwg).File_Extension__c);
	}

	@IsTest
	static void upload_oversizeFileIsRejectedWithReadableLimit() {
		String token = ProjectIntakeFileService.createUploadToken();
		ProjectIntakeFileService.maxBytesOverride.put('SPEC', 10);
		ProjectIntakeFileService.maxBytesOverride.put('LAYOUT', 2048);

		Assert.areEqual(
			'File is larger than 10 bytes.',
			expectUploadError(token + '|SPEC', 'big.pdf', 50)
		);
		Assert.areEqual(
			'File is larger than 2 KB.',
			expectUploadError(token + '|LAYOUT', 'mid.pdf', 5000)
		);
		ProjectIntakeFileService.maxBytesOverride.put('SPEC', 2097152);
		Assert.areEqual(
			'File is larger than 2 MB.',
			expectUploadError(token + '|SPEC', 'huge.pdf', 2200000)
		);
	}

	@IsTest
	static void upload_tooManyFilesOfACategoryAreRejected() {
		String token = ProjectIntakeFileService.createUploadToken();
		ProjectIntakeTestData.createLayout(token);
		ProjectIntakeTestData.createSpec(token);
		ProjectIntakeTestData.createFile(token + '|SPEC', 'spec2.pdf', 10);

		Assert.areEqual('Only 1 file allowed.', expectUploadError(token + '|LAYOUT', 'l2.pdf', 10));
		Assert.areEqual('Only 2 files allowed.', expectUploadError(token + '|SPEC', 's3.pdf', 10));
		Assert.areEqual(3, [SELECT COUNT() FROM Project_Intake_Upload__c WITH SYSTEM_MODE]);
	}

	@IsTest
	static void upload_limitCountsOnlyTheSameTokenAndUnattachedFiles() {
		String token = ProjectIntakeFileService.createUploadToken();
		ContentVersion first = ProjectIntakeTestData.createLayout(token);
		Project_Intake_Upload__c upload = uploadOf(first);
		upload.Lead__c = insertLead().Id;
		Database.update(upload, AccessLevel.SYSTEM_MODE);

		ProjectIntakeTestData.createLayout(token);
		ProjectIntakeTestData.createLayout(ProjectIntakeFileService.createUploadToken());

		Assert.areEqual(3, [SELECT COUNT() FROM Project_Intake_Upload__c WITH SYSTEM_MODE]);
	}

	// ---- form ------------------------------------------------------------------

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
		Assert.areEqual(layout.Id, result[0].contentVersionId);
		Assert.areEqual('LAYOUT', result[0].category);
		Assert.areEqual('pdf', result[0].extension);
		Assert.areEqual('layout', result[0].title);
		Assert.areEqual(layout.ContentSize, result[0].sizeBytes);
		Assert.areEqual('SPEC', result[1].category);
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
	static void describeUploadedFiles_unknownOrForeignFileIsNotFound() {
		String token = ProjectIntakeFileService.createUploadToken();
		ContentVersion foreign = ProjectIntakeTestData.createLayout(
			ProjectIntakeFileService.createUploadToken()
		);

		List<ProjectIntakeFileInfo> result = ProjectIntakeFileService.describeUploadedFiles(
			token,
			new List<Id>{ foreign.Id, fakeVersionId(1) }
		);

		Assert.isFalse(result[0].isValid);
		Assert.areEqual(Constants.INTAKE_ERR_FILE_NOT_FOUND, result[0].errorMessage);
		Assert.isFalse(result[1].isValid);
		Assert.areEqual(Constants.INTAKE_ERR_FILE_NOT_FOUND, result[1].errorMessage);
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
	static void describeUploadedFiles_attachedFileIsInUse() {
		String token = ProjectIntakeFileService.createUploadToken();
		ContentVersion layout = ProjectIntakeTestData.createLayout(token);
		Project_Intake_Upload__c upload = uploadOf(layout);
		upload.Lead__c = insertLead().Id;
		Database.update(upload, AccessLevel.SYSTEM_MODE);

		List<ProjectIntakeFileInfo> result = ProjectIntakeFileService.describeUploadedFiles(
			token,
			new List<Id>{ layout.Id }
		);

		Assert.isFalse(result[0].isValid);
		Assert.areEqual(Constants.INTAKE_ERR_FILE_IN_USE, result[0].errorMessage);
	}

	@IsTest
	static void removeUploadedFile_removesOwnUpload() {
		String token = ProjectIntakeFileService.createUploadToken();
		ContentVersion layout = ProjectIntakeTestData.createLayout(token);

		ProjectIntakeFileService.removeUploadedFile(token, layout.Id);

		Assert.areEqual(0, [SELECT COUNT() FROM Project_Intake_Upload__c WITH SYSTEM_MODE]);
		Assert.areEqual(0, documentCount(layout.ContentDocumentId));
		// The slot is free again.
		ProjectIntakeTestData.createLayout(token);
	}

	@IsTest
	static void removeUploadedFile_missingFileOrIdIsIgnored() {
		String token = ProjectIntakeFileService.createUploadToken();

		ProjectIntakeFileService.removeUploadedFile(token, fakeVersionId(1));
		ProjectIntakeFileService.removeUploadedFile(token, null);

		Assert.areEqual(0, [SELECT COUNT() FROM Project_Intake_Upload__c WITH SYSTEM_MODE]);
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
		Assert.areEqual(1, [SELECT COUNT() FROM Project_Intake_Upload__c WITH SYSTEM_MODE]);
	}

	@IsTest
	static void removeUploadedFile_attachedFileThrowsAndKeepsFile() {
		String token = ProjectIntakeFileService.createUploadToken();
		ContentVersion layout = ProjectIntakeTestData.createLayout(token);
		Project_Intake_Upload__c upload = uploadOf(layout);
		upload.Lead__c = insertLead().Id;
		Database.update(upload, AccessLevel.SYSTEM_MODE);

		try {
			ProjectIntakeFileService.removeUploadedFile(token, layout.Id);
			Assert.fail('Expected IntakeValidationException');
		} catch (ProjectIntakeService.IntakeValidationException e) {
			Assert.areEqual(Constants.INTAKE_ERR_FILE_REMOVE, e.getMessage());
		}
		Assert.areEqual(1, documentCount(layout.ContentDocumentId));
	}

	// ---- submit ----------------------------------------------------------------

	@IsTest
	static void validateFileRefs_enforcesCountsAndStructure() {
		String token = ProjectIntakeFileService.createUploadToken();
		Id layout = fakeVersionId(1);
		Id layout2 = fakeVersionId(2);
		Id spec = fakeVersionId(3);
		Id spec2 = fakeVersionId(4);
		Id spec3 = fakeVersionId(5);

		Assert.isTrue(expectError(token, null).startsWith('Please upload'), 'null files');
		Assert.isTrue(
			expectError(token, new List<ProjectIntakeRequest.FileRef>{ ref(layout, 'LAYOUT') })
				.contains('Module Spec Sheet'),
			'missing spec'
		);
		Assert.areEqual(
			Constants.INTAKE_ERR_INVALID_SUBMISSION,
			expectError(
				token,
				new List<ProjectIntakeRequest.FileRef>{ ref(layout, 'OTHER'), ref(spec, 'SPEC') }
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
					ref(layout, 'LAYOUT'),
					ref(layout, 'LAYOUT'),
					ref(spec, 'SPEC')
				}
			)
		);
		Assert.isTrue(
			expectError(
				token,
				new List<ProjectIntakeRequest.FileRef>{
					ref(layout, 'LAYOUT'),
					ref(layout2, 'LAYOUT'),
					ref(spec, 'SPEC')
				}
			)
				.contains('Only 1 file allowed'),
			'two layouts'
		);
		Assert.isTrue(
			expectError(
				token,
				new List<ProjectIntakeRequest.FileRef>{
					ref(layout, 'LAYOUT'),
					ref(spec, 'SPEC'),
					ref(spec2, 'SPEC'),
					ref(spec3, 'SPEC')
				}
			)
				.contains('Only 2 files allowed'),
			'three specs'
		);
		Assert.areEqual(
			Constants.INTAKE_ERR_SESSION,
			expectError('short', new List<ProjectIntakeRequest.FileRef>())
		);
	}

	@IsTest
	static void attachFilesToLead_linksFilesAndMarksUploadsAttached() {
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
		Assert.areEqual('AllUsers', links[0].Visibility);
		Assert.areEqual(lead.Id, uploadOf(layout).Lead__c);
		Assert.areEqual(lead.Id, uploadOf(spec).Lead__c);
	}

	@IsTest
	static void attachFilesToLead_fileOfAnotherTokenIsRejected() {
		String token = ProjectIntakeFileService.createUploadToken();
		ContentVersion layout = ProjectIntakeTestData.createLayout(
			ProjectIntakeFileService.createUploadToken()
		);
		ContentVersion spec = ProjectIntakeTestData.createSpec(token);

		String message = expectAttachError(
			insertLead().Id,
			token,
			new List<ProjectIntakeRequest.FileRef>{ ref(layout.Id, 'LAYOUT'), ref(spec.Id, 'SPEC') }
		);

		Assert.areEqual(Constants.INTAKE_ERR_FILE_NOT_FOUND, message);
	}

	@IsTest
	static void attachFilesToLead_unknownFileIsRejected() {
		String token = ProjectIntakeFileService.createUploadToken();
		ContentVersion spec = ProjectIntakeTestData.createSpec(token);

		String message = expectAttachError(
			insertLead().Id,
			token,
			new List<ProjectIntakeRequest.FileRef>{ ref(fakeVersionId(1), 'LAYOUT'), ref(spec.Id, 'SPEC') }
		);

		Assert.areEqual(Constants.INTAKE_ERR_FILE_NOT_FOUND, message);
	}

	@IsTest
	static void attachFilesToLead_categoryMustMatchTheUpload() {
		String token = ProjectIntakeFileService.createUploadToken();
		ContentVersion layout = ProjectIntakeTestData.createLayout(token);
		ContentVersion spec = ProjectIntakeTestData.createSpec(token);

		String message = expectAttachError(
			insertLead().Id,
			token,
			new List<ProjectIntakeRequest.FileRef>{ ref(layout.Id, 'SPEC'), ref(spec.Id, 'LAYOUT') }
		);

		Assert.areEqual(Constants.INTAKE_ERR_FILE_NOT_FOUND, message);
	}

	@IsTest
	static void attachFilesToLead_alreadyAttachedFileNamesItInTheMessage() {
		String token = ProjectIntakeFileService.createUploadToken();
		ContentVersion layout = ProjectIntakeTestData.createLayout(token);
		ContentVersion spec = ProjectIntakeTestData.createSpec(token);
		List<ProjectIntakeRequest.FileRef> refs = new List<ProjectIntakeRequest.FileRef>{
			ref(layout.Id, 'LAYOUT'),
			ref(spec.Id, 'SPEC')
		};
		ProjectIntakeFileService.attachFilesToLead(insertLead().Id, token, refs);

		String message = expectAttachError(insertLead().Id, token, refs);

		Assert.areEqual('"layout": ' + Constants.INTAKE_ERR_FILE_IN_USE, message);
	}
}
