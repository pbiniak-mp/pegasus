@IsTest
private class ProjectIntakeServiceTest {
	private static final String COMPANY = 'Intake Test Co';

	private class Submission {
		String token;
		ContentVersion layout;
		ContentVersion spec;
		Map<String, Object> request;
	}

	private static Submission newSubmission() {
		Submission submission = new Submission();
		submission.token = ProjectIntakeFileService.createUploadToken();
		submission.layout = ProjectIntakeTestData.createLayout(submission.token);
		submission.spec = ProjectIntakeTestData.createSpec(submission.token);
		submission.request = ProjectIntakeTestData.validRequest(
			submission.token,
			submission.layout,
			submission.spec
		);
		return submission;
	}

	private static String submitExpectingError(Map<String, Object> request) {
		return submitJsonExpectingError(JSON.serialize(request));
	}

	private static String submitJsonExpectingError(String json) {
		try {
			ProjectIntakeService.submitIntake(json);
		} catch (ProjectIntakeService.IntakeValidationException e) {
			return e.getMessage();
		}
		Assert.fail('Expected IntakeValidationException');
		return null;
	}

	private static Integer leadCount() {
		return [SELECT COUNT() FROM Lead WHERE Company = :COMPANY];
	}

	// ---- options ---------------------------------------------------------------

	@IsTest
	static void getFormOptions_returnsPicklistsCountriesAndStates() {
		ProjectIntakeOptions options = ProjectIntakeService.getFormOptions();

		for (String key : new List<String>{
			'moduleManufacturer',
			'moduleWattage',
			'systemType',
			'systemConfiguration',
			'panelTilt',
			'designPreference',
			'ballastBlockSpecification',
			'codeStandard',
			'roofSurface',
			'constructionType',
			'distributorType'
		}) {
			Assert.isTrue(options.picklists.containsKey(key), 'Missing picklist ' + key);
		}
		Assert.areEqual(3, options.countries.size());
		Assert.areEqual('US', options.countries[0].value);
		Assert.areEqual('CA', options.countries[1].value);
		Assert.areEqual('MX', options.countries[2].value);
		Assert.areEqual(3, options.statesByCountry.size());

		Set<String> usStates = new Set<String>();
		for (ProjectIntakeOptions.Option state : options.statesByCountry.get('US')) {
			usStates.add(state.value);
		}
		Assert.isTrue(usStates.contains('AZ'), 'US states should include AZ');
		Assert.isFalse(usStates.contains('ON'), 'Canadian provinces must not be listed for US');
		Assert.isFalse(options.statesByCountry.get('MX').isEmpty());
		Assert.isFalse(options.statesByCountry.get('CA').isEmpty());
	}

	@IsTest
	static void getFormOptions_systemTypeContainsContractValues() {
		Set<String> values = new Set<String>();
		for (ProjectIntakeOptions.Option option : ProjectIntakeService.getFormOptions()
			.picklists.get('systemType')) {
			values.add(option.value);
		}

		Assert.isTrue(values.contains('Flat Roof'));
		Assert.isTrue(values.contains('Pitched Roof'));
		Assert.isTrue(values.contains('Ground Mount'));
	}

	@IsTest
	static void isValidFor_decodesTheBitmap() {
		// bytes 0x80 0x01: bit 0 and bit 15 are set
		String bitmap = EncodingUtil.base64Encode(EncodingUtil.convertFromHex('8001'));

		Assert.isTrue(ProjectIntakeService.isValidFor(bitmap, 0));
		Assert.isFalse(ProjectIntakeService.isValidFor(bitmap, 1));
		Assert.isFalse(ProjectIntakeService.isValidFor(bitmap, 8));
		Assert.isTrue(ProjectIntakeService.isValidFor(bitmap, 15));
		Assert.isFalse(ProjectIntakeService.isValidFor(bitmap, 16), 'Beyond the bitmap');
		Assert.isFalse(ProjectIntakeService.isValidFor(null, 0));
		Assert.isFalse(ProjectIntakeService.isValidFor('', 0));
		Assert.isFalse(ProjectIntakeService.isValidFor(bitmap, -1));
		Assert.isFalse(ProjectIntakeService.isValidFor(bitmap, null));
	}

