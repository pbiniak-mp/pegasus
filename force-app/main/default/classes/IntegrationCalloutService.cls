/**
 * Generic, reusable HTTP layer for outbound integrations.
 * The caller supplies the HTTP method and full `callout:` endpoint; this class
 * performs a single callout and returns a structured result (status, body, masked
 * headers). It never throws on callout failure — failures are captured in
 * CalloutResult so the caller can log them per record. Emits System.debug at
 * request and response for live UAT troubleshooting.
 */
public with sharing class IntegrationCalloutService {

	private static final String CLASS_NAME = 'IntegrationCalloutService';

	public class CalloutResult {
		public String endpoint;
		public String requestHeaders;
		public Integer statusCode;
		public String responseHeaders;
		public String responseBody;
		public Boolean isSuccess = false;
		public String errorMessage;
	}

	public static CalloutResult send(String method, String endpoint, String body) {
		CalloutResult result = new CalloutResult();
		result.endpoint = endpoint;

		Map<String, String> headers = new Map<String, String>{
			Constants.HTTP_HEADER_CONTENT_TYPE => Constants.HTTP_CONTENT_TYPE_JSON,
			Constants.HTTP_HEADER_ACCEPT => Constants.HTTP_CONTENT_TYPE_JSON
		};
		result.requestHeaders = serializeMaskedHeaders(headers);

		HttpRequest req = new HttpRequest();
		req.setEndpoint(endpoint);
		req.setMethod(method);
		for (String key : headers.keySet()) {
			req.setHeader(key, headers.get(key));
		}
		req.setTimeout(Constants.INTEGRATION_CALLOUT_TIMEOUT_MS);
		if (String.isNotBlank(body)) {
			req.setBody(body);
		}

		System.debug(LoggingLevel.INFO, Constants.INTEGRATION_LOG_DEBUG_PREFIX + 'Request -> '
			+ method + ' ' + endpoint + ' | headers=' + result.requestHeaders + ' | body=' + body);

		try {
			HttpResponse res = new Http().send(req);
			result.statusCode = res.getStatusCode();
			result.responseBody = res.getBody();
			result.responseHeaders = serializeResponseHeaders(res);
			result.isSuccess = result.statusCode >= 200 && result.statusCode < 300;
			if (!result.isSuccess) {
				result.errorMessage = 'HTTP ' + result.statusCode;
			}
			System.debug(LoggingLevel.INFO, Constants.INTEGRATION_LOG_DEBUG_PREFIX + 'Response <- '
				+ result.statusCode + ' | headers=' + result.responseHeaders + ' | body=' + result.responseBody);
		} catch (Exception e) {
			result.isSuccess = false;
			result.errorMessage = e.getTypeName() + ': ' + e.getMessage();
			System.debug(LoggingLevel.ERROR, Constants.INTEGRATION_LOG_DEBUG_PREFIX
				+ 'Callout exception -> ' + result.errorMessage);
			BoltErrorLogger.logError(
				CLASS_NAME,
				'send',
				Constants.INTEGRATION_ERROR_CATEGORY + ' callout failed: ' + e.getMessage(),
				e.getStackTraceString(),
				Constants.SOURCE_TYPE_APEX,
				Constants.SEVERITY_ERROR,
				UserInfo.getUserId(),
				null
			);
		}
		return result;
	}

	private static String serializeMaskedHeaders(Map<String, String> headers) {
		Map<String, String> masked = new Map<String, String>();
		for (String key : headers.keySet()) {
			masked.put(key, isSensitive(key) ? Constants.INTEGRATION_MASKED_VALUE : headers.get(key));
		}
		return JSON.serialize(masked);
	}

	private static String serializeResponseHeaders(HttpResponse res) {
		Map<String, String> headers = new Map<String, String>();
		for (String key : res.getHeaderKeys()) {
			if (key == null) {
				continue;
			}
			headers.put(key, isSensitive(key) ? Constants.INTEGRATION_MASKED_VALUE : res.getHeader(key));
		}
		return JSON.serialize(headers);
	}

	private static Boolean isSensitive(String headerName) {
		return headerName != null && headerName.equalsIgnoreCase(Constants.HTTP_HEADER_AUTHORIZATION);
	}
}
