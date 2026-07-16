/**
 * Opportunity trigger handler. Delegates outbound integration dispatch to
 * GlideAnalyticsIntegrationService on insert and on StageName change.
 */
public with sharing class OpportunityTriggerHandler extends TriggerHandler {

	public override void beforeInsert() {
		StateCodeService.applyProjectStateCodes(Trigger.new, null);
	}

	public override void beforeUpdate() {
		StateCodeService.applyProjectStateCodes(Trigger.new, (Map<Id, Opportunity>) Trigger.oldMap);
	}

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
