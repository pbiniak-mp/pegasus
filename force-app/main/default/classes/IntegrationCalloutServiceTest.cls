@IsTest
private class IntegrationCalloutServiceTest {

	private static final String ENDPOINT = 'callout:Glide_Analytics/opportunities';
	private static final String SECRET_HEADER_VALUE = 'ApiKey super-secret-value';

	private class Mock implements HttpCalloutMock {
		private Integer code;
		private Mock(Integer code) {
			this.code = code;
		}
		public HttpResponse respond(HttpRequest req) {
			HttpResponse res = new HttpResponse();
			res.setStatusCode(code);
			res.setBody('{"echo":true}');
			res.setHeader('X-Request-Id', 'req-1');
			res.setHeader('Authorization', SECRET_HEADER_VALUE);
			return res;
		}
	}

	private class ThrowingMock implements HttpCalloutMock {
		public HttpResponse respond(HttpRequest req) {
			throw new CalloutException('Connection refused');
		}
	}

	@IsTest
	static void successCapturesResponseAndMasksAuthorization() {
		Test.setMock(HttpCalloutMock.class, new Mock(201));

		Test.startTest();
		IntegrationCalloutService.CalloutResult result =
			IntegrationCalloutService.send(Constants.INTEGRATION_HTTP_METHOD_POST, ENDPOINT, '{"a":1}');
		Test.stopTest();

		Assert.isTrue(result.isSuccess, 'Any 2xx status is a success');
		Assert.areEqual(201, result.statusCode);
		Assert.isNull(result.errorMessage, 'No error on success');
		Assert.areEqual(ENDPOINT, result.endpoint);
		Assert.areEqual('{"echo":true}', result.responseBody);
		Assert.isTrue(result.requestHeaders.contains(Constants.HTTP_CONTENT_TYPE_JSON),
			'Request headers are recorded');
		Assert.isTrue(result.responseHeaders.contains('req-1'), 'Response headers are recorded');
		Assert.isTrue(result.responseHeaders.contains(Constants.INTEGRATION_MASKED_VALUE),
			'Authorization response header is masked');
		Assert.isFalse(result.responseHeaders.contains(SECRET_HEADER_VALUE),
			'The secret must never be persisted');
	}

	@IsTest
	static void non2xxIsFailureWithHttpError() {
		Test.setMock(HttpCalloutMock.class, new Mock(404));

		Test.startTest();
		IntegrationCalloutService.CalloutResult result = IntegrationCalloutService.send(
			Constants.INTEGRATION_HTTP_METHOD_PATCH, ENDPOINT + '/006000000000001', '{"a":1}');
		Test.stopTest();

		Assert.isFalse(result.isSuccess, '4xx is a failure');
		Assert.areEqual(404, result.statusCode);
		Assert.areEqual('HTTP 404', result.errorMessage);
	}

	@IsTest
	static void exceptionIsCapturedNotThrown() {
		Test.setMock(HttpCalloutMock.class, new ThrowingMock());

		Test.startTest();
		IntegrationCalloutService.CalloutResult result =
			IntegrationCalloutService.send(Constants.INTEGRATION_HTTP_METHOD_POST, ENDPOINT, null);
		Test.stopTest();

		Assert.isFalse(result.isSuccess, 'Exception path is a failure');
		Assert.isNull(result.statusCode, 'No HTTP status when the callout throws');
		Assert.isTrue(result.errorMessage.contains('CalloutException'), 'Exception type captured');
		Assert.isTrue(result.errorMessage.contains('Connection refused'), 'Exception message captured');
	}
}