	// ---- happy paths -----------------------------------------------------------

	@IsTest
	static void submitIntake_createsLeadWithMappedFieldsAndFiles() {
		Submission submission = newSubmission();

		ProjectIntakeService.submitIntake(JSON.serialize(submission.request));

		Lead lead = [
			SELECT
				Id, LeadSource, Status, ProjectName__c, CountryCode, StateCode, Street, City,
				PostalCode, Project_Notes__c, Planned_Install_Date__c, Project_Wattage_kW__c,
				Module_Wattage__c, Module_Model_Number__c, System_Type__c, System_Configuration__c,
				Panel_Tilt__c, UL_3741_compliance__c, DesignPreference__c, Building_Height_ft__c,
				Roof_Pitch__c, Setback_Distance_ft__c, Ground_Slope__c, Company, FirstName,
				LastName, Email, Phone, Distributor_Type__c, Known_Disty__c, LegalConsent__c
			FROM Lead
			WHERE Company = :COMPANY
		];
		Assert.areEqual('Web', lead.LeadSource);
		Assert.areEqual('New', lead.Status);
		Assert.areEqual('Test Project', lead.ProjectName__c);
		Assert.areEqual('US', lead.CountryCode);
		Assert.areEqual('AZ', lead.StateCode);
		Assert.areEqual('145 Pegasus Way', lead.Street);
		Assert.areEqual('Phoenix', lead.City);
		Assert.areEqual('85001', lead.PostalCode);
		Assert.areEqual('Some notes', lead.Project_Notes__c);
		Assert.areEqual(Date.today().addDays(30), lead.Planned_Install_Date__c);
		Assert.areEqual(120.5, lead.Project_Wattage_kW__c);
		Assert.areEqual('MNU-10XS', lead.Module_Model_Number__c);
		Assert.areEqual('Pitched Roof', lead.System_Type__c);
		Assert.areEqual('South Facing', lead.System_Configuration__c);
		Assert.areEqual('10°', lead.Panel_Tilt__c);
		Assert.isFalse(lead.UL_3741_compliance__c, 'UL 3741 only applies to Flat Roof');
		Assert.areEqual(Constants.INTAKE_DESIGN_PREFERENCE_ATTACHED, lead.DesignPreference__c);
		Assert.areEqual(20, lead.Building_Height_ft__c);
		Assert.areEqual(5, lead.Roof_Pitch__c);
		Assert.areEqual(3, lead.Setback_Distance_ft__c);
		Assert.isNull(lead.Ground_Slope__c, 'Ground fields are ignored for a roof system');
		Assert.areEqual('Jane', lead.FirstName);
		Assert.areEqual('Doe', lead.LastName);
		Assert.areEqual('jane.doe@example.com', lead.Email);
		Assert.areEqual('(555) 555-5555', lead.Phone);
		Assert.areEqual('Indirect', lead.Distributor_Type__c);
		Assert.areEqual('Acme Distribution', lead.Known_Disty__c);
		Assert.isTrue(lead.LegalConsent__c);

		Assert.areEqual(
			2,
			[SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :lead.Id],
			'Both files should be linked to the Lead'
		);
		Assert.areEqual(
			'Module Layout - layout',
			[SELECT Title FROM ContentVersion WHERE Id = :submission.layout.Id].Title
		);
	}

	@IsTest
	static void submitIntake_groundMountIgnoresBuildingFieldsAndKeepsSiteFields() {
		Submission submission = newSubmission();
		submission.request.put('systemType', 'Ground Mount');
		submission.request.put('systemConfiguration', 'East/West Facing');
		submission.request.put('panelTilt', '10°');
		submission.request.put('arrayAzimuth', 180);
		submission.request.put('landfillLocation', true);
		submission.request.put('ul3741Compliance', true);
		submission.request.put('distributorType', 'Direct');

		ProjectIntakeService.submitIntake(JSON.serialize(submission.request));

		Lead lead = [
			SELECT
				Building_Height_ft__c, Roof_Pitch__c, Ground_Slope__c, Array_Azimuth__c,
				Landfill_Location__c, UL_3741_compliance__c, Known_Disty__c
			FROM Lead
			WHERE Company = :COMPANY
		];
		Assert.isNull(lead.Building_Height_ft__c);
		Assert.isNull(lead.Roof_Pitch__c);
		Assert.areEqual(4, lead.Ground_Slope__c);
		Assert.areEqual(180, lead.Array_Azimuth__c);
		Assert.isTrue(lead.Landfill_Location__c);
		Assert.isFalse(lead.UL_3741_compliance__c);
		Assert.isNull(lead.Known_Disty__c, 'Known Disty only applies to Indirect');
	}

