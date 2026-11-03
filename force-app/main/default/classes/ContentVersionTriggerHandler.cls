/**
 * ContentVersion trigger handler. Only Project Intake uploads (Intake_Token_fileupload__c
 * set) are processed; every other file passes through untouched. Errors are handled
 * per file in ProjectIntakeFileService so that a failure never blocks unrelated uploads.
 */
public with sharing class ContentVersionTriggerHandler extends TriggerHandler {
	public override void beforeInsert() {
		ProjectIntakeFileService.prepareUploads((List<ContentVersion>) Trigger.new);
	}

	public override void afterInsert() {
		ProjectIntakeFileService.registerUploads((List<ContentVersion>) Trigger.new);
	}
}
