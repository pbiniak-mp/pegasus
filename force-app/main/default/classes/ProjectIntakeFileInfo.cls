/**
 * Validation result for one file uploaded to the Project Intake form.
 */
public class ProjectIntakeFileInfo {
	@AuraEnabled
	public Id contentVersionId;
	@AuraEnabled
	public String title;
	@AuraEnabled
	public String extension;
	@AuraEnabled
	public Integer sizeBytes;
	@AuraEnabled
	public String category;
	@AuraEnabled
	public Boolean isValid;
	@AuraEnabled
	public String errorMessage;
}
