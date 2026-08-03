/**
 * Opportunity trigger handler. Populates the Project State Code and the
 * assembled Project Code before save, and delegates outbound integration
 * dispatch to GlideAnalyticsIntegrationService on insert and on StageName change.
 */
public with sharing class OpportunityTriggerHandler extends TriggerHandler {

	public override void beforeInsert() {
		StateCodeService.applyProjectStateCodes(Trigger.new, null);
		ProjectCodeService.apply(Trigger.new, null);
	}

	public override void beforeUpdate() {
		StateCodeService.applyProjectStateCodes(Trigger.new, (Map<Id, Opportunity>) Trigger.oldMap);
		ProjectCodeService.apply(Trigger.new, (Map<Id, Opportunity>) Trigger.oldMap);
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
