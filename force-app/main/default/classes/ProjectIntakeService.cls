/**
 * Business logic for the public Project Intake form (Experience Cloud guest).
 * Builds the picklist options, validates the submitted JSON on the server (the LWC
 * validation is only a convenience) and creates the Lead with its files.
 *
 * inherited sharing: it runs with sharing under ProjectIntakeController; the Lead is
 * inserted in USER_MODE so the guest profile / permission set stays the gatekeeper.
 */
public inherited sharing class ProjectIntakeService {
	/** Thrown with a message that is safe to show to the form visitor. */
	public class IntakeValidationException extends Exception {
	}

	private static final String CLASS_NAME = 'ProjectIntakeService';
	private static final String HEX_DIGITS = '0123456789abcdef';
	private static final Integer MAX_REPORTED_ERRORS = 5;
	private static final Integer MAX_PROJECT_NAME = 30;
	private static final Integer MAX_MODEL_NUMBER = 25;
	private static final Integer MAX_NOTES = 3000;
	private static final Integer MAX_KNOWN_DISTY = 42;
	private static final Integer MAX_STREET = 255;
	private static final Integer MAX_CITY = 40;
	private static final Integer MAX_POSTAL_CODE = 20;
	private static final Integer MAX_COMPANY = 255;
	private static final Integer MAX_FIRST_NAME = 40;
	private static final Integer MAX_LAST_NAME = 80;
	private static final Integer MAX_EMAIL = 80;
	private static final Integer MAX_PHONE = 40;
	private static final String EMAIL_PATTERN = '^[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}$';

	// Number field limits (exclusive upper bounds derived from precision and scale)
	private static final Decimal LIMIT_KW = 100000000000000L; // precision 16, scale 2
	private static final Decimal LIMIT_DEFAULT = 10000000000000000L; // precision 18, scale 2
	private static final Decimal LIMIT_GROUND_SLOPE = 100; // precision 4, scale 2
	private static final Decimal LIMIT_AZIMUTH = 1000; // precision 5, scale 2

	// Option key (as used by the LWC) -> Lead picklist field
	private static final Map<String, Schema.SObjectField> PICKLIST_FIELDS = new Map<String, Schema.SObjectField>{
		'moduleManufacturer' => Lead.Module_Manufacturer__c,
		'moduleWattage' => Lead.Module_Wattage__c,
		'systemType' => Lead.System_Type__c,
		'systemConfiguration' => Lead.System_Configuration__c,
		'panelTilt' => Lead.Panel_Tilt__c,
		'designPreference' => Lead.DesignPreference__c,
		'ballastBlockSpecification' => Lead.Ballast_Block_Specification__c,
		'codeStandard' => Lead.Code_Standard__c,
		'roofSurface' => Lead.Roof_Surface__c,
		'constructionType' => Lead.Existing_or_new_construction__c,
		'distributorType' => Lead.Distributor_Type__c
	};

	private static final List<String> ALL_TILTS = new List<String>{
		'0°',
		'5°',
		'7°',
		'10°',
		'15°',
		'20°'
	};

	// System Type -> System Configuration -> allowed Panel Tilt values
	private static final Map<String, Map<String, List<String>>> TILT_MATRIX = new Map<String, Map<String, List<String>>>{
		Constants.INTAKE_SYSTEM_TYPE_FLAT_ROOF => new Map<String, List<String>>{
			Constants.INTAKE_CONFIG_FLUSH_MOUNT => new List<String>{ '0°' },
			Constants.INTAKE_CONFIG_SOUTH_FACING => new List<String>{ '5°', '7°', '10°', '15°' },
			Constants.INTAKE_CONFIG_EAST_WEST_FACING => new List<String>{ '7°', '10°' }
		},
		Constants.INTAKE_SYSTEM_TYPE_GROUND_MOUNT => new Map<String, List<String>>{
			Constants.INTAKE_CONFIG_SOUTH_FACING => new List<String>{ '15°', '20°' },
			Constants.INTAKE_CONFIG_EAST_WEST_FACING => new List<String>{ '10°' }
		},
		Constants.INTAKE_SYSTEM_TYPE_PITCHED_ROOF => new Map<String, List<String>>{
			Constants.INTAKE_CONFIG_FLUSH_MOUNT => ALL_TILTS,
			Constants.INTAKE_CONFIG_SOUTH_FACING => ALL_TILTS,
			Constants.INTAKE_CONFIG_EAST_WEST_FACING => ALL_TILTS
		}
	};

	// ---------------------------------------------------------------------------------
	// Options
	// ---------------------------------------------------------------------------------

	/**
	 * Active picklist values for the form, the allowed countries (US, CA, MX) and the
	 * states of each country (decoded from the StateCode dependent picklist).
	 */
	public static ProjectIntakeOptions getFormOptions() {
		ProjectIntakeOptions options = new ProjectIntakeOptions();
		for (String key : PICKLIST_FIELDS.keySet()) {
			options.picklists.put(
				key,
				toOptions(PICKLIST_FIELDS.get(key).getDescribe().getPicklistValues())
			);
		}

		Map<String, Schema.SObjectField> leadFields = Schema.SObjectType.Lead.fields.getMap();
		List<Schema.PicklistEntry> countryEntries = leadFields.get('CountryCode')
			.getDescribe()
			.getPicklistValues();
		List<Schema.PicklistEntry> stateEntries = leadFields.get('StateCode')
			.getDescribe()
			.getPicklistValues();

		// The validFor bitmap of a state is indexed by position in the full controlling list.
		Map<String, Integer> countryIndexByCode = new Map<String, Integer>();
		Map<String, String> countryLabelByCode = new Map<String, String>();
		for (Integer i = 0; i < countryEntries.size(); i++) {
			if (countryEntries[i].isActive()) {
				countryIndexByCode.put(countryEntries[i].getValue(), i);
				countryLabelByCode.put(countryEntries[i].getValue(), countryEntries[i].getLabel());
			}
		}

		List<Schema.PicklistEntry> activeStates = new List<Schema.PicklistEntry>();
		List<String> stateValidFor = new List<String>();
		for (Schema.PicklistEntry state : stateEntries) {
			if (state.isActive()) {
				activeStates.add(state);
				stateValidFor.add(validForOf(state));
			}
		}

		for (String countryCode : Constants.INTAKE_ALLOWED_COUNTRIES) {
			if (!countryIndexByCode.containsKey(countryCode)) {
				continue;
			}
			Integer countryIndex = countryIndexByCode.get(countryCode);
			options.countries.add(
				new ProjectIntakeOptions.Option(countryLabelByCode.get(countryCode), countryCode)
			);
			List<ProjectIntakeOptions.Option> states = new List<ProjectIntakeOptions.Option>();
			for (Integer i = 0; i < activeStates.size(); i++) {
				if (isValidFor(stateValidFor[i], countryIndex)) {
					states.add(
						new ProjectIntakeOptions.Option(
							activeStates[i].getLabel(),
							activeStates[i].getValue()
						)
					);
				}
			}
			options.statesByCountry.put(countryCode, states);
		}
		return options;
	}

	private static List<ProjectIntakeOptions.Option> toOptions(List<Schema.PicklistEntry> entries) {
		List<ProjectIntakeOptions.Option> options = new List<ProjectIntakeOptions.Option>();
		for (Schema.PicklistEntry entry : entries) {
			if (entry.isActive()) {
				options.add(new ProjectIntakeOptions.Option(entry.getLabel(), entry.getValue()));
			}
		}
		return options;
	}

	/** The base64 validFor bitmap is only exposed through the serialized form of a PicklistEntry. */
	private static String validForOf(Schema.PicklistEntry entry) {
		Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(
			JSON.serialize(entry)
		);
		return (String) raw.get('validFor');
	}

	/**
	 * Tests one bit of a dependent picklist validFor bitmap.
	 * Bit 0 is the most significant bit of the first byte.
	 *
	 * @param validForBase64 the base64 encoded bitmap of the dependent value
	 * @param controllingIndex position of the controlling value in the full controlling list
	 */
	@TestVisible
	private static Boolean isValidFor(String validForBase64, Integer controllingIndex) {
		if (String.isBlank(validForBase64) || controllingIndex == null || controllingIndex < 0) {
			return false;
		}
		String hex = EncodingUtil.convertToHex(EncodingUtil.base64Decode(validForBase64));
		Integer bitInByte = Math.mod(controllingIndex, 8);
		Integer byteIndex = (controllingIndex - bitInByte) / 8;
		if (byteIndex * 2 + 2 > hex.length()) {
			return false;
		}
		Integer byteValue =
			HEX_DIGITS.indexOf(hex.substring(byteIndex * 2, byteIndex * 2 + 1)) * 16 +
			HEX_DIGITS.indexOf(hex.substring(byteIndex * 2 + 1, byteIndex * 2 + 2));
		Integer mask = 128 >> bitInByte;
		return (byteValue & mask) != 0;
	}

	// ---------------------------------------------------------------------------------
	// Submit
	// ---------------------------------------------------------------------------------

	/**
	 * Validates the submission and creates the Lead with its files. Everything happens in
	 * one transaction: if the files cannot be attached the Lead is rolled back.
	 *
	 * @param requestJson JSON of ProjectIntakeRequest
	 * @throws IntakeValidationException with a user-facing message
	 */
	public static void submitIntake(String requestJson) {
		ProjectIntakeRequest request = parseRequest(requestJson);
		normalize(request);

		List<String> errors = validate(request, getFormOptions());
		if (!errors.isEmpty()) {
			if (errors.size() > MAX_REPORTED_ERRORS) {
				errors = errors.subList(0, MAX_REPORTED_ERRORS);
			}
			throw new IntakeValidationException(String.join(errors, ' '));
		}
		// Fail before touching the database when the file references are unusable.
		ProjectIntakeFileService.validateFileRefs(request.uploadToken, request.files);

		Lead lead = buildLead(request);
		Savepoint sp = Database.setSavepoint();
		try {
			insertLead(lead);
			ProjectIntakeFileService.attachFilesToLead(
				lead.Id,
				request.uploadToken,
				request.files
			);
		} catch (Exception e) {
			Database.rollback(sp);
			throw e;
		}
	}

	private static ProjectIntakeRequest parseRequest(String requestJson) {
		if (String.isBlank(requestJson) || requestJson.length() > Constants.INTAKE_MAX_REQUEST_LENGTH) {
			throw new IntakeValidationException(Constants.INTAKE_ERR_INVALID_SUBMISSION);
		}
		ProjectIntakeRequest request;
		try {
			request = (ProjectIntakeRequest) JSON.deserializeStrict(
				requestJson,
				ProjectIntakeRequest.class
			);
		} catch (Exception e) {
			// JSONException / TypeException: unknown keys, wrong types, malformed JSON
			throw new IntakeValidationException(Constants.INTAKE_ERR_INVALID_SUBMISSION);
		}
		if (request == null) {
			throw new IntakeValidationException(Constants.INTAKE_ERR_INVALID_SUBMISSION);
		}
		return request;
	}

	private static void insertLead(Lead lead) {
		try {
			Database.insert(lead, AccessLevel.USER_MODE);
		} catch (DmlException e) {
			// Validation rule messages (for example the install date rule) are written for users.
			if (e.getDmlType(0) == StatusCode.FIELD_CUSTOM_VALIDATION_EXCEPTION) {
				throw new IntakeValidationException(e.getDmlMessage(0));
			}
			throw e;
		}
	}

	// ---------------------------------------------------------------------------------
	// Normalization and validation
	// ---------------------------------------------------------------------------------

	private static String clean(String value) {
		return String.isBlank(value) ? null : value.trim();
	}

	private static Decimal round2(Decimal value) {
		return value == null ? null : value.setScale(2, RoundingMode.HALF_UP);
	}

	/** Trims strings (blank becomes null) and rounds numbers to the 2 decimals the fields store. */
	private static void normalize(ProjectIntakeRequest r) {
		r.projectName = clean(r.projectName);
		r.countryCode = clean(r.countryCode);
		r.street = clean(r.street);
		r.city = clean(r.city);
		r.stateCode = clean(r.stateCode);
		r.postalCode = clean(r.postalCode);
		r.projectNotes = clean(r.projectNotes);
		r.moduleManufacturer = clean(r.moduleManufacturer);
		r.moduleWattage = clean(r.moduleWattage);
		r.moduleModelNumber = clean(r.moduleModelNumber);
		r.systemType = clean(r.systemType);
		r.systemConfiguration = clean(r.systemConfiguration);
		r.panelTilt = clean(r.panelTilt);
		r.designPreference = clean(r.designPreference);
		r.ballastBlockSpecification = clean(r.ballastBlockSpecification);
		r.codeStandard = clean(r.codeStandard);
		r.roofSurface = clean(r.roofSurface);
		r.constructionType = clean(r.constructionType);
		r.company = clean(r.company);
		r.firstName = clean(r.firstName);
		r.lastName = clean(r.lastName);
		r.email = clean(r.email);
		r.phone = clean(r.phone);
		r.distributorType = clean(r.distributorType);
		r.knownDisty = clean(r.knownDisty);
		r.uploadToken = clean(r.uploadToken);

		r.projectWattageKw = round2(r.projectWattageKw);
		r.buildingHeightFt = round2(r.buildingHeightFt);
		r.setbackDistanceFt = round2(r.setbackDistanceFt);
		r.roofPitch = round2(r.roofPitch);
		r.parapetHeightIn = round2(r.parapetHeightIn);
		r.parapetWidthIn = round2(r.parapetWidthIn);
		r.structuralLoadLimitPsf = round2(r.structuralLoadLimitPsf);
		r.pointLoadLimitPsf = round2(r.pointLoadLimitPsf);
		r.maxSystemWeightLbs = round2(r.maxSystemWeightLbs);
		r.groundSlope = round2(r.groundSlope);
		r.arrayAzimuth = round2(r.arrayAzimuth);
	}

	private static Set<String> valuesOf(List<ProjectIntakeOptions.Option> options) {
		Set<String> values = new Set<String>();
		if (options != null) {
			for (ProjectIntakeOptions.Option option : options) {
				values.add(option.value);
			}
		}
		return values;
	}

	private static List<String> validate(ProjectIntakeRequest r, ProjectIntakeOptions options) {
		List<String> errors = new List<String>();
		Boolean isGround = r.systemType == Constants.INTAKE_SYSTEM_TYPE_GROUND_MOUNT;

		// Project
		checkText(errors, 'Project Name', r.projectName, MAX_PROJECT_NAME, true);
		checkText(errors, 'Street', r.street, MAX_STREET, true);
		checkText(errors, 'City', r.city, MAX_CITY, true);
		checkText(errors, 'Postal Code', r.postalCode, MAX_POSTAL_CODE, true);
		checkText(errors, 'Project Notes', r.projectNotes, MAX_NOTES, false);
		Set<String> countries = valuesOf(options.countries);
		if (r.countryCode == null || !countries.contains(r.countryCode)) {
			errors.add('Country is required.');
		} else if (
			r.stateCode == null ||
			!valuesOf(options.statesByCountry.get(r.countryCode)).contains(r.stateCode)
		) {
			errors.add('State / Province is required and must belong to the selected country.');
		}
		if (r.plannedInstallDate == null) {
			errors.add('Planned Install Date is required.');
		} else if (r.plannedInstallDate < Date.today()) {
			errors.add(Constants.INTAKE_ERR_PAST_DATE);
		}

		// Module
		checkNumber(errors, 'Project Size (kW)', r.projectWattageKw, true, 0, false, LIMIT_KW);
		checkPicklist(errors, 'Module Manufacturer', r.moduleManufacturer, options, 'moduleManufacturer', false);
		checkPicklist(errors, 'Module Wattage', r.moduleWattage, options, 'moduleWattage', true);
		checkText(errors, 'Module Model Number', r.moduleModelNumber, MAX_MODEL_NUMBER, true);

		// System
		checkPicklist(errors, 'System Type', r.systemType, options, 'systemType', true);
		checkPicklist(errors, 'System Configuration', r.systemConfiguration, options, 'systemConfiguration', false);
		checkPicklist(errors, 'Panel Tilt', r.panelTilt, options, 'panelTilt', false);
		checkPicklist(errors, 'Design Preference', r.designPreference, options, 'designPreference', false);
		checkSystemCombination(errors, r);
		if (
			r.designPreference == Constants.INTAKE_DESIGN_PREFERENCE_BALLASTED ||
			r.designPreference == Constants.INTAKE_DESIGN_PREFERENCE_HYBRID
		) {
			checkPicklist(errors, 'Ballast Block Specification', r.ballastBlockSpecification, options, 'ballastBlockSpecification', true);
		}

		// Site
		checkPicklist(errors, 'ASCE Code', r.codeStandard, options, 'codeStandard', false);
		checkPicklist(errors, 'Construction', r.constructionType, options, 'constructionType', false);
		if (r.systemType != null && !isGround) {
			checkPicklist(errors, 'Roof Surface', r.roofSurface, options, 'roofSurface', false);
			checkNumber(errors, 'Building Height', r.buildingHeightFt, true, 0, false, LIMIT_DEFAULT);
			checkNumber(errors, 'Roof Pitch', r.roofPitch, true, 0, true, LIMIT_DEFAULT);
			checkNumber(errors, 'Setback Distance', r.setbackDistanceFt, false, 0, false, LIMIT_DEFAULT);
			checkNumber(errors, 'Parapet Height', r.parapetHeightIn, false, 0, false, LIMIT_DEFAULT);
			checkNumber(errors, 'Parapet Width', r.parapetWidthIn, false, 0, false, LIMIT_DEFAULT);
			checkNumber(errors, 'Structural Load Limit', r.structuralLoadLimitPsf, false, 0, false, LIMIT_DEFAULT);
			checkNumber(errors, 'Point Load Limit', r.pointLoadLimitPsf, false, 0, false, LIMIT_DEFAULT);
			checkNumber(errors, 'Maximum System Weight', r.maxSystemWeightLbs, false, 0, false, LIMIT_DEFAULT);
		}
		if (isGround) {
			checkNumber(errors, 'Ground Slope', r.groundSlope, false, 0, false, LIMIT_GROUND_SLOPE);
			checkNumber(errors, 'Array Azimuth', r.arrayAzimuth, false, 0, false, LIMIT_AZIMUTH);
		}

		// Contact
		checkText(errors, 'Company', r.company, MAX_COMPANY, true);
		checkText(errors, 'First Name', r.firstName, MAX_FIRST_NAME, true);
		checkText(errors, 'Last Name', r.lastName, MAX_LAST_NAME, true);
		checkText(errors, 'Email', r.email, MAX_EMAIL, true);
		if (r.email != null && !Pattern.matches(EMAIL_PATTERN, r.email)) {
			errors.add('Email is not a valid email address.');
		}
		checkText(errors, 'Phone', r.phone, MAX_PHONE, true);
		checkPicklist(errors, 'Purchasing', r.distributorType, options, 'distributorType', false);
		if (r.distributorType == Constants.INTAKE_DISTRIBUTOR_INDIRECT) {
			checkText(errors, 'Distribution Partner', r.knownDisty, MAX_KNOWN_DISTY, true);
		}
		if (r.legalConsent != true) {
			errors.add('You must accept the terms to submit.');
		}
		return errors;
	}

	/**
	 * Server-side copy of the dependency matrix (System Type -> Configuration -> Tilt)
	 * plus the locked values of a flat roof flush mount.
	 */
	private static void checkSystemCombination(List<String> errors, ProjectIntakeRequest r) {
		if (!TILT_MATRIX.containsKey(r.systemType)) {
			return; // missing / unknown system type is reported by the picklist check
		}
		Map<String, List<String>> tiltsByConfiguration = TILT_MATRIX.get(r.systemType);
		List<String> allowedTilts = new List<String>();
		if (r.systemConfiguration == null) {
			for (List<String> tilts : tiltsByConfiguration.values()) {
				allowedTilts.addAll(tilts);
			}
		} else if (tiltsByConfiguration.containsKey(r.systemConfiguration)) {
			allowedTilts = tiltsByConfiguration.get(r.systemConfiguration);
			// A single possible tilt is locked in the form, so fill it in when it was not sent.
			if (r.panelTilt == null && allowedTilts.size() == 1) {
				r.panelTilt = allowedTilts[0];
			}
		} else {
			errors.add('System Configuration is not available for the selected System Type.');
			return;
		}
		if (r.panelTilt != null && !allowedTilts.contains(r.panelTilt)) {
			errors.add('Panel Tilt is not available for the selected System Configuration.');
		}
		if (
			r.systemType == Constants.INTAKE_SYSTEM_TYPE_FLAT_ROOF &&
			r.systemConfiguration == Constants.INTAKE_CONFIG_FLUSH_MOUNT
		) {
			if (r.designPreference == null) {
				r.designPreference = Constants.INTAKE_DESIGN_PREFERENCE_ATTACHED;
			} else if (r.designPreference != Constants.INTAKE_DESIGN_PREFERENCE_ATTACHED) {
				errors.add('A Flush Mount flat roof system requires an Attached design.');
			}
		}
	}

	private static void checkText(
		List<String> errors,
		String label,
		String value,
		Integer maxLength,
		Boolean required
	) {
		if (value == null) {
			if (required) {
				errors.add(label + ' is required.');
			}
		} else if (value.length() > maxLength) {
			errors.add(label + ' must be at most ' + maxLength + ' characters.');
		}
	}

	private static void checkPicklist(
		List<String> errors,
		String label,
		String value,
		ProjectIntakeOptions options,
		String optionsKey,
		Boolean required
	) {
		if (value == null) {
			if (required) {
				errors.add(label + ' is required.');
			}
		} else if (!valuesOf(options.picklists.get(optionsKey)).contains(value)) {
			errors.add(label + ' has an invalid value.');
		}
	}

	private static void checkNumber(
		List<String> errors,
		String label,
		Decimal value,
		Boolean required,
		Decimal minimum,
		Boolean minimumAllowed,
		Decimal upperLimit
	) {
		if (value == null) {
			if (required) {
				errors.add(label + ' is required.');
			}
		} else if (value < minimum || (value == minimum && !minimumAllowed)) {
			errors.add(
				label +
					(minimumAllowed ? ' cannot be negative.' : ' must be greater than 0 (leave blank if not applicable).')
			);
		} else if (value >= upperLimit) {
			errors.add(label + ' is too large.');
		}
	}

	// ---------------------------------------------------------------------------------
	// Mapping
	// ---------------------------------------------------------------------------------

	/**
	 * Maps a validated request to a Lead. Fields hidden by the form rules are ignored even
	 * when sent. OwnerId is deliberately not set: the site's default owner for
	 * guest-created records applies.
	 */
	private static Lead buildLead(ProjectIntakeRequest r) {
		Boolean isGround = r.systemType == Constants.INTAKE_SYSTEM_TYPE_GROUND_MOUNT;
		Boolean isFlat = r.systemType == Constants.INTAKE_SYSTEM_TYPE_FLAT_ROOF;
		Boolean showsBuilding = !isGround;
		Boolean showsBallast =
			r.designPreference == Constants.INTAKE_DESIGN_PREFERENCE_BALLASTED ||
			r.designPreference == Constants.INTAKE_DESIGN_PREFERENCE_HYBRID;
		Boolean isIndirect = r.distributorType == Constants.INTAKE_DISTRIBUTOR_INDIRECT;

		return new Lead(
			LeadSource = Constants.INTAKE_LEAD_SOURCE,
			Status = Constants.INTAKE_LEAD_STATUS,
			ProjectName__c = r.projectName,
			CountryCode = r.countryCode,
			Street = r.street,
			City = r.city,
			StateCode = r.stateCode,
			PostalCode = r.postalCode,
			Project_Notes__c = r.projectNotes,
			Planned_Install_Date__c = r.plannedInstallDate,
			Project_Wattage_kW__c = r.projectWattageKw,
			Module_Manufacturer__c = r.moduleManufacturer,
			Module_Wattage__c = r.moduleWattage,
			Module_Model_Number__c = r.moduleModelNumber,
			System_Type__c = r.systemType,
			System_Configuration__c = r.systemConfiguration,
			Panel_Tilt__c = r.panelTilt,
			UL_3741_compliance__c = isFlat && r.ul3741Compliance == true,
			DesignPreference__c = r.designPreference,
			Ballast_Block_Specification__c = showsBallast ? r.ballastBlockSpecification : null,
			Code_Standard__c = r.codeStandard,
			Existing_or_new_construction__c = r.constructionType,
			Roof_Surface__c = showsBuilding ? r.roofSurface : null,
			Building_Height_ft__c = showsBuilding ? r.buildingHeightFt : null,
			Setback_Distance_ft__c = showsBuilding ? r.setbackDistanceFt : null,
			Roof_Pitch__c = showsBuilding ? r.roofPitch : null,
			Parapet_Height_in__c = showsBuilding ? r.parapetHeightIn : null,
			Parapet_Width_in__c = showsBuilding ? r.parapetWidthIn : null,
			Structural_Load_Limit_psf__c = showsBuilding ? r.structuralLoadLimitPsf : null,
			Point_Load_Limit_psf__c = showsBuilding ? r.pointLoadLimitPsf : null,
			Maximum_System_Weight_Limit_lbs__c = showsBuilding ? r.maxSystemWeightLbs : null,
			Ground_Slope__c = isGround ? r.groundSlope : null,
			Array_Azimuth__c = isGround ? r.arrayAzimuth : null,
			Landfill_Location__c = isGround && r.landfillLocation == true,
			Company = r.company,
			FirstName = r.firstName,
			LastName = r.lastName,
			Email = r.email,
			Phone = r.phone,
			Distributor_Type__c = r.distributorType,
			Known_Disty__c = isIndirect ? r.knownDisty : null,
			LegalConsent__c = true
		);
	}

	// ---------------------------------------------------------------------------------
	// Logging
	// ---------------------------------------------------------------------------------

	/**
	 * Logs through BoltErrorLogger without ever throwing: logging (a DML) can itself fail
	 * in the guest context or inside a cacheable call and must not mask the original error.
	 */
	public static void logSafely(
		String className,
		String methodName,
		String message,
		String stackTrace
	) {
		try {
			BoltErrorLogger.logError(
				className,
				methodName,
				message,
				stackTrace,
				Constants.SOURCE_TYPE_APEX,
				Constants.SEVERITY_ERROR,
				UserInfo.getUserId(),
				null
			);
		} catch (Exception loggingError) {
			System.debug(
				LoggingLevel.WARN,
				CLASS_NAME + ': could not log "' + message + '": ' + loggingError.getMessage()
			);
		}
	}
}
