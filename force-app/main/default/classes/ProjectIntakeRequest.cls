/**
 * Deserialization target for the public Project Intake form submission.
 * Property names match the JSON keys sent by the projectIntakeForm LWC exactly.
 * Parsed with JSON.deserializeStrict, so an unknown key rejects the submission.
 */
public class ProjectIntakeRequest {
	public String projectName;
	public String countryCode;
	public String street;
	public String city;
	public String stateCode;
	public String postalCode;
	public String projectNotes;
	public Date plannedInstallDate;
	public Decimal projectWattageKw;
	public String moduleManufacturer;
	public String moduleWattage;
	public String moduleModelNumber;

	public String systemType;
	public String systemConfiguration;
	public String panelTilt;
	public Boolean ul3741Compliance;
	public String designPreference;
	public String ballastBlockSpecification;

	public String codeStandard;
	public String roofSurface;
	public Decimal buildingHeightFt;
	public Decimal setbackDistanceFt;
	public Decimal roofPitch;
	public Decimal parapetHeightIn;
	public Decimal parapetWidthIn;
	public Decimal structuralLoadLimitPsf;
	public Decimal pointLoadLimitPsf;
	public Decimal maxSystemWeightLbs;
	public String constructionType;
	public Decimal groundSlope;
	public Decimal arrayAzimuth;
	public Boolean landfillLocation;

	public String company;
	public String firstName;
	public String lastName;
	public String email;
	public String phone;
	public String distributorType;
	public String knownDisty;
	public Boolean legalConsent;

	public String uploadToken;
	public List<FileRef> files;

	/** Reference to a file uploaded before the Lead existed. */
	public class FileRef {
		public Id contentVersionId;
		public String category;
	}
}
