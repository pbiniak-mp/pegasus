/**
 * Queries for ContentVersion used by the Project Intake file handling.
 *
 * No USER_MODE / WITH SECURITY_ENFORCED on purpose: these methods are called from
 * ProjectIntakeFileService (without sharing) for files uploaded by the guest user,
 * who has no read access to ContentVersion. Access is constrained in the service
 * by upload token, uploader and age instead.
 */
public inherited sharing class ContentVersionSelector {
	public static List<ContentVersion> getByIds(Set<Id> contentVersionIds) {
		return [
			SELECT
				Id,
				ContentDocumentId,
				Title,
				FileExtension,
				ContentSize,
				Intake_Token_fileupload__c,
				CreatedById,
				CreatedDate,
				IsLatest
			FROM ContentVersion
			WHERE Id IN :contentVersionIds
		];
	}

	/**
	 * @param tokenValues exact field values, for example '<token>|LAYOUT' and '<token>|SPEC'
	 */
	public static List<ContentVersion> getByTokenValues(Set<String> tokenValues) {
		return [
			SELECT
				Id,
				ContentDocumentId,
				Title,
				FileExtension,
				ContentSize,
				Intake_Token_fileupload__c,
				CreatedById,
				CreatedDate,
				IsLatest
			FROM ContentVersion
			WHERE Intake_Token_fileupload__c IN :tokenValues
			ORDER BY CreatedDate ASC, Id ASC
		];
	}

	/**
	 * Returns the links of the given documents to anything other than the uploader's own
	 * user link (the implicit link created for an unattached upload).
	 */
	public static List<ContentDocumentLink> getLinksExcludingUser(
		Set<Id> contentDocumentIds,
		Id uploaderId
	) {
		return [
			SELECT Id, ContentDocumentId, LinkedEntityId
			FROM ContentDocumentLink
			WHERE ContentDocumentId IN :contentDocumentIds AND LinkedEntityId != :uploaderId
		];
	}
}