	@IsTest
	static void submitIntake_flatRoofFlushMountFillsLockedValues() {
		Submission submission = newSubmission();
		submission.request.put('systemType', 'Flat Roof');
		submission.request.put('systemConfiguration', 'Flush Mount');
		submission.request.remove('panelTilt');
		submission.request.remove('designPreference');
		submission.request.put('ul3741Compliance', true);

		ProjectIntakeService.submitIntake(JSON.serialize(submission.request));

		Lead lead = [
			SELECT Panel_Tilt__c, DesignPreference__c, UL_3741_compliance__c
			FROM Lead
			WHERE Company = :COMPANY
		];
		Assert.areEqual('0°', lead.Panel_Tilt__c);
		Assert.areEqual(Constants.INTAKE_DESIGN_PREFERENCE_ATTACHED, lead.DesignPreference__c);
		Assert.isTrue(lead.UL_3741_compliance__c);
	}

	@IsTest
	static void submitIntake_ballastedDesignKeepsBallastSpecification() {
		Submission submission = newSubmission();
		String ballast = ProjectIntakeTestData.firstOptionValue('ballastBlockSpecification');
		submission.request.put('designPreference', Constants.INTAKE_DESIGN_PREFERENCE_BALLASTED);
		submission.request.put('ballastBlockSpecification', ballast);

		ProjectIntakeService.submitIntake(JSON.serialize(submission.request));

		Assert.areEqual(
			ballast,
			[SELECT Ballast_Block_Specification__c FROM Lead WHERE Company = :COMPANY]
			.Ballast_Block_Specification__c
		);
	}

	// ---- validation ------------------------------------------------------------

	@IsTest
	static void submitIntake_missingRequiredFieldsListsErrorsAndCreatesNothing() {
		String message = submitJsonExpectingError('{}');

		Assert.isTrue(message.contains('Project Name is required.'), message);
		Assert.areEqual(0, leadCount());
	}

	@IsTest
	static void submitIntake_reportsEachRequiredField() {
		Submission submission = newSubmission();
		for (String key : new List<String>{
			'projectName', 'street', 'city', 'postalCode', 'plannedInstallDate',
			'projectWattageKw', 'moduleWattage', 'moduleModelNumber', 'systemType', 'company',
			'firstName', 'lastName', 'email', 'phone', 'countryCode', 'buildingHeightFt'
		}) {
			Map<String, Object> request = ProjectIntakeTestData.validRequest(
				submission.token, submission.layout, submission.spec
			);
			request.remove(key);
			String message = submitExpectingError(request);
			Assert.isFalse(String.isBlank(message), 'No error for missing ' + key);
		}
		Assert.areEqual(0, leadCount());
	}

	@IsTest
	static void submitIntake_conditionalRequiredFields() {
		Submission submission = newSubmission();
		submission.request.put('designPreference', Constants.INTAKE_DESIGN_PREFERENCE_HYBRID);
		submission.request.remove('knownDisty');
		submission.request.remove('roofPitch');

		String message = submitExpectingError(submission.request);

		Assert.isTrue(message.contains('Ballast Block Specification is required.'), message);
		Assert.isTrue(message.contains('Distribution Partner is required.'), message);
		Assert.isTrue(message.contains('Roof Pitch is required.'), message);
	}

	@IsTest
	static void submitIntake_rejectsInvalidValues() {
		Submission submission = newSubmission();
		submission.request.put('projectName', 'x'.repeat(31));
		submission.request.put('moduleModelNumber', 'x'.repeat(26));
		submission.request.put('email', 'not-an-email');
		submission.request.put('legalConsent', false);
		submission.request.put('projectWattageKw', 0);
		submission.request.put('roofPitch', -1);
		submission.request.put('setbackDistanceFt', 0);
		submission.request.put('moduleWattage', 'bogus');

		String message = submitExpectingError(submission.request);

		Assert.isTrue(message.length() > 0);
		Assert.areEqual(0, leadCount());
	}

