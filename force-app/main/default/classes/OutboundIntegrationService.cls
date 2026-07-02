/**
 * Entry point for outbound Opportunity integration. Called from the Opportunity
 * trigger handler. Builds one Integration_Log__c per Opportunity (bulk-safe,
 * single DML) and enqueues the async processor. No-op when the integration is
 * inactive in Custom Metadata, so it is safe before the Named Credential exists.
 *
 * Routing per the Glide Analytics contract:
 *   - Created      -> POST  {NC}{path}                 (Salesforce Id in the body)
 *   - Stage change -> PATCH {NC}{path}/{opportunityId}  (Salesforce Id in the URL)
 */
public with sharing class OutboundIntegrationService {

	private static final IIntegrationPayloadBuilder OPPORTUNITY_BUILDER = new OpportunityIntegrationPayloadBuilder();

	// Lets tests inject an active config (CMDT records cannot be inserted in tests).
	@TestVisible
	private static Outbound_Integration__mdt configOverride;

	public static Outbound_Integration__mdt getConfig() {
		if (configOverride != null) {
			return configOverride;
		}
		return Outbound_Integration__mdt.getInstance(Constants.INTEGRATION_GLIDE_ANALYTICS);
	}

	public static void handleOpportunityInsert(List<Opportunity> newOpps) {
		dispatch(newOpps, Constants.INTEGRATION_EVENT_OPP_CREATED);
	}

	public static void handleOpportunityStageChange(List<Opportunity> newOpps, Map<Id, Opportunity> oldMap) {
		List<Opportunity> changed = new List<Opportunity>();
		for (Opportunity opp : newOpps) {
			Opportunity previous = oldMap.get(opp.Id);
			if (previous != null && opp.StageName != previous.StageName) {
				changed.add(opp);
			}
		}
		dispatch(changed, Constants.INTEGRATION_EVENT_OPP_STAGE_CHANGED);
	}

	private static void dispatch(List<Opportunity> opps, String eventType) {
		if (opps == null || opps.isEmpty()) {
			return;
		}

		Outbound_Integration__mdt config = getConfig();
		if (config == null || config.Active__c != true) {
			return;
		}

		Boolean isCreate = eventType == Constants.INTEGRATION_EVENT_OPP_CREATED;
		String httpMethod = isCreate
			? Constants.INTEGRATION_HTTP_METHOD_POST
			: Constants.INTEGRATION_HTTP_METHOD_PATCH;
		String calloutBase = Constants.CALLOUT_PREFIX + config.Named_Credential__c
			+ (String.isBlank(config.Endpoint_Path__c) ? '' : config.Endpoint_Path__c);
		Datetime eventTimestamp = Datetime.now();

		List<Integration_Log__c> logs = new List<Integration_Log__c>();
		for (Opportunity opp : opps) {
			String body = OPPORTUNITY_BUILDER.buildPayload(opp, eventType, eventTimestamp);
			// Create posts to the collection; updates PATCH the record by Salesforce Id in the URL.
			String endpoint = isCreate ? calloutBase : calloutBase + '/' + opp.Id;
			logs.add(IntegrationLogService.buildOutboundLog(
				Constants.INTEGRATION_GLIDE_ANALYTICS,
				eventType,
				opp.Id,
				body,
				httpMethod,
				endpoint,
				eventTimestamp
			));
		}

		System.debug(LoggingLevel.INFO, Constants.INTEGRATION_LOG_DEBUG_PREFIX + 'Queued '
			+ logs.size() + ' ' + eventType + ' log(s)');
		insert logs;
		System.enqueueJob(new IntegrationCalloutQueueable());
	}
}
