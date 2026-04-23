@RestResource(UrlMapping='/netsuite/inventory/*')
global with sharing class NetSuiteInventoryApi {

	global class InventoryPayload {
		global List<InventoryItem> items;
	}

	global class InventoryItem {
		global String  netsuiteItemId;
		global String  netsuiteLocationId;
		global String  locationName;
		global Decimal onHandQty;
	}

	@HttpPost
	global static void handlePost() {
		try {
			String requestBody = RestContext.request.requestBody.toString();
			System.debug(Constants.NETSUITE_INVENTORY_LOG_PAYLOAD + requestBody);

			InventoryPayload payload = (InventoryPayload) JSON.deserialize(
				requestBody, InventoryPayload.class
			);

			if (isEmpty(payload)) {
				RestResponseUtils.sendBadRequest(Constants.NETSUITE_INVENTORY_MSG_EMPTY_PAYLOAD);
				return;
			}

			List<Inventory_Location__c> toUpsert = buildRecords(payload.items);

			if (toUpsert.isEmpty()) {
				RestResponseUtils.sendOk(Constants.NETSUITE_INVENTORY_MSG_NO_VALID_ITEMS);
				return;
			}

			RestResponseUtils.sendOk(upsertAndSummarize(toUpsert));

		} catch (Exception e) {
			System.debug(Constants.NETSUITE_INVENTORY_LOG_ERROR_PREFIX + e.getMessage() + '\n' + e.getStackTraceString());
			RestResponseUtils.sendInternalError(e);
		}
	}

	private static Boolean isEmpty(InventoryPayload payload) {
		return payload == null || payload.items == null || payload.items.isEmpty();
	}

	private static List<Inventory_Location__c> buildRecords(List<InventoryItem> items) {
		List<Inventory_Location__c> records = new List<Inventory_Location__c>();
		for (InventoryItem item : items) {
			if (String.isBlank(item.netsuiteItemId) || String.isBlank(item.netsuiteLocationId)) {
				System.debug(Constants.NETSUITE_INVENTORY_LOG_SKIP_ITEM + JSON.serialize(item));
				continue;
			}
			records.add(new Inventory_Location__c(
				Composite_Key__c        = buildCompositeKey(item),
				Quantity_On_Hand__c     = item.onHandQty != null ? item.onHandQty : Constants.NETSUITE_INVENTORY_DEFAULT_ON_HAND_QTY,
				NetSuite_Item_ID__c     = item.netsuiteItemId,
				NetSuite_Location_ID__c = item.netsuiteLocationId
			));
		}
		return records;
	}

	private static String buildCompositeKey(InventoryItem item) {
		return item.netsuiteItemId + Constants.NETSUITE_INVENTORY_COMPOSITE_KEY_SEPARATOR + item.netsuiteLocationId;
	}

	private static String upsertAndSummarize(List<Inventory_Location__c> records) {
		Database.UpsertResult[] results = Database.upsert(
			records, Inventory_Location__c.Composite_Key__c, false
		);

		Integer successCount = 0;
		List<String> errors = new List<String>();

		for (Integer i = 0; i < results.size(); i++) {
			if (results[i].isSuccess()) {
				successCount++;
			} else {
				String itemKey = records[i].Composite_Key__c;
				for (Database.Error err : results[i].getErrors()) {
					errors.add(itemKey + ': ' + err.getStatusCode() + ' - ' + err.getMessage());
				}
			}
		}

		System.debug(Constants.NETSUITE_INVENTORY_LOG_UPSERT_SUMMARY + successCount + ', Errors: ' + errors.size());
		if (!errors.isEmpty()) {
			System.debug(Constants.NETSUITE_INVENTORY_LOG_UPSERT_ERRORS
				+ String.join(errors, Constants.HTTP_RESPONSE_ERROR_JOIN_SEPARATOR));
		}

		String message = successCount + Constants.NETSUITE_INVENTORY_MSG_UPSERTED_SUFFIX;
		if (!errors.isEmpty()) {
			message += ', ' + errors.size() + Constants.NETSUITE_INVENTORY_MSG_FAILED_SUFFIX
				+ String.join(errors, Constants.HTTP_RESPONSE_ERROR_JOIN_SEPARATOR);
		}
		return message;
	}
}
