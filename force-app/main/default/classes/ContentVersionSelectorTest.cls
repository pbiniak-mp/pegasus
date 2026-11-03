@IsTest
private class ContentVersionSelectorTest {
	@IsTest
	static void getByIds_returnsRequestedVersions() {
		String token = ProjectIntakeFileService.createUploadToken();
		ContentVersion layout = ProjectIntakeTestData.createLayout(token);
		ProjectIntakeTestData.createSpec(token);

		List<ContentVersion> result = ContentVersionSelector.getByIds(new Set<Id>{ layout.Id });

		Assert.areEqual(1, result.size());
		Assert.areEqual(layout.ContentDocumentId, result[0].ContentDocumentId);
		Assert.areEqual(token + '|LAYOUT', result[0].Intake_Token_fileupload__c);
		Assert.areEqual(UserInfo.getUserId(), result[0].CreatedById);
		Assert.isTrue(result[0].IsLatest);
	}

	@IsTest
	static void getByTokenValues_matchesExactValuesOnly() {
		String token = ProjectIntakeFileService.createUploadToken();
		String otherToken = ProjectIntakeFileService.createUploadToken();
		ProjectIntakeTestData.createLayout(token);
		ProjectIntakeTestData.createSpec(token);
		ProjectIntakeTestData.createLayout(otherToken);

		List<ContentVersion> result = ContentVersionSelector.getByTokenValues(
			new Set<String>{ token + '|LAYOUT', token + '|SPEC' }
		);

		Assert.areEqual(2, result.size(), 'Only files of the given token should be returned');
	}

	@IsTest
	static void getLinksExcludingUser_skipsTheUploaderLink() {
		String token = ProjectIntakeFileService.createUploadToken();
		ContentVersion layout = ProjectIntakeTestData.createLayout(token);
		Lead lead = new Lead(LastName = 'Linked', Company = 'Linked Co');
		insert lead;
		insert new ContentDocumentLink(
			ContentDocumentId = layout.ContentDocumentId,
			LinkedEntityId = lead.Id,
			ShareType = 'V'
		);

		List<ContentDocumentLink> links = ContentVersionSelector.getLinksExcludingUser(
			new Set<Id>{ layout.ContentDocumentId },
			UserInfo.getUserId()
		);

		Assert.areEqual(1, links.size(), 'The uploader user link must be excluded');
		Assert.areEqual(lead.Id, links[0].LinkedEntityId);
	}
}