	@IsTest
	static void submitIntake_eachInvalidValueGetsItsMessage() {
		Submission base = newSubmission();
		Map<String, Object> request;

		request = ProjectIntakeTestData.validRequest(base.token, base.layout, base.spec);
		request.put('projectName', 'x'.repeat(31));
		Assert.isTrue(submitExpectingError(request).contains('Project Name must be at most 30'));

		request = ProjectIntakeTestData.validRequest(base.token, base.layout, base.spec);
		request.put('email', 'not-an-email');
		Assert.isTrue(submitExpectingError(request).contains('Email is not a valid'));

		request = ProjectIntakeTestData.validRequest(base.token, base.layout, base.spec);
		request.put('legalConsent', false);
		Assert.isTrue(submitExpectingError(request).contains('accept the terms'));

		request = ProjectIntakeTestData.validRequest(base.token, base.layout, base.spec);
		request.put('projectWattageKw', 0);
		Assert.isTrue(submitExpectingError(request).contains('must be greater than 0'));

		request = ProjectIntakeTestData.validRequest(base.token, base.layout, base.spec);
		request.put('roofPitch', -1);
		Assert.isTrue(submitExpectingError(request).contains('Roof Pitch cannot be negative'));

		request = ProjectIntakeTestData.validRequest(base.token, base.layout, base.spec);
		request.put('projectWattageKw', 100000000000000L);
		Assert.isTrue(submitExpectingError(request).contains('too large'));

		request = ProjectIntakeTestData.validRequest(base.token, base.layout, base.spec);
		request.put('moduleWattage', 'bogus');
		Assert.isTrue(submitExpectingError(request).contains('Module Wattage has an invalid value'));
	}

	@IsTest
	static void submitIntake_rejectsZeroRoofPitchAsValidButNegativeAsInvalid() {
		Submission submission = newSubmission();
		submission.request.put('roofPitch', 0);

		ProjectIntakeService.submitIntake(JSON.serialize(submission.request));

		Assert.areEqual(1, leadCount(), 'Roof pitch 0 is allowed');
	}

	@IsTest
	static void submitIntake_rejectsPastInstallDate() {
		Submission submission = newSubmission();
		submission.request.put('plannedInstallDate', String.valueOf(Date.today().addDays(-1)));

		String message = submitExpectingError(submission.request);

		Assert.isTrue(message.contains(Constants.INTAKE_ERR_PAST_DATE), message);
		Assert.areEqual(0, leadCount());
	}

	@IsTest
	static void submitIntake_rejectsInvalidSystemCombinations() {
		Submission base = newSubmission();
		Map<String, Object> request;

		request = ProjectIntakeTestData.validRequest(base.token, base.layout, base.spec);
		request.put('systemType', 'Ground Mount');
		request.put('systemConfiguration', 'Flush Mount');
		Assert.isTrue(
			submitExpectingError(request).contains('System Configuration is not available')
		);

		request = ProjectIntakeTestData.validRequest(base.token, base.layout, base.spec);
		request.put('systemType', 'Flat Roof');
		request.put('systemConfiguration', 'East/West Facing');
		request.put('panelTilt', '15°');
		Assert.isTrue(submitExpectingError(request).contains('Panel Tilt is not available'));

		request = ProjectIntakeTestData.validRequest(base.token, base.layout, base.spec);
		request.put('systemType', 'Flat Roof');
		request.put('systemConfiguration', 'Flush Mount');
		request.put('panelTilt', '0°');
		request.put('designPreference', Constants.INTAKE_DESIGN_PREFERENCE_HYBRID);
		request.put(
			'ballastBlockSpecification',
			ProjectIntakeTestData.firstOptionValue('ballastBlockSpecification')
		);
		Assert.isTrue(submitExpectingError(request).contains('requires an Attached design'));

		request = ProjectIntakeTestData.validRequest(base.token, base.layout, base.spec);
		request.put('systemType', 'Flat Roof');
		request.remove('systemConfiguration');
		request.put('panelTilt', '20°');
		Assert.isTrue(submitExpectingError(request).contains('Panel Tilt is not available'));

		Assert.areEqual(0, leadCount());
	}

