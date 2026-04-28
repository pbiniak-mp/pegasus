public class Constants {

	// BoltErrorLogger
	public static final String SOURCE_TYPE_APEX = 'Apex';
	public static final String SEVERITY_ERROR = 'ERROR';

	// REST Response
	public static final Integer HTTP_STATUS_OK = 200;
	public static final Integer HTTP_STATUS_BAD_REQUEST = 400;
	public static final Integer HTTP_STATUS_INTERNAL_ERROR = 500;

	public static final String HTTP_HEADER_CONTENT_TYPE = 'Content-Type';
	public static final String HTTP_CONTENT_TYPE_TEXT_PLAIN = 'text/plain';

	public static final String HTTP_RESPONSE_PREFIX_OK = 'OK: ';
	public static final String HTTP_RESPONSE_PREFIX_ERROR = 'ERROR: ';
	public static final String HTTP_RESPONSE_ERROR_JOIN_SEPARATOR = ' | ';

	// NetSuite Inventory API
	public static final String NETSUITE_INVENTORY_LOG_PAYLOAD = 'NetSuite Inventory Payload: ';
	public static final String NETSUITE_INVENTORY_LOG_SKIP_ITEM = 'Skipping item with missing IDs: ';
	public static final String NETSUITE_INVENTORY_LOG_UPSERT_SUMMARY = 'Inventory upsert complete. Success: ';
	public static final String NETSUITE_INVENTORY_LOG_UPSERT_ERRORS = 'Inventory upsert errors: ';
	public static final String NETSUITE_INVENTORY_LOG_ERROR_PREFIX = 'NetSuiteInventoryApi error: ';

	public static final String NETSUITE_INVENTORY_MSG_EMPTY_PAYLOAD = 'Empty or missing items array';
	public static final String NETSUITE_INVENTORY_MSG_NO_VALID_ITEMS = 'No valid items to process';
	public static final String NETSUITE_INVENTORY_MSG_UPSERTED_SUFFIX = ' upserted';
	public static final String NETSUITE_INVENTORY_MSG_FAILED_SUFFIX = ' failed: ';

	public static final String NETSUITE_INVENTORY_COMPOSITE_KEY_SEPARATOR = '-';
	public static final Decimal NETSUITE_INVENTORY_DEFAULT_ON_HAND_QTY = 0;

	// NetSuite Product API
	public static final String NETSUITE_PRODUCT_LOG_PAYLOAD = 'NetSuite Product Payload: ';
	public static final String NETSUITE_PRODUCT_LOG_SKIP_ITEM = 'Skipping product item with missing fields: ';
	public static final String NETSUITE_PRODUCT_LOG_MISSING = 'No Product2 found for External_Id__c: ';
	public static final String NETSUITE_PRODUCT_LOG_UPDATE_SUMMARY = 'Product update complete. Success: ';
	public static final String NETSUITE_PRODUCT_LOG_UPDATE_ERRORS = 'Product update errors: ';
	public static final String NETSUITE_PRODUCT_LOG_ERROR_PREFIX = 'NetSuiteProductApi error: ';

	public static final String NETSUITE_PRODUCT_MSG_EMPTY_PAYLOAD = 'Empty or missing items array';
	public static final String NETSUITE_PRODUCT_MSG_NO_VALID_ITEMS = 'No valid items to process';
	public static final String NETSUITE_PRODUCT_MSG_UPDATED_SUFFIX = ' updated';
	public static final String NETSUITE_PRODUCT_MSG_FAILED_SUFFIX = ' failed: ';
	public static final String NETSUITE_PRODUCT_MSG_MISSING_SUFFIX = ' missing';

	// Inventory Location
	public static final String INVENTORY_LOCATION_HANDLER_NAME = 'InventoryLocationTriggerHandler';
	public static final String WAREHOUSE_LOCATION_TYPE_CONSIGNED = 'Consigned';
	public static final Decimal INVENTORY_LOCATION_DEFAULT_ON_HAND = 0;

	// Opportunity Line Item
	public static final String OPPORTUNITY_LINE_ITEM_HANDLER_NAME = 'OpportunityLineItemTriggerHandler';

	// Quote
	public static final String QUOTE_HANDLER_NAME = 'QuoteTriggerHandler';

	// Quote Line Item
	public static final String QUOTE_LINE_ITEM_HANDLER_NAME = 'QuoteLineItemTriggerHandler';

	// Design Revision
	public static final String DESIGN_REVISION_HANDLER_NAME = 'DesignRevisionTriggerHandler';
	public static final String DESIGN_REVISION_STATUS_NEW = 'New';
	public static final String DESIGN_REVISION_NAME_PREFIX = 'REV';
	public static final String DESIGN_REVISION_NAME_DEFAULT_NUMBER = 'REV00';
	public static final String DESIGN_REVISION_UNKNOWN_ACCOUNT = 'Unknown';
	public static final String DESIGN_REVISION_RECORD_URL_BASE = '/lightning/r/Design_Revision__c/';
	public static final String RECORD_URL_VIEW_SUFFIX = '/view';
}
