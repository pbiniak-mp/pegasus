/**
 * File handling for the public Project Intake form.
 *
 * The site guest user uploads files with lightning-file-upload before the Lead exists.
 * Each upload carries Intake_Token_fileupload__c = '<token>|<CATEGORY>' for the token
 * held by the browser session. The file is owned by the site's default record owner,
 * and file access applies to the guest even in system mode, so the guest cannot query
 * the file after the upload. Therefore:
 *   - the ContentVersion trigger validates the file and records it in
 *     Project_Intake_Upload__c in the upload transaction (prepareUploads /
 *     registerUploads), when the file is still at hand in Trigger.new;
 *   - the form and the submit work with those records only.
 *
 * Database access to Project_Intake_Upload__c and the file links is in SYSTEM_MODE
 * explicitly: nobody, the guest included, has field access to the upload records.
 *
 * Runs WITHOUT sharing on purpose: the upload records are owned by the default record
 * owner and the guest has no access to them. Access is constrained instead by
 *   - the upload token of the browser session,
 *   - the uploader (the running user, i.e. the shared guest user),
 *   - the age of the upload (Constants.INTAKE_TOKEN_MAX_AGE_HOURS),
 *   - the upload not being attached to a Lead yet (so a used file cannot be reused or
 *     removed through the form).
 * The class is not @AuraEnabled; it is only reachable through ProjectIntakeController
 * and ContentVersionTriggerHandler.
 */
