public with sharing class DesignRevisionTriggerHandler extends TriggerHandler {

	public override void beforeInsert() {
		DesignRevisionService.buildNames(Trigger.new, null);
	}

	public override void beforeUpdate() {
		DesignRevisionService.buildNames(Trigger.new, (Map<Id, Design_Revision__c>) Trigger.oldMap);
		DesignRevisionService.assignOwnerOnStatusChange(Trigger.new, (Map<Id, Design_Revision__c>) Trigger.oldMap);
	}

	public override void afterInsert() {
		List<Design_Revision__c> activated = DesignRevisionService.filterActivated(Trigger.new, null);
		if (!activated.isEmpty()) {
			DesignRevisionService.handleActivation(activated);
		}
	}

	public override void afterUpdate() {
		List<Design_Revision__c> activated = DesignRevisionService.filterActivated(Trigger.new, (Map<Id, Design_Revision__c>) Trigger.oldMap);
		if (!activated.isEmpty()) {
			DesignRevisionService.handleActivation(activated);
		}
		DesignRevisionService.syncOpportunityStageOnStatusChange(Trigger.new, (Map<Id, Design_Revision__c>) Trigger.oldMap);
	}
}
