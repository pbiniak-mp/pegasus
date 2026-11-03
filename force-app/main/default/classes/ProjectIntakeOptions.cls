/**
 * Picklist data returned to the Project Intake form (guest, no record access).
 */
public class ProjectIntakeOptions {
	@AuraEnabled
	public Map<String, List<Option>> picklists = new Map<String, List<Option>>();
	@AuraEnabled
	public List<Option> countries = new List<Option>();
	@AuraEnabled
	public Map<String, List<Option>> statesByCountry = new Map<String, List<Option>>();

	/** A single combobox option. */
	public class Option {
		@AuraEnabled
		public String label;
		@AuraEnabled
		public String value;

		public Option(String label, String value) {
			this.label = label;
			this.value = value;
		}
	}
}
