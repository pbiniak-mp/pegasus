/**
 * Builds a Quote that has every value the QuotePDF page prints, so tests can
 * start from "complete" and blank one field at a time.
 *
 * Picklist values are read from the describe rather than hardcoded - the sets
 * behind Module Manufacturer, Module Wattage, System Type and Panel Tilt are
 * global value sets that change with the catalog.
 */
@IsTest
public class QuotePDFTestDataFactory {

	public static final String ACRONYM = 'PCS';
	public static final String ACCOUNT_NAME = 'PDF Test Account';
	public static final String REV_00 = '00';
	// Resolved to 'HI' by StateCodeService, which feeds the SS project code segment.
	public static final String PROJECT_STATE = 'Hawaii';

	/**
	 * Inserts Account, Contact, Opportunity, Design Revision, Quote and one
	 * Quote Line Item, all fully populated.
	 *
	 * @return the inserted Quote
	 */
	public static Quote createCompleteQuote() {
		// The outbound integration is irrelevant here; keep it off so the DML in
		// these tests never queues a callout.
		GlideAnalyticsIntegrationService.configOverride = new Outbound_Integration__mdt(Active__c = false);

		Account acc = new Account(Name = ACCOUNT_NAME, Naming_Acronym__c = ACRONYM);
		insert acc;

		Contact con = new Contact(FirstName = 'John', LastName = 'Doe', AccountId = acc.Id);
		insert con;

		Opportunity opp = buildOpportunity(acc.Id, 'PDF Test Opportunity');
		insert opp;

		Design_Revision__c revision = new Design_Revision__c(
			Opportunity__c = opp.Id,
			Revision_Number__c = REV_00,
			Planned_Install_Date__c = Date.today().addDays(60),
			// Module_Quantity_F__c is a formula over Module_Wattage__c and Project_Wattage_kW__c
			Project_Wattage_kW__c = 449.6,
			Total_Attachments__c = 240,
			Module_Manufacturer__c = firstPicklistValue(Design_Revision__c.Module_Manufacturer__c),
			Module_Model_Number__c = 'MOD-400-X',
			Module_Wattage__c = firstPicklistValue(Design_Revision__c.Module_Wattage__c),
			System_Type__c = firstPicklistValue(Design_Revision__c.System_Type__c),
			Panel_Tilt__c = firstPicklistValue(Design_Revision__c.Panel_Tilt__c)
		);
		insert revision;

		Id pricebookId = Test.getStandardPricebookId();

		Product2 product = new Product2(Name = 'Test Product', ProductCode = 'TEST-001', IsActive = true);
		insert product;

		PricebookEntry pbe = new PricebookEntry(
			Pricebook2Id = pricebookId,
			Product2Id = product.Id,
			UnitPrice = 100.00,
			IsActive = true
		);
		insert pbe;

		// Hierarchy setting: a second org-default insert would fail, and a test
		// class may well have created one in its own @TestSetup already.
		if ([SELECT COUNT() FROM Quote_Sequence__c] == 0) {
			insert new Quote_Sequence__c(
				SetupOwnerId = UserInfo.getOrganizationId(),
				Last_Number__c = 26099
			);
		}

		Quote quote = new Quote(
			Name = 'PDF Test Quote',
			OpportunityId = opp.Id,
			Pricebook2Id = pricebookId,
			ContactId = con.Id,
			Design_Revision__c = revision.Id,
			Quote_Type__c = Constants.QUOTE_TYPE_MATERIAL,
			ExpirationDate = Date.today().addDays(30),
			BillingStreet = '123 Main St',
			BillingCity = 'Richmond',
			BillingState = 'California',
			BillingPostalCode = '94804',
			BillingCountry = 'United States'
		);
		insert quote;

		insert new QuoteLineItem(
			QuoteId = quote.Id,
			Product2Id = product.Id,
			PricebookEntryId = pbe.Id,
			Quantity = 2,
			UnitPrice = 100.00
		);

		return quote;
	}

	public static Opportunity buildOpportunity(Id accountId, String name) {
		return new Opportunity(
			Name = name,
			AccountId = accountId,
			StageName = 'Qualification',
			CloseDate = Date.today().addDays(30),
			Product_Line__c = 'Flat FX',
			ProjectName__c = 'Hilton Tower',
			Project_State__c = PROJECT_STATE,
			Project_Wattage_kW__c = 449.6,
			Active_Revision_Number__c = REV_00
		);
	}

	/**
	 * Reported entries are "PDF caption -> Record: Field", so tests match on the
	 * caption rather than reconstructing the whole string.
	 *
	 * @param missing the entries returned by QuotePDFValidationService
	 * @param pdfLabel the PDF caption to look for
	 */
	public static Boolean mentions(List<String> missing, String pdfLabel) {
		if (missing == null) return false;
		for (String entry : missing) {
			if (entry.startsWith(pdfLabel + QuotePDFValidationService.SOURCE_SEPARATOR)) return true;
		}
		return false;
	}

	private static String firstPicklistValue(Schema.SObjectField field) {
		List<Schema.PicklistEntry> entries = field.getDescribe().getPicklistValues();
		for (Schema.PicklistEntry entry : entries) {
			if (entry.isActive()) return entry.getValue();
		}
		return null;
	}
}
