/**
 * Shared test data builders for the Project Intake tests.
 */
@IsTest
public class ProjectIntakeTestData {
	public static ContentVersion createFile(String tokenValue, String fileName, Integer sizeChars) {
		ContentVersion version = new ContentVersion(
			Title = fileName.substringBeforeLast('.'),
			PathOnClient = fileName,
			VersionData = Blob.valueOf('x'.repeat(sizeChars)),
			IsMajorVersion = true,
			Intake_Token_fileupload__c = tokenValue
		);
		insert version;
		return [
			SELECT Id, ContentDocumentId, Title, FileExtension, ContentSize, Intake_Token_fileupload__c
			FROM ContentVersion
			WHERE Id = :version.Id
		];
	}

	public static ContentVersion createLayout(String token) {
		return createFile(token + '|LAYOUT', 'layout.pdf', 10);
	}

	public static ContentVersion createSpec(String token) {
		return createFile(token + '|SPEC', 'spec.pdf', 10);
	}

	public static String firstOptionValue(String picklistKey) {
		return ProjectIntakeService.getFormOptions().picklists.get(picklistKey)[0].value;
	}

	/** A valid Pitched Roof submission referencing the two given files. */
	public static Map<String, Object> validRequest(
		String token,
		ContentVersion layout,
		ContentVersion spec
	) {
		return new Map<String, Object>{
			'projectName' => 'Test Project',
			'countryCode' => 'US',
			'street' => '145 Pegasus Way',
			'city' => 'Phoenix',
			'stateCode' => 'AZ',
			'postalCode' => '85001',
			'projectNotes' => 'Some notes',
			'plannedInstallDate' => String.valueOf(Date.today().addDays(30)),
			'projectWattageKw' => 120.5,
			'moduleWattage' => firstOptionValue('moduleWattage'),
			'moduleModelNumber' => 'MNU-10XS',
			'systemType' => 'Pitched Roof',
			'systemConfiguration' => 'South Facing',
			'panelTilt' => '10°',
			'ul3741Compliance' => true,
			'designPreference' => Constants.INTAKE_DESIGN_PREFERENCE_ATTACHED,
			'buildingHeightFt' => 20,
			'roofPitch' => 5,
			'setbackDistanceFt' => 3,
			'groundSlope' => 4,
			'company' => 'Intake Test Co',
			'firstName' => 'Jane',
			'lastName' => 'Doe',
			'email' => 'jane.doe@example.com',
			'phone' => '(555) 555-5555',
			'distributorType' => 'Indirect',
			'knownDisty' => 'Acme Distribution',
			'legalConsent' => true,
			'uploadToken' => token,
			'files' => new List<Object>{
				new Map<String, Object>{
					'contentVersionId' => layout.Id,
					'category' => 'LAYOUT'
				},
				new Map<String, Object>{ 'contentVersionId' => spec.Id, 'category' => 'SPEC' }
			}
		};
	}
}
