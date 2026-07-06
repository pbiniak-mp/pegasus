/**
 * Opportunity trigger handler. Delegates outbound integration dispatch to
 * GlideAnalyticsIntegrationService on insert and on StageName change.
 */
public with sharing class OpportunityTriggerHandler extends TriggerHandler {

	public override void afterInsert() {
		GlideAnalyticsIntegrationService.handleOpportunityInsert(Trigger.new);
	}

	public override void afterUpdate() {
		GlideAnalyticsIntegrationService.handleOpportunityStageChange(
			Trigger.new,
			(Map<Id, Opportunity>) Trigger.oldMap
		);
	}
}
