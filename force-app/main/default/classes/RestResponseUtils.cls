public with sharing class RestResponseUtils {
	public static void sendText(Integer statusCode, String body) {
		RestContext.response.statusCode = statusCode;
		RestContext.response.addHeader(Constants.HTTP_HEADER_CONTENT_TYPE, Constants.HTTP_CONTENT_TYPE_TEXT_PLAIN);
		RestContext.response.responseBody = Blob.valueOf(body == null ? '' : body);
	}

	public static void sendOk(String message) {
		sendText(Constants.HTTP_STATUS_OK, Constants.HTTP_RESPONSE_PREFIX_OK + message);
	}

	public static void sendBadRequest(String message) {
		sendText(Constants.HTTP_STATUS_BAD_REQUEST, Constants.HTTP_RESPONSE_PREFIX_ERROR + message);
	}

	public static void sendInternalError(Exception e) {
		String body = Constants.HTTP_RESPONSE_PREFIX_ERROR + e.getTypeName() + ': ' + e.getMessage()
			+ '\nStack: ' + e.getStackTraceString();
		sendText(Constants.HTTP_STATUS_INTERNAL_ERROR, body);
	}
}
