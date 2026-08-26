@IsTest
private class QuotePDFAccessServiceTest {

	private static final String STANDARD_PROFILE = 'Standard User';

	/**
	 * The real check, with no override in play: a user who holds no permission
	 * set granting Generate_Quote_PDF must be refused. Run as a freshly built
	 * standard user so the result does not depend on what the developer running
	 * the tests happens to be assigned.
	 */
	@IsTest
	static void canGeneratePDF_forAUserWithoutTheCustomPermission_isFalse() {
		User plainUser = buildUser();

		Boolean allowed;
		System.runAs(plainUser) {
			allowed = QuotePDFAccessService.canGeneratePDF();
		}

		Assert.isFalse(allowed, 'A user without the permission set must not be able to publish a quote');
	}

	@IsTest
	static void canGeneratePDF_whenGranted_isTrue() {
		QuotePDFTestDataFactory.grantPDFPermission();

		Assert.isTrue(QuotePDFAccessService.canGeneratePDF(), 'A granted user should be able to publish a quote');
	}

	@IsTest
	static void canGeneratePDF_whenRevoked_isFalse() {
		QuotePDFTestDataFactory.revokePDFPermission();

		Assert.isFalse(QuotePDFAccessService.canGeneratePDF(), 'A revoked user should not be able to publish a quote');
	}

	@IsTest
	static void refusalMessage_tellsTheUserWhatToAskFor() {
		Assert.isTrue(
			QuotePDFAccessService.MSG_NO_PERMISSION.contains('Quote PDF Generation'),
			'The refusal should name the permission set to request: ' + QuotePDFAccessService.MSG_NO_PERMISSION
		);
	}

	private static User buildUser() {
		Profile p = [SELECT Id FROM Profile WHERE Name = :STANDARD_PROFILE LIMIT 1];
		String unique = String.valueOf(Datetime.now().getTime());
		User u = new User(
			ProfileId = p.Id,
			LastName = 'NoPdfPermission',
			Email = 'no.pdf.permission@example.com',
			Username = 'no.pdf.permission.' + unique + '@example.com',
			Alias = 'nopdf',
			TimeZoneSidKey = 'America/Los_Angeles',
			LocaleSidKey = 'en_US',
			EmailEncodingKey = 'UTF-8',
			LanguageLocaleKey = 'en_US'
		);
		insert u;
		return u;
	}
}
