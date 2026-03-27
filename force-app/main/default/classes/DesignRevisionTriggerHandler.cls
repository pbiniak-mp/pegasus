public with sharing class DesignRevisionTriggerHandler extends TriggerHandler {

	private static final String CLASS_NAME = 'DesignRevisionTriggerHandler';
	private static final String ERR_AFTER_INSERT = 'Unhandled error during afterInsert on Design_Revision__c';
	private static final String ERR_AFTER_UPDATE = 'Unhandled error during afterUpdate on Design_Revision__c';
	private static final String ERR_BEFORE_INSERT = 'Unhandled error during beforeInsert on Design_Revision__c';
	private static final String ERR_BEFORE_UPDATE = 'Unhandled error during beforeUpdate on Design_Revision__c';

	public override void beforeInsert() {
		try {
			DesignRevisionService.buildNames(Trigger.new, null);
		} catch (Exception e) {
			BoltErrorLogger.logError(
				CLASS_NAME,
				'beforeInsert',
				ERR_BEFORE_INSERT + ': ' + e.getMessage(),
				e.getStackTraceString(),
				Constants.SOURCE_TYPE_APEX,
				Constants.SEVERITY_ERROR,
				UserInfo.getUserId(),
				null
			);
			throw e;
		}
	}

	public override void beforeUpdate() {
		try {
			DesignRevisionService.buildNames(Trigger.new, (Map<Id, Design_Revision__c>) Trigger.oldMap);
		} catch (Exception e) {
			BoltErrorLogger.logError(
				CLASS_NAME,
				'beforeUpdate',
				ERR_BEFORE_UPDATE + ': ' + e.getMessage(),
				e.getStackTraceString(),
				Constants.SOURCE_TYPE_APEX,
				Constants.SEVERITY_ERROR,
				UserInfo.getUserId(),
				null
			);
			throw e;
		}
	}

	public override void afterInsert() {
		try {
			List<Design_Revision__c> activated = DesignRevisionService.filterActivated(Trigger.new, null);
			if (!activated.isEmpty()) {
				DesignRevisionService.handleActivation(activated);
			}
		} catch (Exception e) {
			BoltErrorLogger.logError(
				CLASS_NAME,
				'afterInsert',
				ERR_AFTER_INSERT + ': ' + e.getMessage(),
				e.getStackTraceString(),
				Constants.SOURCE_TYPE_APEX,
				Constants.SEVERITY_ERROR,
				UserInfo.getUserId(),
				null
			);
			throw e;
		}
	}

	public override void afterUpdate() {
		try {
			List<Design_Revision__c> activated = DesignRevisionService.filterActivated(Trigger.new, (Map<Id, Design_Revision__c>) Trigger.oldMap);
			if (!activated.isEmpty()) {
				DesignRevisionService.handleActivation(activated);
			}
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
