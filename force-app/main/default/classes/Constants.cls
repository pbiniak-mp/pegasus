public class Constants {

	// BoltErrorLogger
	public static final String SOURCE_TYPE_APEX = 'Apex';
	public static final String SEVERITY_ERROR = 'ERROR';

	// REST Response
	public static final Integer HTTP_STATUS_OK = 200;
	public static final Integer HTTP_STATUS_BAD_REQUEST = 400;
	public static final Integer HTTP_STATUS_INTERNAL_ERROR = 500;

	public static final String HTTP_HEADER_CONTENT_TYPE = 'Content-Type';

	// NetSuite Inventory Sync (inbound, POST /services/apexrest/netsuite/inventory)
	public static final String NETSUITE_INVENTORY_INTEGRATION_NAME = 'NetSuite_Inventory_Sync';
	public static final String NETSUITE_INVENTORY_EVENT_TYPE = 'Inventory Sync';
	public static final String NETSUITE_INVENTORY_SOURCE_OBJECT = 'Inventory_Location__c';
	public static final String NETSUITE_INVENTORY_ENDPOINT = '/services/apexrest/netsuite/inventory';
	public static final String NETSUITE_INVENTORY_COMPOSITE_KEY_SEPARATOR = '-';
	public static final Decimal NETSUITE_INVENTORY_DEFAULT_QTY = 0;
	public static final String NETSUITE_INVENTORY_DEBUG_PREFIX = 'NetSuiteInventorySync: ';
	public static final String NETSUITE_INVENTORY_ERROR_CATEGORY = 'NetSuite Inventory Sync';

	public static final String NETSUITE_INVENTORY_MSG_EMPTY_BODY = 'Request body is empty';
	public static final String NETSUITE_INVENTORY_MSG_MALFORMED_JSON = 'Request body is not valid JSON: ';
	public static final String NETSUITE_INVENTORY_MSG_EMPTY_PAYLOAD = 'Empty or missing items array';
	public static final String NETSUITE_INVENTORY_MSG_UNEXPECTED_ERROR = 'Unexpected error, all changes from this request were rolled back: ';

	public static final String NETSUITE_INVENTORY_REASON_MISSING_IDS = 'row has a blank netsuiteItemId or netsuiteLocationId';
	public static final String NETSUITE_INVENTORY_REASON_PRODUCT_NOT_FOUND = 'no Product2 with External_Id__c = {0} or Product_Name_External__c = "{1}"';
	public static final String NETSUITE_INVENTORY_REASON_NAME_MATCH_CONFLICT = 'Product_Name_External__c = "{0}" matches Product2 {1}, which is already matched by External_Id__c to another item in this request';
	public static final String NETSUITE_INVENTORY_REASON_LOCATION_NOT_FOUND = 'no Warehouse_Location__c with NetSuite_ID__c = {0}';
	public static final String NETSUITE_INVENTORY_REASON_DUPLICATE_ROW = 'duplicate row for the same item and location in this request, the last one was used';

	// Inventory Location
	public static final String INVENTORY_LOCATION_HANDLER_NAME = 'InventoryLocationTriggerHandler';
	public static final String WAREHOUSE_LOCATION_TYPE_CONSIGNED = 'Consigned';
	public static final Decimal INVENTORY_LOCATION_DEFAULT_ON_HAND = 0;

	// Opportunity Line Item
	public static final String OPPORTUNITY_LINE_ITEM_HANDLER_NAME = 'OpportunityLineItemTriggerHandler';

	// Quote
	public static final String QUOTE_HANDLER_NAME = 'QuoteTriggerHandler';
	public static final String QUOTE_STATUS_PRESENTED = 'Presented';
	public static final String QUOTE_TYPE_MATERIAL = 'Material';
	public static final String QUOTE_TYPE_STAMP = 'Stamp';
	public static final String QUOTE_TYPE_EXTRA = 'Extra';

	// Quote Line Item
	public static final String QUOTE_LINE_ITEM_HANDLER_NAME = 'QuoteLineItemTriggerHandler';

	// Product
	public static final String PRODUCT_FAMILY_FIXED_PRICE = 'FIXED PRICED PRODUCTS';

	// Lead
	public static final String LEAD_HANDLER_NAME = 'LeadTriggerHandler';
	public static final Integer LEAD_CONVERSION_NEW_ACCOUNT_WINDOW_SECONDS = 30;

	// Design Revision
	public static final String DESIGN_REVISION_HANDLER_NAME = 'DesignRevisionTriggerHandler';
	public static final String DESIGN_REVISION_STATUS_NEW = 'New';
	public static final String DESIGN_REVISION_STATUS_ASSIGNED = 'Assigned';
	public static final String DESIGN_REVISION_STATUS_QUOTE = 'Quote';
	public static final String DESIGN_REVISION_STATUS_CLOSED = 'Closed';
	public static final String OPPORTUNITY_STAGE_QUOTE = 'Quote';
	public static final String OPPORTUNITY_STAGE_OFFERED = 'Offered';
	public static final String DESIGN_REVISION_NAME_PREFIX = 'REV';
	public static final String DESIGN_REVISION_NAME_DEFAULT_NUMBER = 'REV00';
	public static final String DESIGN_REVISION_UNKNOWN_ACCOUNT = 'Unknown';
	public static final String DESIGN_REVISION_RECORD_URL_BASE = '/lightning/r/Design_Revision__c/';
	public static final String RECORD_URL_VIEW_SUFFIX = '/view';

	// Project Code (CCC-TT-PPPPP-RR-SS-KWW)
	public static final String PROJECT_CODE_SEGMENT_SEPARATOR = '-';
	public static final Integer PROJECT_SHORT_NAME_LENGTH = 5;
	// Stripped from every free-text segment so nothing can smuggle a separator
	// (or any other punctuation) into the code and break a parser splitting on '-'.
	public static final String PROJECT_CODE_INVALID_CHARS = '[^a-zA-Z0-9]';
	// Product Line -> TT acronym (Product_Line_Code__c). Placeholder values pending
	// Charles's approval; a new Product Line value needs an entry here AND a
	// matching value on the Product_Line_Code__c picklist.
	public static final Map<String, String> PRODUCT_LINE_TO_CODE = new Map<String, String>{
		'Flat FX' => 'FX',
		'Flat S' => 'FS',
		'S-Base' => 'SB',
		'SN2' => 'SN',
		'G-Base' => 'GB',
		'Scale' => 'SC'
	};

	// Outbound Integration
	public static final String OPPORTUNITY_HANDLER_NAME = 'OpportunityTriggerHandler';

	public static final String INTEGRATION_GLIDE_ANALYTICS = 'Glide_Analytics';
	public static final String INTEGRATION_SOURCE_OBJECT_OPPORTUNITY = 'Opportunity';

	public static final String INTEGRATION_EVENT_OPP_CREATED = 'Opportunity Created';
	public static final String INTEGRATION_EVENT_OPP_STAGE_CHANGED = 'Opportunity Stage Changed';

	public static final String INTEGRATION_LOG_RT_OUTBOUND = 'Outbound';
	public static final String INTEGRATION_LOG_RT_INBOUND = 'Inbound';

	public static final String INTEGRATION_STATUS_QUEUED = 'Queued';
	public static final String INTEGRATION_STATUS_SENT = 'Sent';
	public static final String INTEGRATION_STATUS_FAILED = 'Failed';
	public static final String INTEGRATION_STATUS_PROCESSED = 'Processed';
	public static final String INTEGRATION_STATUS_PARTIALLY_PROCESSED = 'Partially Processed';

	public static final String INTEGRATION_HTTP_METHOD_POST = 'POST';
	public static final String INTEGRATION_HTTP_METHOD_PATCH = 'PATCH';
	public static final String INTEGRATION_LOG_DEBUG_PREFIX = 'OutboundIntegration: ';
	public static final String HTTP_CONTENT_TYPE_JSON = 'application/json';
	public static final String HTTP_HEADER_ACCEPT = 'Accept';
	public static final String HTTP_HEADER_AUTHORIZATION = 'Authorization';
	public static final String INTEGRATION_MASKED_VALUE = '****';
	public static final String CALLOUT_PREFIX = 'callout:';

	public static final Integer INTEGRATION_CALLOUT_TIMEOUT_MS = 120000;
	public static final Integer INTEGRATION_CALLOUT_CHUNK_SIZE = 90;

	public static final String INTEGRATION_ERROR_CATEGORY = 'Outbound Integration';

	// --- Log retention (nightly purge of ageing log records) ---
	// Records are always aged on CreatedDate: it exists on every object, is always
	// populated and cannot be edited afterwards, so "how old is this record" has
	// exactly one answer.
	public static final String LOG_RETENTION_DATE_FIELD = 'CreatedDate';
	public static final Integer LOG_RETENTION_BATCH_SIZE = 200;
	public static final Integer LOG_RETENTION_MAX_TRACKED_ERRORS = 20;
	public static final String LOG_RETENTION_ERROR_CATEGORY = 'Log Retention';
	public static final String LOG_RETENTION_DEBUG_PREFIX = 'LogRetention: ';
	public static final String LOG_RETENTION_JOB_NAME = 'Log Retention Nightly';
	public static final String LOG_RETENTION_CRON_MIDNIGHT = '0 0 0 * * ?';

	// --- AI Chat agent (read-only Claude assistant) ---
	public static final String ANTHROPIC_NAMED_CREDENTIAL = 'Anthropic_API';
	public static final String ANTHROPIC_MESSAGES_PATH = '/v1/messages';
	public static final String ANTHROPIC_MODEL = 'claude-sonnet-4-6';
	public static final Integer ANTHROPIC_MAX_TOKENS = 1024;
	public static final Integer AGENT_MAX_ITERATIONS = 5;
	public static final Integer AGENT_DEFAULT_QUERY_LIMIT = 200;
	public static final String AGENT_TOOL_NAME = 'run_soql';
	public static final String AGENT_ERROR_CATEGORY = 'AI Chat Agent';
	// Shown to the user when Anthropic rejects the callout with HTTP 401 — i.e. the
	// API key in the External Credential is missing, empty, expired or invalid.
	public static final Integer ANTHROPIC_UNAUTHORIZED_STATUS = 401;
	public static final Integer ANTHROPIC_FORBIDDEN_STATUS = 403;
	public static final String AGENT_API_KEY_MISSING_MESSAGE =
		'The AI assistant is not available yet because no valid Anthropic API key is configured. ' +
		'Please ask your Salesforce administrator to add a valid API key to the "Anthropic API Credential" ' +
		'external credential (the "ApiKey" parameter) under Setup → Named Credentials, then try again.';
	// Custom Permission that gates access to the AI chat (granted by the
	// AI_Chat_Agent_User permission set). Checked in the LWC to hide the UI and in
	// the controller as a server-side guard.
	public static final String AGENT_ACCESS_CUSTOM_PERMISSION = 'AI_Chat_Agent_Access';
	public static final String AGENT_NO_ACCESS_MESSAGE =
		'You do not have permission to use the AI Chat. Please ask your Salesforce administrator ' +
		'to assign you the "AI Chat Agent User" permission set.';
}
