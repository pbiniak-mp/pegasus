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
		debugIncomingRequest(request, requestBody);

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

		System.debug(
			LoggingLevel.INFO,
			Constants.NETSUITE_INVENTORY_DEBUG_PREFIX + 'Parsed run ' + payload.runId
				+ ', batch ' + payload.batchNumber + '/' + payload.batchCount
				+ ', generatedAt ' + payload.generatedAt
				+ ', ' + payload.items.size() + ' rows'
		);

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

		String responseJson = JSON.serialize(result, true);
		System.debug(LoggingLevel.INFO, Constants.NETSUITE_INVENTORY_DEBUG_PREFIX + 'Response 200: ' + responseJson);
		RestResponseUtils.sendJson(Constants.HTTP_STATUS_OK, responseJson);
	}

	/**
	 * Headers worth seeing when debugging a sync. Salesforce adds many platform
	 * headers (x-forwarded-client-cert alone carries a whole certificate), so only
	 * these are logged. Authorization is never logged, only whether it was sent.
	 */
	private static final Set<String> DEBUG_HEADER_NAMES = new Set<String>{
		'user-agent',
		'content-type',
		'content-length',
		'accept',
		'x-forwarded-for'
	};

	/**
	 * Writes exactly what NetSuite sent to the debug log: who the request runs as
	 * (the External Client App run-as user), where it came from, the relevant
	 * headers and the raw body. The same body is also stored on the
	 * Integration_Log__c record, which is easier to read after the fact.
	 */
	private static void debugIncomingRequest(RestRequest request, String requestBody) {
		Map<String, String> debugHeaders = new Map<String, String>();
		if (request.headers != null) {
			for (String name : request.headers.keySet()) {
				if (name.equalsIgnoreCase(Constants.HTTP_HEADER_AUTHORIZATION)) {
					debugHeaders.put(name, Constants.INTEGRATION_MASKED_VALUE);
				} else if (DEBUG_HEADER_NAMES.contains(name.toLowerCase())) {
					debugHeaders.put(name, request.headers.get(name));
				}
			}
		}
		System.debug(
			LoggingLevel.INFO,
			Constants.NETSUITE_INVENTORY_DEBUG_PREFIX + 'Received ' + request.httpMethod + ' ' + request.requestURI
				+ ' from ' + request.remoteAddress
				+ ' as ' + UserInfo.getUserName()
				+ ', body ' + (requestBody == null ? 0 : requestBody.length()) + ' chars'
				+ ', headers ' + JSON.serialize(debugHeaders)
		);
		System.debug(LoggingLevel.INFO, Constants.NETSUITE_INVENTORY_DEBUG_PREFIX + 'Request body: ' + requestBody);
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
