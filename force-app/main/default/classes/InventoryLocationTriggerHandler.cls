public with sharing class InventoryLocationTriggerHandler extends TriggerHandler {

	private static final String CLASS_NAME = 'InventoryLocationTriggerHandler';
	private static final String ERR_AFTER_INSERT = 'Unhandled error during afterInsert on Inventory_Location__c';
	private static final String ERR_AFTER_UPDATE = 'Unhandled error during afterUpdate on Inventory_Location__c';
	private static final String ERR_AFTER_DELETE = 'Unhandled error during afterDelete on Inventory_Location__c';
	private static final String ERR_AFTER_UNDELETE = 'Unhandled error during afterUndelete on Inventory_Location__c';

	public override void afterInsert() {
		try {
			Set<Id> productIds = InventoryLocationService.collectAffectedProductIds(
				Trigger.new,
				null
			);
			InventoryLocationService.recalculateProductOnHand(productIds);
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
			Set<Id> productIds = InventoryLocationService.collectAffectedProductIds(
				Trigger.new,
				(Map<Id, Inventory_Location__c>) Trigger.oldMap
			);
			InventoryLocationService.recalculateProductOnHand(productIds);
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

	public override void afterDelete() {
		try {
			Set<Id> productIds = InventoryLocationService.collectAffectedProductIds(
				null,
				(Map<Id, Inventory_Location__c>) Trigger.oldMap
			);
			InventoryLocationService.recalculateProductOnHand(productIds);
		} catch (Exception e) {
			BoltErrorLogger.logError(
				CLASS_NAME,
				'afterDelete',
				ERR_AFTER_DELETE + ': ' + e.getMessage(),
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
