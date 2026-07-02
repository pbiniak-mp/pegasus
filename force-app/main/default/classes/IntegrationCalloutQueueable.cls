/**
 * Drains Queued Integration_Log__c records and sends each one (1 log = 1 callout)
 * using the HTTP method + endpoint stored on the log (POST for create, PATCH for
 * stage change). Processes a bounded chunk to stay under the 100-callout governor
 * limit, writes the response back to the log, stamps the source Opportunity, and
 * chains itself while more Queued logs remain.
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

			if (String.isNotBlank(log.Source_Record_Id__c)) {
				oppStampsById.put((Id) log.Source_Record_Id__c, buildStamp(log.Source_Record_Id__c, result, sentAt));
			}
		}

		update logsToUpdate;
		stampOpportunities(oppStampsById.values());
		chainIfMoreQueued();
	}

	private static Opportunity buildStamp(Id oppId, IntegrationCalloutService.CalloutResult result, Datetime sentAt) {
		Opportunity stamp = new Opportunity(Id = oppId);
		stamp.Integration_Status__c = result.isSuccess
			? Constants.OPP_INTEGRATION_STATUS_SENT
			: Constants.OPP_INTEGRATION_STATUS_FAILED;
		// "Last Sent" reflects the last successful delivery only.
		if (result.isSuccess) {
			stamp.Last_Sent__c = sentAt;
		}
		return stamp;
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
