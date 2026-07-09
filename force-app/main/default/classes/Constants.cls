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

	public static final String OPP_INTEGRATION_STATUS_PENDING = 'Pending';
	public static final String OPP_INTEGRATION_STATUS_SENT = 'Sent';
	public static final String OPP_INTEGRATION_STATUS_FAILED = 'Failed';

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