public without sharing class ProjectIntakeFileService {
	private static final String CLASS_NAME = 'ProjectIntakeFileService';
	// An external user (the site guest) may only create links visible to all users. The
	// Lead itself is private and not shared with any external user.
	private static final String VISIBILITY_ALL_USERS = 'AllUsers';
	private static final String SHARE_TYPE_INFERRED = 'I';
	private static final Integer BYTES_PER_KB = 1024;
	private static final Integer BYTES_PER_MB = 1048576;
	private static final Integer MAX_TITLE_LENGTH = 255;

	// Test hooks: allow exercising size / age limits without huge blobs or waiting.
	@TestVisible
	private static Map<String, Integer> maxBytesOverride = new Map<String, Integer>();
	@TestVisible
	private static Integer maxAgeHours = Constants.INTAKE_TOKEN_MAX_AGE_HOURS;
	// Last unexpected error of the upload trigger, so tests can report the real cause.
	@TestVisible
	private static Exception lastUnexpectedError;

	/**
	 * Creates an unguessable token that correlates the uploads of one form session.
	 * @return 32 lowercase hex characters
	 */
	public static String createUploadToken() {
		return EncodingUtil.convertToHex(Crypto.generateAESKey(128));
	}

	// ---------------------------------------------------------------------------------
	// Upload transaction (ContentVersion trigger)
	// ---------------------------------------------------------------------------------

	/**
	 * Before insert: rejects intake uploads with an unknown token or a file type that is
	 * not allowed for the category, and prefixes the title with the category label.
	 * Files without Intake_Token_fileupload__c are ignored.
	 */
	public static void prepareUploads(List<ContentVersion> versions) {
		for (ContentVersion version : intakeUploads(versions)) {
			try {
				UploadKey key = parseUploadKey(version.Intake_Token_fileupload__c);
				if (key == null) {
					version.addError(Constants.INTAKE_ERR_SESSION);
					continue;
				}
				String error = validateExtension(extensionOf(version), key.category);
				if (error != null) {
					version.addError(error);
					continue;
				}
				String prefix = Constants.INTAKE_FILE_TITLE_PREFIX.get(key.category);
				String title = String.isBlank(version.Title)
					? fileNameOf(version.PathOnClient).substringBeforeLast('.')
					: version.Title;
				if (!title.startsWith(prefix)) {
					version.Title = (prefix + title).left(MAX_TITLE_LENGTH);
				}
			} catch (Exception e) {
				rejectUnexpected(version, 'prepareUploads', e);
			}
		}
	}

	/**
	 * After insert: rejects intake uploads that are too large or exceed the number of
	 * files of their category, and records the accepted ones in Project_Intake_Upload__c.
	 */
	public static void registerUploads(List<ContentVersion> versions) {
		List<ContentVersion> uploads = intakeUploads(versions);
		if (uploads.isEmpty()) {
			return;
		}
		try {
			Map<String, Integer> countByKey = countUnattached(uploads);
			List<Project_Intake_Upload__c> records = new List<Project_Intake_Upload__c>();
			for (ContentVersion version : uploads) {
				UploadKey key = parseUploadKey(version.Intake_Token_fileupload__c);
				if (key == null) {
					version.addError(Constants.INTAKE_ERR_SESSION);
					continue;
				}
				String error = validateSize(version.ContentSize, key.category);
				Integer count = countByKey.containsKey(key.value) ? countByKey.get(key.value) : 0;
				Integer maxFiles = Constants.INTAKE_FILE_MAX_FILES.get(key.category);
				if (error == null && count >= maxFiles) {
					error = String.format(
						Constants.INTAKE_ERR_FILE_COUNT,
						new List<String>{ maxFiles + (maxFiles == 1 ? ' file' : ' files') }
					);
				}
				if (error != null) {
					version.addError(error);
					continue;
				}
				countByKey.put(key.value, count + 1);
				records.add(toUploadRecord(version, key));
			}
			Database.insert(records, AccessLevel.SYSTEM_MODE);
		} catch (Exception e) {
			for (ContentVersion version : uploads) {
				rejectUnexpected(version, 'registerUploads', e);
			}
		}
	}

	// ---------------------------------------------------------------------------------
	// Form (ProjectIntakeController)
	// ---------------------------------------------------------------------------------

	/**
	 * Describes freshly uploaded files. Type, size and count were already enforced in the
	 * upload transaction; this confirms the files belong to the form session.
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
		Map<String, Project_Intake_Upload__c> uploadsByVersionId = getUploads(contentVersionIds);
		for (Id contentVersionId : contentVersionIds) {
			Project_Intake_Upload__c upload = uploadsByVersionId.get(String.valueOf(contentVersionId));
			String error = upload == null
				? Constants.INTAKE_ERR_FILE_NOT_FOUND
				: validateUpload(upload, token, null);
			results.add(toInfo(contentVersionId, upload, error));
		}
		return results;
	}

	/**
	 * Removes a file the visitor removed from the form. Only uploads of the token and the
	 * running user that are not attached to a Lead are removed. A file that is not
	 * recorded is ignored.
	 */
	public static void removeUploadedFile(String token, Id contentVersionId) {
		requireValidToken(token);
		if (contentVersionId == null) {
			return;
		}
		Project_Intake_Upload__c upload = getUploads(new List<Id>{ contentVersionId })
			.get(String.valueOf(contentVersionId));
		if (upload == null) {
			return;
		}
		if (validateUpload(upload, token, null) != null) {
			throw new ProjectIntakeService.IntakeValidationException(
				Constants.INTAKE_ERR_FILE_REMOVE
			);
		}
		Database.delete(upload, AccessLevel.SYSTEM_MODE);
		// The guest usually cannot delete a file it does not own. The file then stays
		// orphaned, which is harmless: it is never linked to a Lead.
		Database.delete(
			new List<Id>{ Id.valueOf(upload.Content_Document_Id__c) },
			false,
			AccessLevel.SYSTEM_MODE
		);
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

		List<Id> versionIds = new List<Id>();
		for (ProjectIntakeRequest.FileRef ref : files) {
			versionIds.add(ref.contentVersionId);
		}
		Map<String, Project_Intake_Upload__c> uploadsByVersionId = getUploads(versionIds);

		List<ContentDocumentLink> links = new List<ContentDocumentLink>();
		List<Project_Intake_Upload__c> attached = new List<Project_Intake_Upload__c>();
		for (ProjectIntakeRequest.FileRef ref : files) {
			Project_Intake_Upload__c upload = uploadsByVersionId.get(
				String.valueOf(ref.contentVersionId)
			);
			if (upload == null) {
				throw new ProjectIntakeService.IntakeValidationException(
					Constants.INTAKE_ERR_FILE_NOT_FOUND
				);
			}
			String error = validateUpload(upload, token, ref.category);
			if (error == Constants.INTAKE_ERR_FILE_NOT_FOUND) {
				// Never reveal the name of a file of another form session.
				throw new ProjectIntakeService.IntakeValidationException(error);
			}
			if (error != null) {
				throw new ProjectIntakeService.IntakeValidationException(
					'"' + upload.File_Name__c + '": ' + error
				);
			}
			links.add(
				new ContentDocumentLink(
					ContentDocumentId = Id.valueOf(upload.Content_Document_Id__c),
					LinkedEntityId = leadId,
					ShareType = SHARE_TYPE_INFERRED,
					Visibility = VISIBILITY_ALL_USERS
				)
			);
			attached.add(new Project_Intake_Upload__c(Id = upload.Id, Lead__c = leadId));
		}

		Database.insert(links, AccessLevel.SYSTEM_MODE);
		Database.update(attached, AccessLevel.SYSTEM_MODE);
	}

	// ---------------------------------------------------------------------------------
	// Helpers
	// ---------------------------------------------------------------------------------

	/** Token and category encoded in Intake_Token_fileupload__c. */
	private class UploadKey {
		public String value;
		public String token;
		public String category;
	}

	private static List<ContentVersion> intakeUploads(List<ContentVersion> versions) {
		List<ContentVersion> uploads = new List<ContentVersion>();
		for (ContentVersion version : versions) {
			if (String.isNotBlank(version.Intake_Token_fileupload__c)) {
				uploads.add(version);
			}
		}
		return uploads;
	}

	/** @return the parsed value, or null when the token or the category is not valid */
	private static UploadKey parseUploadKey(String value) {
		String token = value.substringBefore(Constants.INTAKE_TOKEN_SEPARATOR);
		String category = value.substringAfter(Constants.INTAKE_TOKEN_SEPARATOR);
		if (
			!isValidToken(token) ||
			!Constants.INTAKE_FILE_MAX_FILES.containsKey(category) ||
			value != tokenValue(token, category)
		) {
			return null;
		}
		UploadKey key = new UploadKey();
		key.value = value;
		key.token = token;
		key.category = category;
		return key;
	}

	private static Boolean isValidToken(String token) {
		return String.isNotBlank(token) && Pattern.matches(Constants.INTAKE_TOKEN_PATTERN, token);
	}

	private static void requireValidToken(String token) {
		if (!isValidToken(token)) {
			throw new ProjectIntakeService.IntakeValidationException(Constants.INTAKE_ERR_SESSION);
		}
	}

	private static String tokenValue(String token, String category) {
		return token + Constants.INTAKE_TOKEN_SEPARATOR + category;
	}

	/** Unattached uploads per token value ('<token>|<CATEGORY>') of the given versions. */
	private static Map<String, Integer> countUnattached(List<ContentVersion> uploads) {
		Set<String> tokens = new Set<String>();
		for (ContentVersion version : uploads) {
			tokens.add(version.Intake_Token_fileupload__c.substringBefore(Constants.INTAKE_TOKEN_SEPARATOR));
		}
		Map<String, Integer> countByKey = new Map<String, Integer>();
		for (Project_Intake_Upload__c upload : ProjectIntakeUploadSelector.getUnattachedByTokens(tokens)) {
			String key = tokenValue(upload.Upload_Token__c, upload.Category__c);
			countByKey.put(key, countByKey.containsKey(key) ? countByKey.get(key) + 1 : 1);
		}
		return countByKey;
	}

	private static Map<String, Project_Intake_Upload__c> getUploads(List<Id> contentVersionIds) {
		Set<String> ids = new Set<String>();
		for (Id contentVersionId : contentVersionIds) {
			ids.add(String.valueOf(contentVersionId));
		}
		Map<String, Project_Intake_Upload__c> uploadsByVersionId = new Map<String, Project_Intake_Upload__c>();
		for (Project_Intake_Upload__c upload : ProjectIntakeUploadSelector.getByContentVersionIds(ids)) {
			uploadsByVersionId.put(upload.Content_Version_Id__c, upload);
		}
		return uploadsByVersionId;
	}

	private static Project_Intake_Upload__c toUploadRecord(ContentVersion version, UploadKey key) {
		String prefix = Constants.INTAKE_FILE_TITLE_PREFIX.get(key.category);
		return new Project_Intake_Upload__c(
			Upload_Token__c = key.token,
			Category__c = key.category,
			Content_Version_Id__c = String.valueOf(version.Id),
			Content_Document_Id__c = version.ContentDocumentId,
			File_Name__c = String.isBlank(version.Title) ? null : version.Title.removeStart(prefix),
			File_Extension__c = extensionOf(version),
			Size_Bytes__c = version.ContentSize
		);
	}

	private static String fileNameOf(String pathOnClient) {
		String path = String.isBlank(pathOnClient) ? '' : pathOnClient.replace('\\', '/');
		return path.substringAfterLast('/') == '' ? path : path.substringAfterLast('/');
	}

	private static String extensionOf(ContentVersion version) {
		String extension = String.isNotBlank(version.FileExtension)
			? version.FileExtension
			: fileNameOf(version.PathOnClient).substringAfterLast('.');
		return String.isBlank(extension) ? '' : extension.toLowerCase();
	}

	private static Integer maxBytesFor(String category) {
		return maxBytesOverride.containsKey(category)
			? maxBytesOverride.get(category)
			: Constants.INTAKE_FILE_MAX_BYTES.get(category);
	}

	private static String validateExtension(String extension, String category) {
		if (Constants.INTAKE_FILE_EXTENSIONS.get(category).contains(extension)) {
			return null;
		}
		return String.format(
			Constants.INTAKE_ERR_FILE_TYPE,
			new List<String>{ String.isBlank(extension) ? '(none)' : extension }
		);
	}

	private static String validateSize(Integer sizeBytes, String category) {
		Integer maxBytes = maxBytesFor(category);
		if (sizeBytes == null || sizeBytes <= maxBytes) {
			return null;
		}
		return String.format(
			Constants.INTAKE_ERR_FILE_TOO_LARGE,
			new List<String>{ formatSize(maxBytes) }
		);
	}

	/**
	 * @param category expected category, or null when any category of the token is fine
	 * @return a user-facing reason the upload cannot be used, or null when it can
	 */
	private static String validateUpload(
		Project_Intake_Upload__c upload,
		String token,
		String category
	) {
		if (
			upload.Upload_Token__c != token ||
			(category != null && upload.Category__c != category) ||
			upload.CreatedById != UserInfo.getUserId()
		) {
			return Constants.INTAKE_ERR_FILE_NOT_FOUND;
		}
		if (upload.Lead__c != null) {
			return Constants.INTAKE_ERR_FILE_IN_USE;
		}
		if (upload.CreatedDate < Datetime.now().addHours(-maxAgeHours)) {
			return Constants.INTAKE_ERR_FILE_EXPIRED;
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
		Id contentVersionId,
		Project_Intake_Upload__c upload,
		String error
	) {
		ProjectIntakeFileInfo info = new ProjectIntakeFileInfo();
		info.contentVersionId = contentVersionId;
		if (upload != null) {
			info.title = upload.File_Name__c;
			info.extension = upload.File_Extension__c;
			info.sizeBytes = upload.Size_Bytes__c == null ? null : upload.Size_Bytes__c.intValue();
			info.category = upload.Category__c;
		}
		info.isValid = error == null;
		info.errorMessage = error;
		return info;
	}

	/** Rejects an intake upload after an unexpected error; the cause is logged. */
	private static void rejectUnexpected(ContentVersion version, String methodName, Exception e) {
		// The upload is rolled back with the log entry, so keep a debug trace as well.
		lastUnexpectedError = e;
		System.debug(LoggingLevel.ERROR, CLASS_NAME + '.' + methodName + ': ' + e.getMessage());
		ProjectIntakeService.logSafely(CLASS_NAME, methodName, e.getMessage(), e.getStackTraceString());
		version.addError(Constants.INTAKE_ERR_UPLOAD_FAILED);
	}
}
