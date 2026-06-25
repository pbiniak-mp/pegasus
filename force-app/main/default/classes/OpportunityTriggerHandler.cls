/**
 * Opportunity trigger handler. Delegates outbound integration dispatch to
 * OutboundIntegrationService on insert and on StageName change.
 */
public with sharing class OpportunityTriggerHandler extends TriggerHandler {

	public override void afterInsert() {
		OutboundIntegrationService.handleOpportunityInsert(Trigger.new);
	}

	public override void afterUpdate() {
		OutboundIntegrationService.handleOpportunityStageChange(
			Trigger.new,
			(Map<Id, Opportunity>) Trigger.oldMap
		);
	}
}
