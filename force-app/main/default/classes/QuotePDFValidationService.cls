/**
 * Guards the Quote PDF against going out to a client with blanks on it.
 *
 * Every check maps 1:1 to a value printed on the QuotePDF page. A reported
 * entry names three things, because the PDF caption alone does not tell anyone
 * where to go and fix it:
 *
 *     Total Attachments  ->  Design Revision REV-01: Total Attachments
 *     ^ caption on the PDF   ^ record to open        ^ field label on it
 *
 * The values come from the following records:
 *   - Quote            - quote number, Bill To address, expiration date
 *   - Opportunity      - project name and recipient company via Account / Distributor
 *   - Design Revision  - the whole Summary / Equipments Type block
 *   - Contact          - contact name (via Quote.ContactId)
 *   - Quote Line Items - the Racking Components table
 *
 * Freight and Tax are deliberately not required: the PDF prints "TBD" for
 * freight by design.
 *
 * Keep this in sync with QuotePDF.page whenever a field is added or removed
 * from the layout.
 */
public inherited sharing class QuotePDFValidationService {

	public class IncompleteQuoteException extends Exception {}

	public static final String MSG_QUOTE_NOT_FOUND = 'Quote not found.';
	public static final String MSG_PREFIX = 'The PDF cannot be generated. Fill in the following: ';
	public static final String MSG_SEPARATOR = '; ';

	// "PDF caption" + SOURCE_SEPARATOR + "Record: Field label"
	public static final String SOURCE_SEPARATOR = ' -> ';

	// --- PDF captions (left column = what the client reads on paper) ---------

	// Project Information
	public static final String LABEL_PROJECT_NAME = 'Project Name';
	public static final String LABEL_QUOTE_NUMBER = 'Quote #';
	public static final String LABEL_REV_NUMBER = 'REV Number';
	public static final String LABEL_COMPANY_NAME = 'Company Name';
	public static final String LABEL_CONTACT_NAME = 'Contact Name';
	public static final String LABEL_PROJECT_STREET = 'Project Street';
	public static final String LABEL_CITY = 'City';
	public static final String LABEL_STATE = 'State';
	public static final String LABEL_ZIP_CODE = 'Zip code';
	public static final String LABEL_VALID_TO = 'Valid To';
	public static final String LABEL_PLANNED_INSTALL_DATE = 'Planned install Date';

	// Summary
	public static final String LABEL_TOTAL_MODULES = 'Total Modules';
	public static final String LABEL_PROJECT_SIZE = 'Project Size';
	public static final String LABEL_TOTAL_ATTACHMENTS = 'Total Attachments';

	// Equipments Type
	public static final String LABEL_MODULE_MANUFACTURER = 'Module Manufacturer';
	public static final String LABEL_MODULE_NUMBER = 'Module Number';
	public static final String LABEL_MODULE_WATTS = 'Module Watts';
	public static final String LABEL_SYSTEM = 'System';
	public static final String LABEL_TILT = 'Tilt';

	// Racking Components
	public static final String LABEL_DESIGN_REVISION = 'Whole right-hand column and REV number';
	public static final String LABEL_LINE_ITEMS = 'Racking Components table';
	public static final String LABEL_LINE_ITEM_QUANTITY = 'Racking Components - QTY';
	public static final String LABEL_LINE_ITEM_PRICE = 'Racking Components - Price';
	public static final String LABEL_UNNAMED_PRODUCT = '(unnamed product)';

	// --- Where to fix it (right column = record + field label in the UI) -----

	public static final String RECORD_QUOTE = 'Quote';
	public static final String RECORD_OPPORTUNITY = 'Opportunity';
	public static final String RECORD_DESIGN_REVISION = 'Design Revision';
	public static final String RECORD_CONTACT = 'Contact';
	public static final String RECORD_SEPARATOR = ': ';

	public static final String FIELD_OPPORTUNITY_NAME = 'Opportunity Name';
	public static final String FIELD_ACCOUNT_NAME = 'Account Name';
	public static final String FIELD_DISTRIBUTOR = 'Distributor';
	public static final String FIELD_DISTRIBUTOR_TYPE = 'Distributor Type (select Direct or Indirect)';
	public static final String FIELD_QUOTE_NUMBER = 'Quote Number (auto-generated on save)';
	public static final String FIELD_REVISION_NUMBER = 'Revision Number';
	public static final String FIELD_CONTACT = 'Contact (the Contact lookup on the Quote)';
	public static final String FIELD_BILL_TO_STREET = 'Bill To Address - Street';
	public static final String FIELD_BILL_TO_CITY = 'Bill To Address - City';
	public static final String FIELD_BILL_TO_STATE = 'Bill To Address - State/Province';
	public static final String FIELD_BILL_TO_ZIP = 'Bill To Address - Zip/Postal Code';
	public static final String FIELD_EXPIRATION_DATE = 'Expiration Date';
	public static final String FIELD_PLANNED_INSTALL_DATE = 'Planned Install Date';
	public static final String FIELD_MODULE_QUANTITY = 'Module Quantity (calculated from Module Wattage and Project Wattage kW)';
	public static final String FIELD_PROJECT_WATTAGE = 'Project Wattage (kW)';
	public static final String FIELD_TOTAL_ATTACHMENTS = 'Total Attachments';
	public static final String FIELD_MODULE_MANUFACTURER = 'Module Manufacturer';
	public static final String FIELD_MODULE_MODEL_NUMBER = 'Module Model Number';
	public static final String FIELD_MODULE_WATTAGE = 'Module Wattage';
	public static final String FIELD_SYSTEM_TYPE = 'System Type';
	public static final String FIELD_PANEL_TILT = 'Panel Tilt';
	public static final String FIELD_DESIGN_REVISION_LOOKUP = 'Design Revision (the lookup on the Quote is empty)';
	public static final String FIELD_ADD_LINE_ITEMS = 'add at least one Quote Line Item';
	public static final String FIELD_LINE_ITEM_QUANTITY = 'Quantity on line item ';
	public static final String FIELD_LINE_ITEM_PRICE = 'Sales Price on line item ';

	private static final String ZERO_QUANTITY = '0';
	private static final String REV_PREFIX = ' REV-';

	/**
	 * @param quoteId the Quote about to be rendered
	 * @return one entry per empty PDF value, each naming the record and field to
	 *         fix; empty list when the Quote is complete
	 */
	public static List<String> getMissingFields(Id quoteId) {
		if (quoteId == null) return new List<String>{ MSG_QUOTE_NOT_FOUND };

		Quote quote = QuoteSelector.getQuoteById(quoteId);
		if (quote == null) return new List<String>{ MSG_QUOTE_NOT_FOUND };

		return getMissingFields(
			quote,
			ContactSelector.getContactById(quote.ContactId),
			QuoteLineItemSelector.getLineItemsByQuoteId(quoteId)
		);
	}

	public static List<String> getMissingFields(
		Quote quote,
		Contact contact,
		List<QuoteLineItem> lineItems
	) {
		List<String> missing = new List<String>();
		if (quote == null) {
			missing.add(MSG_QUOTE_NOT_FOUND);
			return missing;
		}

		// --- Project Information ---
		// Opportunity, reached through Quote.OpportunityId
		addIfBlank(missing, LABEL_PROJECT_NAME, RECORD_OPPORTUNITY, FIELD_OPPORTUNITY_NAME, quote.Opportunity?.Name);
		addCompanyIssue(missing, quote.Opportunity);
		// Contact, reached through Quote.ContactId
		addIfBlank(missing, LABEL_CONTACT_NAME, RECORD_CONTACT, FIELD_CONTACT, contact?.Name);
		// The Quote record itself - Bill To address block, not Quote To
		addIfBlank(missing, LABEL_QUOTE_NUMBER, RECORD_QUOTE, FIELD_QUOTE_NUMBER, quote.Quote_Number__c);
		addIfBlank(missing, LABEL_PROJECT_STREET, RECORD_QUOTE, FIELD_BILL_TO_STREET, quote.BillingStreet);
		addIfBlank(missing, LABEL_CITY, RECORD_QUOTE, FIELD_BILL_TO_CITY, quote.BillingCity);
		addIfBlank(missing, LABEL_STATE, RECORD_QUOTE, FIELD_BILL_TO_STATE, quote.BillingState);
		addIfBlank(missing, LABEL_ZIP_CODE, RECORD_QUOTE, FIELD_BILL_TO_ZIP, quote.BillingPostalCode);
		addIfNull(missing, LABEL_VALID_TO, RECORD_QUOTE, FIELD_EXPIRATION_DATE, quote.ExpirationDate);

		// --- Everything below lives on the Design Revision ---
		// Without it the whole right-hand column of the PDF renders blank, so
		// report the lookup once instead of a dozen orphaned field names.
		if (quote.Design_Revision__c == null || quote.Design_Revision__r == null) {
			missing.add(describe(LABEL_DESIGN_REVISION, RECORD_QUOTE, FIELD_DESIGN_REVISION_LOOKUP));
		} else {
			Design_Revision__c revision = quote.Design_Revision__r;
			String revisionRecord = RECORD_DESIGN_REVISION
				+ (String.isBlank(revision.Revision_Number__c) ? '' : REV_PREFIX + revision.Revision_Number__c);

			addIfBlank(missing, LABEL_REV_NUMBER, revisionRecord, FIELD_REVISION_NUMBER, revision.Revision_Number__c);
			addIfNull(missing, LABEL_PLANNED_INSTALL_DATE, revisionRecord, FIELD_PLANNED_INSTALL_DATE, revision.Planned_Install_Date__c);

			// Module_Quantity_F__c is a formula that falls back to "0" when the
			// module wattage is blank, so zero - not null - is the empty case.
			if (String.isBlank(revision.Module_Quantity_F__c) || revision.Module_Quantity_F__c == ZERO_QUANTITY) {
				missing.add(describe(LABEL_TOTAL_MODULES, revisionRecord, FIELD_MODULE_QUANTITY));
			}

			addIfNull(missing, LABEL_PROJECT_SIZE, revisionRecord, FIELD_PROJECT_WATTAGE, revision.Project_Wattage_kW__c);
			addIfNull(missing, LABEL_TOTAL_ATTACHMENTS, revisionRecord, FIELD_TOTAL_ATTACHMENTS, revision.Total_Attachments__c);
			addIfBlank(missing, LABEL_MODULE_MANUFACTURER, revisionRecord, FIELD_MODULE_MANUFACTURER, revision.Module_Manufacturer__c);
			addIfBlank(missing, LABEL_MODULE_NUMBER, revisionRecord, FIELD_MODULE_MODEL_NUMBER, revision.Module_Model_Number__c);
			addIfBlank(missing, LABEL_MODULE_WATTS, revisionRecord, FIELD_MODULE_WATTAGE, revision.Module_Wattage__c);
			addIfBlank(missing, LABEL_SYSTEM, revisionRecord, FIELD_SYSTEM_TYPE, revision.System_Type__c);
			addIfBlank(missing, LABEL_TILT, revisionRecord, FIELD_PANEL_TILT, revision.Panel_Tilt__c);
		}

		// --- Racking Components table: Quote Line Items ---
		addLineItemIssues(missing, lineItems);

		return missing;
	}

	/**
	 * @throws IncompleteQuoteException listing every empty PDF value
	 */
	public static void validate(Id quoteId) {
		List<String> missing = getMissingFields(quoteId);
		if (missing.isEmpty()) return;
		throw new IncompleteQuoteException(buildMessage(missing));
	}

	public static String buildMessage(List<String> missing) {
		return MSG_PREFIX + String.join(missing, MSG_SEPARATOR);
	}

	/**
	 * Formats one reported entry: what is blank on the PDF, and where to fill it.
	 *
	 * @param pdfLabel the caption as printed on the PDF
	 * @param recordName the record to open, e.g. 'Design Revision REV-01'
	 * @param fieldLabel the field label on that record
	 */
	public static String describe(String pdfLabel, String recordName, String fieldLabel) {
		return pdfLabel + SOURCE_SEPARATOR + recordName + RECORD_SEPARATOR + fieldLabel;
	}

	private static void addCompanyIssue(List<String> missing, Opportunity opp) {
		String sourceField = FIELD_DISTRIBUTOR_TYPE;
		if (opp?.Distributor_Type__c == Constants.DISTRIBUTOR_TYPE_DIRECT) {
			sourceField = FIELD_ACCOUNT_NAME;
		} else if (opp?.Distributor_Type__c == Constants.DISTRIBUTOR_TYPE_INDIRECT) {
			sourceField = FIELD_DISTRIBUTOR;
		}
		addIfBlank(missing, LABEL_COMPANY_NAME, RECORD_OPPORTUNITY, sourceField,
			QuoteService.getRecipientCompanyName(opp));
	}

	private static void addLineItemIssues(List<String> missing, List<QuoteLineItem> lineItems) {
		if (lineItems == null || lineItems.isEmpty()) {
			missing.add(describe(LABEL_LINE_ITEMS, RECORD_QUOTE, FIELD_ADD_LINE_ITEMS));
			return;
		}

		for (QuoteLineItem li : lineItems) {
			String productName = String.isBlank(li.Product2?.Name)
				? LABEL_UNNAMED_PRODUCT
				: li.Product2.Name;

			if (li.Quantity == null || li.Quantity == 0) {
				missing.add(describe(LABEL_LINE_ITEM_QUANTITY, RECORD_QUOTE, FIELD_LINE_ITEM_QUANTITY + productName));
			}
			// The PDF derives the printed unit price from TotalPrice, falling back
			// to UnitPrice - a line with neither prints $ 0.00.
			if (li.TotalPrice == null && li.UnitPrice == null) {
				missing.add(describe(LABEL_LINE_ITEM_PRICE, RECORD_QUOTE, FIELD_LINE_ITEM_PRICE + productName));
			}
		}
	}

	private static void addIfBlank(
		List<String> missing, String pdfLabel, String recordName, String fieldLabel, String value
	) {
		if (String.isBlank(value)) missing.add(describe(pdfLabel, recordName, fieldLabel));
	}

	private static void addIfNull(
		List<String> missing, String pdfLabel, String recordName, String fieldLabel, Object value
	) {
		if (value == null) missing.add(describe(pdfLabel, recordName, fieldLabel));
	}
}
