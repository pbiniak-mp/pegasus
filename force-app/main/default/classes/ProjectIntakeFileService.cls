/**
 * File handling for the public Project Intake form.
 *
 * Runs WITHOUT sharing on purpose: the site guest user uploads files before the Lead
 * exists (lightning-file-upload without a record Id), cannot read the Lead after it is
 * inserted and cannot link files to it. Access is therefore constrained by the checks
 * in this class instead of by sharing:
 *   - the file carries Intake_Token_fileupload__c = '<token>|<CATEGORY>' for the
 *     token held by the submitting browser session,
 *   - the file was created by the running user (the shared guest user) in the last
 *     Constants.INTAKE_TOKEN_MAX_AGE_HOURS hours,
 *   - the file is not linked to any record yet (so a used file cannot be reused or
 *     deleted through the form).
 * The class is not @AuraEnabled; it is only reachable through ProjectIntakeController.
 */
public without sharing class ProjectIntakeFileService {
	private static final String CLASS_NAME = 'ProjectIntakeFileService';
	private static final String VISIBILITY_INTERNAL = 'InternalUsers';
	private static final String SHARE_TYPE_INFERRED = 'I';
	private static final Integer BYTES_PER_KB = 1024;
	private static final Integer BYTES_PER_MB = 1048576;
	private static final Integer MAX_TITLE_LENGTH = 255;

	// Test hooks: allow exercising size / age limits without huge blobs or waiting.
	@TestVisible
	private static Map<String, Integer> maxBytesOverride = new Map<String, Integer>();
	@TestVisible
	private static Integer maxAgeHours = Constants.INTAKE_TOKEN_MAX_AGE_HOURS;

	/**
	 * Creates an unguessable token that correlates the uploads of one form session.
	 * @return 32 lowercase hex characters
	 */
	public static String createUploadToken() {
		return EncodingUtil.convertToHex(Crypto.generateAESKey(128));
	}

	/**
	 * Validates freshly uploaded files. Invalid files are deleted and returned with
	 * isValid = false and a user-facing errorMessage.
	 *
	 * @param token upload token of the form session
	 * @param contentVersionIds ContentVersion Ids reported by lightning-file-upload
	 */
	public static List<ProjectIntakeFileInfo> describeUploadedFiles(
		String token,
		List<Id> contentVersionIds
	) {
		requireValidToken(token);
		List<ProjectIntakeFileInfo> results = new List<ProjectIntakeFileInfo>();
		if (contentVersionIds == null || contentVersionIds.isEmpty()) {
			return results;
		}

		// All files of this token, oldest first, so that a per-category limit keeps the
		// earlier uploads and rejects the excess ones.
		List<ContentVersion> tokenFiles = ContentVersionSelector.getByTokenValues(
			tokenValues(token)
		);
		Map<Id, ContentVersion> versionsById = new Map<Id, ContentVersion>(tokenFiles);
		Set<Id> linkedElsewhere = getDocumentsLinkedElsewhere(documentIds(tokenFiles));

		Map<Id, ProjectIntakeFileInfo> infoByVersionId = new Map<Id, ProjectIntakeFileInfo>();
		Map<String, Integer> acceptedByCategory = new Map<String, Integer>();
		for (ContentVersion version : tokenFiles) {
			String category = categoryOf(token, version);
			String error = validateFile(version, category, linkedElsewhere);
			if (error == null) {
				Integer accepted = acceptedByCategory.containsKey(category)
					? acceptedByCategory.get(category) + 1
					: 1;
				acceptedByCategory.put(category, accepted);
				Integer maxFiles = Constants.INTAKE_FILE_MAX_FILES.get(category);
				if (accepted > maxFiles) {
					error = String.format(
						Constants.INTAKE_ERR_FILE_COUNT,
						new List<String>{ maxFiles + (maxFiles == 1 ? ' file' : ' files') }
					);
				}
			}
			infoByVersionId.put(version.Id, toInfo(version, category, error));
		}

		Set<Id> documentsToDelete = new Set<Id>();
		for (Id requestedId : contentVersionIds) {
			ProjectIntakeFileInfo info = infoByVersionId.get(requestedId);
			if (info == null) {
				info = new ProjectIntakeFileInfo();
				info.contentVersionId = requestedId;
				info.isValid = false;
				info.errorMessage = Constants.INTAKE_ERR_FILE_NOT_FOUND;
			} else if (!info.isValid) {
				ContentVersion version = versionsById.get(requestedId);
				// Only clean up files this session's user owns and that are not in use.
				if (
					version.CreatedById == UserInfo.getUserId() &&
					!linkedElsewhere.contains(version.ContentDocumentId)
				) {
					documentsToDelete.add(version.ContentDocumentId);
				}
			}
			results.add(info);
		}
		deleteDocuments(documentsToDelete);
		return results;
	}

	/**
	 * Deletes an uploaded file the visitor removed from the form.
	 * Only files that belong to the token and the running user and are not linked to
	 * any record are deleted. A file that no longer exists is ignored.
	 */
	public static void removeUploadedFile(String token, Id contentVersionId) {
		requireValidToken(token);
		if (contentVersionId == null) {
			return;
		}
		List<ContentVersion> versions = ContentVersionSelector.getByIds(
			new Set<Id>{ contentVersionId }
		);
		if (versions.isEmpty()) {
			return;
		}
		ContentVersion version = versions[0];
		if (
			categoryOf(token, version) == null ||
			version.CreatedById != UserInfo.getUserId() ||
			!getDocumentsLinkedElsewhere(new Set<Id>{ version.ContentDocumentId }).isEmpty()
		) {
			throw new ProjectIntakeService.IntakeValidationException(
				Constants.INTAKE_ERR_FILE_REMOVE
			);
		}
		delete new ContentDocument(Id = version.ContentDocumentId);
	}

	/**
	 * Structural check of the file references (no database access): known categories,
	 * no duplicates and the minimum / maximum number of files per category.
	 */
	public static void validateFileRefs(
		String token,
		List<ProjectIntakeRequest.FileRef> files
	) {
		requireValidToken(token);
		Map<String, Integer> countByCategory = new Map<String, Integer>();
		Set<Id> seen = new Set<Id>();
		if (files != null) {
			for (ProjectIntakeRequest.FileRef ref : files) {
				if (
					ref == null ||
					ref.contentVersionId == null ||
					ref.category == null ||
					!Constants.INTAKE_FILE_MAX_FILES.containsKey(ref.category)
				) {
					throw new ProjectIntakeService.IntakeValidationException(
						Constants.INTAKE_ERR_INVALID_SUBMISSION
					);
				}
				if (!seen.add(ref.contentVersionId)) {
					throw new ProjectIntakeService.IntakeValidationException(
						Constants.INTAKE_ERR_FILE_DUPLICATE
					);
				}
				Integer current = countByCategory.containsKey(ref.category)
					? countByCategory.get(ref.category)
					: 0;
				countByCategory.put(ref.category, current + 1);
			}
		}
		for (String category : Constants.INTAKE_FILE_MAX_FILES.keySet()) {
			Integer count = countByCategory.containsKey(category)
				? countByCategory.get(category)
				: 0;
			String label = Constants.INTAKE_FILE_LABEL.get(category);
			if (count < Constants.INTAKE_FILE_MIN_FILES.get(category)) {
				throw new ProjectIntakeService.IntakeValidationException(
					String.format(
						Constants.INTAKE_ERR_FILE_REQUIRED,
						new List<String>{ 'a ' + label + ' file' }
					)
				);
			}
			Integer maxFiles = Constants.INTAKE_FILE_MAX_FILES.get(category);
			if (count > maxFiles) {
				throw new ProjectIntakeService.IntakeValidationException(
					label +
						': ' +
						String.format(
							Constants.INTAKE_ERR_FILE_COUNT,
							new List<String>{ maxFiles + (maxFiles == 1 ? ' file' : ' files') }
						)
				);
			}
		}
	}

	/**
	 * Re-validates every referenced file and attaches it to the Lead. Must run in the
	 * same transaction as the Lead insert so a failure can roll the Lead back.
	 */
	public static void attachFilesToLead(
		Id leadId,
		String token,
		List<ProjectIntakeRequest.FileRef> files
	) {
		validateFileRefs(token, files);

		Set<Id> versionIds = new Set<Id>();
		for (ProjectIntakeRequest.FileRef ref : files) {
			versionIds.add(ref.contentVersionId);
		}
		Map<Id, ContentVersion> versionsById = new Map<Id, ContentVersion>(
			ContentVersionSelector.getByIds(versionIds)
		);
		Set<Id> linkedElsewhere = getDocumentsLinkedElsewhere(
			documentIds(versionsById.values())
		);

		List<ContentDocumentLink> links = new List<ContentDocumentLink>();
		List<ContentVersion> titleUpdates = new List<ContentVersion>();
		Map<Id, ContentDocument> documentUpdates = new Map<Id, ContentDocument>();
		Id documentOwnerId = getUserOwnerOfLead(leadId);

		for (ProjectIntakeRequest.FileRef ref : files) {
			ContentVersion version = versionsById.get(ref.contentVersionId);
			if (
				version == null ||
				version.Intake_Token_fileupload__c !=
				tokenValue(token, ref.category)
			) {
				throw new ProjectIntakeService.IntakeValidationException(
					Constants.INTAKE_ERR_FILE_NOT_FOUND
				);
			}
			String error = validateFile(version, ref.category, linkedElsewhere);
			if (error != null) {
				throw new ProjectIntakeService.IntakeValidationException(
					'"' + version.Title + '": ' + error
				);
			}

			links.add(
				new ContentDocumentLink(
					ContentDocumentId = version.ContentDocumentId,
					LinkedEntityId = leadId,
					ShareType = SHARE_TYPE_INFERRED,
					Visibility = VISIBILITY_INTERNAL
				)
			);

			String prefix = Constants.INTAKE_FILE_TITLE_PREFIX.get(ref.category);
			if (!version.Title.startsWith(prefix)) {
				titleUpdates.add(
					new ContentVersion(
						Id = version.Id,
						Title = (prefix + version.Title).left(MAX_TITLE_LENGTH)
					)
				);
			}
			if (documentOwnerId != null) {
				documentUpdates.put(
					version.ContentDocumentId,
					new ContentDocument(Id = version.ContentDocumentId, OwnerId = documentOwnerId)
				);
			}
		}

		insert links;

		// Title prefix and ownership are conveniences for the sales team, so a failure
		// there is logged but must not reject the submission.
		logSaveFailures('attachFilesToLead.titles', Database.update(titleUpdates, false));
		logSaveFailures(
			'attachFilesToLead.owners',
			Database.update(documentUpdates.values(), false)
		);
	}

	// ---------------------------------------------------------------------------------
	// Helpers
	// ---------------------------------------------------------------------------------

	private static void requireValidToken(String token) {
		if (String.isBlank(token) || !Pattern.matches(Constants.INTAKE_TOKEN_PATTERN, token)) {
			throw new ProjectIntakeService.IntakeValidationException(Constants.INTAKE_ERR_SESSION);
		}
	}

	private static String tokenValue(String token, String category) {
		return token + Constants.INTAKE_TOKEN_SEPARATOR + category;
	}

	private static Set<String> tokenValues(String token) {
		Set<String> values = new Set<String>();
		for (String category : Constants.INTAKE_FILE_MAX_FILES.keySet()) {
			values.add(tokenValue(token, category));
		}
		return values;
	}

	/** Category encoded in the file's token field, or null when it does not match the token. */
	private static String categoryOf(String token, ContentVersion version) {
		for (String category : Constants.INTAKE_FILE_MAX_FILES.keySet()) {
			if (version.Intake_Token_fileupload__c == tokenValue(token, category)) {
				return category;
			}
		}
		return null;
	}

	private static Set<Id> documentIds(List<ContentVersion> versions) {
		Set<Id> ids = new Set<Id>();
		for (ContentVersion version : versions) {
			ids.add(version.ContentDocumentId);
		}
		return ids;
	}

	/**
	 * Documents linked to something other than the uploader's own user link.
	 * Content library links are ignored; any other link means the file is in use.
	 */
	private static Set<Id> getDocumentsLinkedElsewhere(Set<Id> documentIds) {
		Set<Id> linked = new Set<Id>();
		if (documentIds.isEmpty()) {
			return linked;
		}
		for (
			ContentDocumentLink link : ContentVersionSelector.getLinksExcludingUser(
				documentIds,
				UserInfo.getUserId()
			)
		) {
			if (link.LinkedEntityId.getSobjectType() != Schema.ContentWorkspace.SObjectType) {
				linked.add(link.ContentDocumentId);
			}
		}
		return linked;
	}

	private static Integer maxBytesFor(String category) {
		return maxBytesOverride.containsKey(category)
			? maxBytesOverride.get(category)
			: Constants.INTAKE_FILE_MAX_BYTES.get(category);
	}

	/** @return a user-facing reason the file is not acceptable, or null when it is valid */
	private static String validateFile(
		ContentVersion version,
		String category,
		Set<Id> linkedElsewhere
	) {
		if (
			category == null ||
			!version.IsLatest ||
			version.CreatedById != UserInfo.getUserId()
		) {
			return Constants.INTAKE_ERR_FILE_NOT_FOUND;
		}
		if (version.CreatedDate < Datetime.now().addHours(-maxAgeHours)) {
			return Constants.INTAKE_ERR_FILE_EXPIRED;
		}
		if (linkedElsewhere.contains(version.ContentDocumentId)) {
			return Constants.INTAKE_ERR_FILE_IN_USE;
		}
		String extension = String.isBlank(version.FileExtension)
			? ''
			: version.FileExtension.toLowerCase();
		if (!Constants.INTAKE_FILE_EXTENSIONS.get(category).contains(extension)) {
			return String.format(
				Constants.INTAKE_ERR_FILE_TYPE,
				new List<String>{ String.isBlank(extension) ? '(none)' : extension }
			);
		}
		Integer maxBytes = maxBytesFor(category);
		if (version.ContentSize > maxBytes) {
			return String.format(
				Constants.INTAKE_ERR_FILE_TOO_LARGE,
				new List<String>{ formatSize(maxBytes) }
			);
		}
		return null;
	}

	private static String formatSize(Integer bytes) {
		if (bytes >= BYTES_PER_MB) {
			Integer megabytes = (bytes - Math.mod(bytes, BYTES_PER_MB)) / BYTES_PER_MB;
			return megabytes + ' MB';
		}
		if (bytes >= BYTES_PER_KB) {
			Integer kilobytes = (bytes - Math.mod(bytes, BYTES_PER_KB)) / BYTES_PER_KB;
			return kilobytes + ' KB';
		}
		return bytes + ' bytes';
	}

	private static ProjectIntakeFileInfo toInfo(
		ContentVersion version,
		String category,
		String error
	) {
		ProjectIntakeFileInfo info = new ProjectIntakeFileInfo();
		info.contentVersionId = version.Id;
		info.title = version.Title;
		info.extension = version.FileExtension;
		info.sizeBytes = version.ContentSize;
		info.category = category;
		info.isValid = error == null;
		info.errorMessage = error;
		return info;
	}

	/** Lead owner when it is a user (a queue cannot own a file), otherwise null. */
	private static Id getUserOwnerOfLead(Id leadId) {
		List<Lead> leads = LeadSelector.getOwnersByIds(new Set<Id>{ leadId });
		if (leads.isEmpty()) {
			throw new ProjectIntakeService.IntakeValidationException(Constants.INTAKE_ERR_GENERIC);
		}
		Id ownerId = leads[0].OwnerId;
		return ownerId.getSobjectType() == Schema.User.SObjectType ? ownerId : null;
	}

	private static void deleteDocuments(Set<Id> documentIds) {
		if (documentIds.isEmpty()) {
			return;
		}
		logDeleteFailures(Database.delete(new List<Id>(documentIds), false));
	}

	private static void logDeleteFailures(List<Database.DeleteResult> results) {
		for (Database.DeleteResult result : results) {
			if (!result.isSuccess()) {
				ProjectIntakeService.logSafely(
					CLASS_NAME,
					'deleteDocuments',
					result.getErrors()[0].getMessage(),
					null
				);
			}
		}
	}

	private static void logSaveFailures(String methodName, List<Database.SaveResult> results) {
		for (Database.SaveResult result : results) {
			if (!result.isSuccess()) {
				ProjectIntakeService.logSafely(
					CLASS_NAME,
					methodName,
					result.getErrors()[0].getMessage(),
					null
				);
			}
		}
	}
}
