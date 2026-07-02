/**
 * Builds the outbound JSON payload for Opportunity integration events.
 * - Created: name, project wattage, stage, Opportunity Id (external Id), timestamp.
 * - Stage Changed: name, Opportunity Id, stage, timestamp.
 */
public with sharing class OpportunityIntegrationPayloadBuilder implements IIntegrationPayloadBuilder {

	private static final String KEY_OPPORTUNITY_ID = 'salesforce_id';
	private static final String KEY_NAME = 'name';
	private static final String KEY_STAGE_NAME = 'stage_name';
	private static final String KEY_WATTAGE_KW = 'project_wattage_kw';
	private static final String KEY_EVENT_TYPE = 'eventType';
	private static final String KEY_EVENT_TIMESTAMP = 'eventTimestamp';

	public String buildPayload(SObject record, String eventType, Datetime eventTimestamp) {
		Opportunity opp = (Opportunity) record;

		Map<String, Object> payload = new Map<String, Object>();
		payload.put(KEY_OPPORTUNITY_ID, opp.Id);
		payload.put(KEY_NAME, opp.Name);
		payload.put(KEY_STAGE_NAME, opp.StageName);
		payload.put(KEY_EVENT_TYPE, eventType);
		payload.put(KEY_EVENT_TIMESTAMP, eventTimestamp);

		// Wattage is only part of the "created" contract.
		if (eventType == Constants.INTEGRATION_EVENT_OPP_CREATED) {
			payload.put(KEY_WATTAGE_KW, opp.Project_Wattage_kW__c);
		}

		return JSON.serialize(payload, true);
	}
}
