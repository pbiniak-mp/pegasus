/**
 * Inbound endpoint for the daily NetSuite -> Salesforce inventory sync.
 * POST /services/apexrest/netsuite/inventory
 *
 * Request (one batch; NetSuite sends ~50 items x all 12 locations per call):
 * {
 *   "runId": "NSINV-20260917T120000Z",       groups all batches of one run
 *   "generatedAt": "2026-09-17T12:00:00.000Z",
 *   "batchNumber": 1,
 *   "batchCount": 8,
 *   "items": [{
 *     "netsuiteItemId": "2354",               item.id
 *     "netsuiteItemName": "PSR-B84",          item.itemid, used for the name fallback
 *     "netsuiteLocationId": "2",              location.id
 *     "locationName": "Richmond - Main Facility",
 *     "onHandQty": 59220,
 *     "committedQty": 2800
 *   }]
 * }
 *
 * Every request writes one Inbound Integration_Log__c and answers with the
 * JSON sync summary (see NetSuiteInventorySyncService.SyncResult). Unresolvable
 * rows are reported, not failed: the response is 200 whenever the payload could
 * be processed. 400 = unusable payload, 500 = unexpected error (rolled back).
 */
@RestResource(UrlMapping='/netsuite/inventory/*')
global with sharing class NetSuiteInventoryApi {

	private static final String CLASS_NAME = 'NetSuiteInventoryApi';

	@HttpPost
	global static void handlePost() {
		RestRequest request = RestContext.request;
		String requestBody = request.requestBody == null ? null : request.requestBody.toString();

		if (String.isBlank(requestBody)) {
			respondWithError(null, requestBody, Constants.HTTP_STATUS_BAD_REQUEST, Constants.NETSUITE_INVENTORY_MSG_EMPTY_BODY);
			return;
		}

		NetSuiteInventorySyncService.SyncRequest payload;
		try {
			payload = (NetSuiteInventorySyncService.SyncRequest) JSON.deserialize(
				requestBody,
				NetSuiteInventorySyncService.SyncRequest.class
			);
		} catch (Exception e) {
			respondWithError(
				null,
				requestBody,
				Constants.HTTP_STATUS_BAD_REQUEST,
				Constants.NETSUITE_INVENTORY_MSG_MALFORMED_JSON + e.getMessage()
			);
			return;
		}

		if (payload == null || payload.items == null || payload.items.isEmpty()) {
			respondWithError(
				payload == null ? null : payload.runId,
				requestBody,
				Constants.HTTP_STATUS_BAD_REQUEST,
				Constants.NETSUITE_INVENTORY_MSG_EMPTY_PAYLOAD
			);
			return;
		}

		Savepoint beforeSync = Database.setSavepoint();
		NetSuiteInventorySyncService.SyncResult result;
		try {
			result = NetSuiteInventorySyncService.sync(payload);
		} catch (Exception e) {
			Database.rollback(beforeSync);
			BoltErrorLogger.logError(
				CLASS_NAME,
				'handlePost',
				Constants.NETSUITE_INVENTORY_ERROR_CATEGORY + ' failed: ' + e.getMessage(),
				e.getStackTraceString(),
				Constants.SOURCE_TYPE_APEX,
				Constants.SEVERITY_ERROR,
				UserInfo.getUserId(),
				null
			);
			respondWithError(
				payload.runId,
				requestBody,
				Constants.HTTP_STATUS_INTERNAL_ERROR,
				Constants.NETSUITE_INVENTORY_MSG_UNEXPECTED_ERROR + e.getTypeName() + ': ' + e.getMessage()
			);
			return;
		}

		Integration_Log__c log = buildLog(payload.runId, requestBody);
		String summaryJson = JSON.serialize(result, true);
		IntegrationLogService.applyInboundResult(
			log,
			result.status,
			Constants.HTTP_STATUS_OK,
			summaryJson,
			describeProblems(result)
		);
		result.logId = insertLog(log);

		RestResponseUtils.sendJson(Constants.HTTP_STATUS_OK, JSON.serialize(result, true));
	}

	private static void respondWithError(String runId, String requestBody, Integer statusCode, String message) {
		Map<String, Object> body = new Map<String, Object>{
			'status' => Constants.INTEGRATION_STATUS_FAILED,
			'runId' => runId,
			'message' => message
		};
		Integration_Log__c log = buildLog(runId, requestBody);
		IntegrationLogService.applyInboundResult(
			log,
			Constants.INTEGRATION_STATUS_FAILED,
			statusCode,
			JSON.serialize(body, true),
			message
		);
		body.put('logId', insertLog(log));

		System.debug(LoggingLevel.ERROR, Constants.NETSUITE_INVENTORY_DEBUG_PREFIX + statusCode + ' ' + message);
		RestResponseUtils.sendJson(statusCode, JSON.serialize(body, true));
	}

	private static Integration_Log__c buildLog(String runId, String requestBody) {
		return IntegrationLogService.buildInboundLog(
			Constants.NETSUITE_INVENTORY_INTEGRATION_NAME,
			Constants.NETSUITE_INVENTORY_EVENT_TYPE,
			Constants.NETSUITE_INVENTORY_SOURCE_OBJECT,
			Constants.NETSUITE_INVENTORY_ENDPOINT,
			Constants.INTEGRATION_HTTP_METHOD_POST,
			requestBody,
			runId
		);
	}

	/**
	 * Human-readable list of everything that did not land, for Error_Message__c.
	 * Null when the batch was fully applied.
	 */
	private static String describeProblems(NetSuiteInventorySyncService.SyncResult result) {
		List<String> lines = new List<String>();
		if (!result.skipped.isEmpty()) {
			lines.add('Skipped:');
			lines.addAll(result.skipped);
		}
		if (!result.errors.isEmpty()) {
			lines.add('Failed:');
			lines.addAll(result.errors);
		}
		return lines.isEmpty() ? null : String.join(lines, '\n');
	}

	/**
	 * A logging failure must never turn a processed batch into an error response,
	 * so it is reported through BoltErrorLogger instead of thrown.
	 */
	private static Id insertLog(Integration_Log__c log) {
		try {
			insert log;
			return log.Id;
		} catch (Exception e) {
			BoltErrorLogger.logError(
				CLASS_NAME,
				'insertLog',
				Constants.NETSUITE_INVENTORY_ERROR_CATEGORY + ' log insert failed: ' + e.getMessage(),
				e.getStackTraceString(),
				Constants.SOURCE_TYPE_APEX,
				Constants.SEVERITY_ERROR,
				UserInfo.getUserId(),
				null
			);
			return null;
		}
	}
}
