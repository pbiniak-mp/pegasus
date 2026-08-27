/**
 * Drains Queued Integration_Log__c records and sends each one (1 log = 1 callout)
 * using the HTTP method + endpoint stored on the log (POST for create, PATCH for
 * stage change). Processes a bounded chunk to stay under the 100-callout governor
 * limit, writes the response back to the log, and chains itself while more Queued
 * logs remain.
 *
 * The log is the single source of truth for delivery state: it carries the
 * status, endpoint, HTTP code and error message. The only thing mirrored onto the
 * Opportunity is Last_Sent__c, and only on success - a fact that stays true
 * regardless of what happens later, unlike a status that silently goes stale when
 * no further event fires.
 */
public with sharing class IntegrationCalloutQueueable implements Queueable, Database.AllowsCallouts {

	public void execute(QueueableContext context) {
		List<Integration_Log__c> logs = IntegrationLogSelector.getQueued(Constants.INTEGRATION_CALLOUT_CHUNK_SIZE);
		if (logs.isEmpty()) {
			return;
		}

		List<Integration_Log__c> logsToUpdate = new List<Integration_Log__c>();
		Map<Id, Opportunity> oppStampsById = new Map<Id, Opportunity>();
		Datetime sentAt = Datetime.now();

		for (Integration_Log__c log : logs) {
			IntegrationCalloutService.CalloutResult result =
				IntegrationCalloutService.send(log.HTTP_Method__c, log.Endpoint__c, log.Request_Body__c);
			IntegrationLogService.applyCalloutResult(log, result);
			logsToUpdate.add(log);

			// Only a delivery is worth recording on the Opportunity. A failure lives
			// on the log, which carries the endpoint, status code and error message
			// the Opportunity never could.
			if (result.isSuccess && log.Opportunity__c != null) {
				oppStampsById.put(log.Opportunity__c, new Opportunity(
					Id = log.Opportunity__c,
					Last_Sent__c = sentAt
				));
			}
		}

		update logsToUpdate;
		stampOpportunities(oppStampsById.values());
		chainIfMoreQueued();
	}

	private static void stampOpportunities(List<Opportunity> opps) {
		if (opps.isEmpty()) {
			return;
		}
		// Stamp must not re-trigger the outbound flow.
		TriggerHandler.bypass(Constants.OPPORTUNITY_HANDLER_NAME);
		try {
			update opps;
		} finally {
			TriggerHandler.clearBypass(Constants.OPPORTUNITY_HANDLER_NAME);
		}
	}

	private static void chainIfMoreQueued() {
		if (Test.isRunningTest()) {
			return;
		}
		Boolean canEnqueue = (Limits.getLimitQueueableJobs() - Limits.getQueueableJobs()) > 0;
		if (canEnqueue && IntegrationLogSelector.countQueued() > 0) {
			System.enqueueJob(new IntegrationCalloutQueueable());
		}
	}
}
