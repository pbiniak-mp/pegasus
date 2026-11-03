/**
 * Entry point of the public Project Intake form (Experience Cloud guest user).
 * The only Apex class the site guest profile / permission set exposes. It never returns
 * record data or Ids; validation messages are shown as they are, every other failure is
 * logged and replaced by a generic message.
 */
public with sharing class ProjectIntakeController {
	@AuraEnabled(cacheable=true scope='global')
	public static ProjectIntakeOptions getFormOptions() {
		try {
			return ProjectIntakeService.getFormOptions();
		} catch (Exception e) {
			// Cacheable calls cannot perform DML, so there is nothing to log here.
			throw handledError(e, 'getFormOptions', false);
		}
	}

	@AuraEnabled
	public static String createUploadToken() {
		try {
			return ProjectIntakeFileService.createUploadToken();
		} catch (Exception e) {
			throw handledError(e, 'createUploadToken', true);
		}
	}

	@AuraEnabled
	public static List<ProjectIntakeFileInfo> getUploadedFiles(
		String token,
		List<Id> contentVersionIds
	) {
		try {
			return ProjectIntakeFileService.describeUploadedFiles(token, contentVersionIds);
		} catch (Exception e) {
			throw handledError(e, 'getUploadedFiles', true);
		}
	}

	@AuraEnabled
	public static void removeUploadedFile(String token, Id contentVersionId) {
		try {
			ProjectIntakeFileService.removeUploadedFile(token, contentVersionId);
		} catch (Exception e) {
			throw handledError(e, 'removeUploadedFile', true);
		}
	}

	@AuraEnabled
	public static void submitIntake(String requestJson) {
		try {
			ProjectIntakeService.submitIntake(requestJson);
		} catch (Exception e) {
			throw handledError(e, 'submitIntake', true);
		}
	}

	private static AuraHandledException handledError(
		Exception cause,
		String methodName,
		Boolean logIt
	) {
		String message = Constants.INTAKE_ERR_GENERIC;
		if (cause instanceof ProjectIntakeService.IntakeValidationException) {
			message = cause.getMessage();
		} else if (logIt) {
			ProjectIntakeService.logSafely(
				Constants.INTAKE_CLASS_NAME,
				methodName,
				cause.getMessage(),
				cause.getStackTraceString()
			);
		}
		AuraHandledException error = new AuraHandledException(message);
		error.setMessage(message);
		return error;
	}
}
