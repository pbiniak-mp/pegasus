public with sharing class RestResponseUtils {
	public static void sendJson(Integer statusCode, String jsonBody) {
		RestContext.response.statusCode = statusCode;
		RestContext.response.addHeader(Constants.HTTP_HEADER_CONTENT_TYPE, Constants.HTTP_CONTENT_TYPE_JSON);
		RestContext.response.responseBody = Blob.valueOf(jsonBody == null ? '' : jsonBody);
	}
}
