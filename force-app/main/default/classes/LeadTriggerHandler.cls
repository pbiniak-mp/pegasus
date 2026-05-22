public with sharing class LeadTriggerHandler extends TriggerHandler {

	private static final String CLASS_NAME = 'LeadTriggerHandler';
	private static final String ERR_AFTER_UPDATE = 'Unhandled error during afterUpdate on Lead';

	public override void afterUpdate() {
		try {
			LeadService.handleConvertedLeads(
				(List<Lead>) Trigger.new,
				(Map<Id, Lead>) Trigger.oldMap
			);
		} catch (Exception e) {
			BoltErrorLogger.logError(
				CLASS_NAME,
				'afterUpdate',
				ERR_AFTER_UPDATE + ': ' + e.getMessage(),
				e.getStackTraceString(),
				Constants.SOURCE_TYPE_APEX,
				Constants.SEVERITY_ERROR,
				UserInfo.getUserId(),
				null
			);
			throw e;
		}
	}
}