	@IsTest
	static void submitIntake_rejectsStateOutsideCountryAndUnknownCountry() {
		Submission base = newSubmission();
		Map<String, Object> request = ProjectIntakeTestData.validRequest(base.token, base.layout, base.spec);
		request.put('stateCode', 'ON');
		Assert.isTrue(submitExpectingError(request).contains('State / Province'));

		request = ProjectIntakeTestData.validRequest(base.token, base.layout, base.spec);
		request.put('countryCode', 'PL');
		Assert.isTrue(submitExpectingError(request).contains('Country is required'));
	}

	@IsTest
	static void submitIntake_rejectsMalformedRequests() {
		Submission submission = newSubmission();

		Assert.areEqual(Constants.INTAKE_ERR_INVALID_SUBMISSION, submitJsonExpectingError(null));
		Assert.areEqual(Constants.INTAKE_ERR_INVALID_SUBMISSION, submitJsonExpectingError('  '));
		Assert.areEqual(Constants.INTAKE_ERR_INVALID_SUBMISSION, submitJsonExpectingError('{not json'));
		Assert.areEqual(Constants.INTAKE_ERR_INVALID_SUBMISSION, submitJsonExpectingError('null'));
		Assert.areEqual(
			Constants.INTAKE_ERR_INVALID_SUBMISSION,
			submitJsonExpectingError('x'.repeat(Constants.INTAKE_MAX_REQUEST_LENGTH + 1))
		);

		submission.request.put('ownerId', '005000000000000AAA');
		Assert.areEqual(
			Constants.INTAKE_ERR_INVALID_SUBMISSION,
			submitExpectingError(submission.request),
			'Unknown JSON keys must be rejected'
		);
		Assert.areEqual(0, leadCount());
	}

	// ---- files -----------------------------------------------------------------

	@IsTest
	static void submitIntake_requiresBothFileCategories() {
		Submission submission = newSubmission();
		submission.request.put('files', new List<Object>());

		String message = submitExpectingError(submission.request);

		Assert.isTrue(message.startsWith('Please upload'), message);
		Assert.areEqual(0, leadCount());
	}

	@IsTest
	static void submitIntake_fileOfAnotherTokenRollsBackTheLead() {
		Submission submission = newSubmission();
		ContentVersion foreignLayout = ProjectIntakeTestData.createLayout(
			ProjectIntakeFileService.createUploadToken()
		);
		submission.request.put(
			'files',
			new List<Object>{
				new Map<String, Object>{ 'contentVersionId' => foreignLayout.Id, 'category' => 'LAYOUT' },
				new Map<String, Object>{ 'contentVersionId' => submission.spec.Id, 'category' => 'SPEC' }
			}
		);

		String message = submitExpectingError(submission.request);

		Assert.areEqual(Constants.INTAKE_ERR_FILE_NOT_FOUND, message);
		Assert.areEqual(0, leadCount(), 'The Lead must be rolled back when files cannot be attached');
	}

	@IsTest
	static void submitIntake_invalidUploadTokenIsRejected() {
		Submission submission = newSubmission();
		submission.request.put('uploadToken', 'short');

		Assert.areEqual(Constants.INTAKE_ERR_SESSION, submitExpectingError(submission.request));
	}

	@IsTest
	static void logSafely_neverThrows() {
		ProjectIntakeService.logSafely('ProjectIntakeServiceTest', 'logSafely', 'test message', null);

		Assert.isTrue(true, 'No exception expected');
	}

	@IsTest
	static void submitIntake_bulkOfSubmissionsInSeparateTransactionsAreIndependent() {
		for (Integer i = 0; i < 3; i++) {
			Submission submission = newSubmission();
			submission.request.put('projectName', 'Project ' + i);
			ProjectIntakeService.submitIntake(JSON.serialize(submission.request));
		}

		Assert.areEqual(3, leadCount());
	}
}
