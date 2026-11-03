/**
 * Queries for Project_Intake_Upload__c, the record of files uploaded through the
 * public Project Intake form.
 *
 * Queries run WITH SYSTEM_MODE: no user, the guest included, has field access to these
 * records; they are only read by the Project Intake services.
 *
 * Sharing follows the caller: ProjectIntakeFileService runs without sharing on purpose,
 * because the rows are owned by the site's default record owner and the guest user has
 * no access to them. Access is constrained in the service by upload token, uploader
 * and age instead.
 */
public inherited sharing class ProjectIntakeUploadSelector {
	public static List<Project_Intake_Upload__c> getByContentVersionIds(
		Set<String> contentVersionIds
	) {
		return [
			SELECT
				Id,
				Upload_Token__c,
				Category__c,
				Content_Version_Id__c,
				Content_Document_Id__c,
				File_Name__c,
				File_Extension__c,
				Size_Bytes__c,
				Lead__c,
				CreatedById,
				CreatedDate
			FROM Project_Intake_Upload__c
			WHERE Content_Version_Id__c IN :contentVersionIds
			WITH SYSTEM_MODE
		];
	}

	/** Uploads of the given tokens that are not attached to a Lead yet. */
	public static List<Project_Intake_Upload__c> getUnattachedByTokens(Set<String> tokens) {
		return [
			SELECT Id, Upload_Token__c, Category__c
			FROM Project_Intake_Upload__c
			WHERE Upload_Token__c IN :tokens AND Lead__c = NULL
			WITH SYSTEM_MODE
		];
	}
}
