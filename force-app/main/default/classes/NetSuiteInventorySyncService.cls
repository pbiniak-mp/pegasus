/**
 * Applies one batch of the daily NetSuite -> Salesforce inventory snapshot.
 *
 * NetSuite sends the full item x location matrix (zero rows included), chunked
 * so that every location of an item arrives in the same request. For each batch:
 *   - Warehouse_Location__c is resolved by NetSuite_ID__c.
 *   - Product2 is resolved by External_Id__c, falling back to
 *     Product_Name_External__c = the NetSuite item name.
 *   - Inventory_Location__c is upserted by Composite_Key__c. Rows whose product
 *     or location cannot be resolved are skipped (never written as orphans) and
 *     reported. On_Hand__c / Consignment_Stock_On_Hand__c on Product2 are then
 *     rolled up by InventoryLocationTrigger as before.
 *   - Product2.Committed__c is written directly as the sum of committedQty
 *     across the item's rows in the batch.
 */
public with sharing class NetSuiteInventorySyncService {

	public class SyncException extends Exception {}

	// Lets tests prove that an unexpected failure after the upsert is rolled back
	// by NetSuiteInventoryApi. Never set outside tests.
	@TestVisible
	private static Boolean simulateFailureAfterUpsert = false;

	public class SyncRequest {
		public String runId;
		public String generatedAt;
		public Integer batchNumber;
		public Integer batchCount;
		public List<InventoryRow> items;
	}

	public class InventoryRow {
		public String netsuiteItemId;
		public String netsuiteItemName;
		public String netsuiteLocationId;
		public String locationName;
		public Decimal onHandQty;
		public Decimal committedQty;
	}

	public class SyncResult {
		public String status;
		public String runId;
		public Integer batchNumber;
		public Integer batchCount;
		public Id logId;
		public Integer rowsReceived = 0;
		public Integer rowsUpserted = 0;
		public Integer rowsSkipped = 0;
		public Integer rowsFailed = 0;
		public Integer productsCommittedUpdated = 0;
		public Integer productsCommittedFailed = 0;
		public List<String> skipped = new List<String>();
		public List<String> errors = new List<String>();
		public List<String> resolvedByName = new List<String>();

		public Boolean hasProblems() {
			return rowsSkipped > 0 || rowsFailed > 0 || productsCommittedFailed > 0;
		}
	}

	/**
	 * Groups skipped rows by subject + reason so a missing product produces one
	 * line ("12 rows skipped") instead of one line per location.
	 */
	private class SkipTracker {
		private final List<String> order = new List<String>();
		private final Map<String, Integer> countByMessage = new Map<String, Integer>();

		public void add(String subject, String reason) {
			String message = subject + ': ' + reason;
			if (!countByMessage.containsKey(message)) {
				order.add(message);
				countByMessage.put(message, 0);
			}
			countByMessage.put(message, countByMessage.get(message) + 1);
		}

		public List<String> toMessages() {
			List<String> messages = new List<String>();
			for (String message : order) {
				Integer count = countByMessage.get(message);
				messages.add(message + ' (' + count + (count == 1 ? ' row' : ' rows') + ' skipped)');
			}
			return messages;
		}
	}

	/** Product2 resolution outcome for the items in one batch. */
	private class ProductResolution {
		public final Map<String, Product2> productByItemId = new Map<String, Product2>();
		public final Map<String, String> failureReasonByItemId = new Map<String, String>();
		public final List<String> resolvedByName = new List<String>();
	}

	public static SyncResult sync(SyncRequest request) {
		SyncResult result = new SyncResult();
		result.runId = request.runId;
		result.batchNumber = request.batchNumber;
		result.batchCount = request.batchCount;
		result.rowsReceived = request.items == null ? 0 : request.items.size();

		SkipTracker skips = new SkipTracker();
		Map<String, InventoryRow> rowByKey = dedupeValidRows(request.items, skips, result);

		Map<String, String> itemNameById = new Map<String, String>();
		Set<String> locationIds = new Set<String>();
		for (InventoryRow row : rowByKey.values()) {
			if (String.isNotBlank(row.netsuiteItemName) || !itemNameById.containsKey(row.netsuiteItemId)) {
				itemNameById.put(row.netsuiteItemId, row.netsuiteItemName);
			}
			locationIds.add(row.netsuiteLocationId);
		}

		Map<String, Id> locationIdByNetSuiteId = resolveLocations(locationIds);
		ProductResolution products = resolveProducts(itemNameById);
		result.resolvedByName.addAll(products.resolvedByName);

		System.debug(
			LoggingLevel.INFO,
			Constants.NETSUITE_INVENTORY_DEBUG_PREFIX + 'Resolution: '
				+ itemNameById.size() + ' items, '
				+ (products.productByItemId.size() - products.resolvedByName.size()) + ' by External_Id__c, '
				+ products.resolvedByName.size() + ' by Product_Name_External__c, '
				+ products.failureReasonByItemId.size() + ' unresolved ' + JSON.serialize(products.failureReasonByItemId)
				+ '; locations ' + locationIdByNetSuiteId.size() + '/' + locationIds.size()
				+ ' resolved ' + JSON.serialize(locationIdByNetSuiteId)
		);

		List<Inventory_Location__c> toUpsert = new List<Inventory_Location__c>();
		Map<Id, Decimal> committedByProductId = new Map<Id, Decimal>();

		for (String key : rowByKey.keySet()) {
			InventoryRow row = rowByKey.get(key);
			Product2 product = products.productByItemId.get(row.netsuiteItemId);

			if (product == null) {
				skips.add(describeItem(row), products.failureReasonByItemId.get(row.netsuiteItemId));
				result.rowsSkipped++;
				continue;
			}

			// Committed is a product-level total: it counts every row of the item,
			// even one whose location cannot be resolved below.
			if (row.committedQty != null) {
				Decimal runningTotal = committedByProductId.containsKey(product.Id)
					? committedByProductId.get(product.Id)
					: Constants.NETSUITE_INVENTORY_DEFAULT_QTY;
				committedByProductId.put(product.Id, runningTotal + row.committedQty);
			}

			Id locationId = locationIdByNetSuiteId.get(row.netsuiteLocationId);
			if (locationId == null) {
				skips.add(
					'Location ' + row.netsuiteLocationId,
					String.format(
						Constants.NETSUITE_INVENTORY_REASON_LOCATION_NOT_FOUND,
						new List<Object>{ row.netsuiteLocationId }
					)
				);
				result.rowsSkipped++;
				continue;
			}

			toUpsert.add(new Inventory_Location__c(
				Composite_Key__c = key,
				Product__c = product.Id,
				Location__c = locationId,
				Quantity_On_Hand__c = row.onHandQty != null ? row.onHandQty : Constants.NETSUITE_INVENTORY_DEFAULT_QTY,
				NetSuite_Item_ID__c = row.netsuiteItemId,
				NetSuite_Location_ID__c = row.netsuiteLocationId
			));
		}

		upsertInventoryLocations(toUpsert, result);
		if (simulateFailureAfterUpsert) {
			throw new SyncException('Simulated failure after upsert');
		}
		updateCommitted(committedByProductId, result);

		result.skipped.addAll(skips.toMessages());
		result.status = resolveStatus(result);

		System.debug(
			Constants.NETSUITE_INVENTORY_DEBUG_PREFIX + 'run ' + result.runId
				+ ' batch ' + result.batchNumber + '/' + result.batchCount
				+ ': received ' + result.rowsReceived
				+ ', upserted ' + result.rowsUpserted
				+ ', skipped ' + result.rowsSkipped
				+ ', failed ' + result.rowsFailed
				+ ', committed updated ' + result.productsCommittedUpdated
				+ ', committed failed ' + result.productsCommittedFailed
		);
		return result;
	}

	public static String buildCompositeKey(String netsuiteItemId, String netsuiteLocationId) {
		return netsuiteItemId + Constants.NETSUITE_INVENTORY_COMPOSITE_KEY_SEPARATOR + netsuiteLocationId;
	}

	/**
	 * Drops rows without both ids and keeps the last row per item + location, so
	 * a repeated row can neither fail the upsert nor double-count Committed__c.
	 */
	private static Map<String, InventoryRow> dedupeValidRows(
		List<InventoryRow> rows,
		SkipTracker skips,
		SyncResult result
	) {
		Map<String, InventoryRow> rowByKey = new Map<String, InventoryRow>();
		if (rows == null) {
			return rowByKey;
		}

		for (InventoryRow row : rows) {
			if (row == null || String.isBlank(row.netsuiteItemId) || String.isBlank(row.netsuiteLocationId)) {
				skips.add(
					'Item ' + (row == null ? null : row.netsuiteItemId)
						+ ' / location ' + (row == null ? null : row.netsuiteLocationId),
					Constants.NETSUITE_INVENTORY_REASON_MISSING_IDS
				);
				result.rowsSkipped++;
				continue;
			}

			row.netsuiteItemId = row.netsuiteItemId.trim();
			row.netsuiteLocationId = row.netsuiteLocationId.trim();
			row.netsuiteItemName = row.netsuiteItemName == null ? null : row.netsuiteItemName.trim();

			String key = buildCompositeKey(row.netsuiteItemId, row.netsuiteLocationId);
			if (rowByKey.containsKey(key)) {
				skips.add('Composite key ' + key, Constants.NETSUITE_INVENTORY_REASON_DUPLICATE_ROW);
				result.rowsSkipped++;
			}
			rowByKey.put(key, row);
		}
		return rowByKey;
	}

	private static Map<String, Id> resolveLocations(Set<String> netSuiteLocationIds) {
		Map<String, Id> locationIdByNetSuiteId = new Map<String, Id>();
		if (netSuiteLocationIds.isEmpty()) {
			return locationIdByNetSuiteId;
		}
		for (Warehouse_Location__c location : WarehouseLocationSelector.getByNetSuiteIds(netSuiteLocationIds)) {
			locationIdByNetSuiteId.put(location.NetSuite_ID__c, location.Id);
		}
		return locationIdByNetSuiteId;
	}

	/**
	 * External_Id__c first. Items still unresolved fall back to
	 * Product_Name_External__c = NetSuite item name (case-insensitive, like the
	 * field itself). A name match is rejected when that Product2 is already
	 * matched by External_Id__c to a different item in the same batch, so one
	 * product can never receive two items' stock.
	 */
	private static ProductResolution resolveProducts(Map<String, String> itemNameById) {
		ProductResolution resolution = new ProductResolution();
		if (itemNameById.isEmpty()) {
			return resolution;
		}

		Set<Id> productIdsMatchedById = new Set<Id>();
		for (Product2 product : Product2Selector.getProductsByExternalIds(itemNameById.keySet())) {
			resolution.productByItemId.put(product.External_Id__c, product);
			productIdsMatchedById.add(product.Id);
		}

		Map<String, String> unresolvedItemIdByName = new Map<String, String>();
		for (String itemId : itemNameById.keySet()) {
			if (resolution.productByItemId.containsKey(itemId)) {
				continue;
			}
			String itemName = itemNameById.get(itemId);
			resolution.failureReasonByItemId.put(
				itemId,
				String.format(
					Constants.NETSUITE_INVENTORY_REASON_PRODUCT_NOT_FOUND,
					new List<Object>{ itemId, itemName }
				)
			);
			if (String.isNotBlank(itemName)) {
				unresolvedItemIdByName.put(itemName.toLowerCase(), itemId);
			}
		}

		if (unresolvedItemIdByName.isEmpty()) {
			return resolution;
		}

		for (Product2 product : Product2Selector.getProductsByNameExternal(unresolvedItemIdByName.keySet())) {
			String itemId = unresolvedItemIdByName.get(product.Product_Name_External__c.toLowerCase());
			if (itemId == null) {
				continue;
			}
			if (productIdsMatchedById.contains(product.Id)) {
				resolution.failureReasonByItemId.put(
					itemId,
					String.format(
						Constants.NETSUITE_INVENTORY_REASON_NAME_MATCH_CONFLICT,
						new List<Object>{ product.Product_Name_External__c, product.Id }
					)
				);
				continue;
			}
			resolution.productByItemId.put(itemId, product);
			resolution.failureReasonByItemId.remove(itemId);
			resolution.resolvedByName.add(
				'Item ' + itemId + ' (' + itemNameById.get(itemId) + ') -> Product2 ' + product.Id
					+ ' (' + product.Name + '), External_Id__c = '
					+ (String.isBlank(product.External_Id__c) ? 'blank' : product.External_Id__c)
			);
		}
		return resolution;
	}

	private static void upsertInventoryLocations(List<Inventory_Location__c> records, SyncResult result) {
		if (records.isEmpty()) {
			return;
		}
		Database.UpsertResult[] saveResults = Database.upsert(
			records,
			Inventory_Location__c.Composite_Key__c,
			false
		);
		for (Integer i = 0; i < saveResults.size(); i++) {
			if (saveResults[i].isSuccess()) {
				result.rowsUpserted++;
				continue;
			}
			result.rowsFailed++;
			result.errors.add(
				'Inventory_Location__c ' + records[i].Composite_Key__c + ': ' + joinErrors(saveResults[i].getErrors())
			);
		}
	}

	private static void updateCommitted(Map<Id, Decimal> committedByProductId, SyncResult result) {
		if (committedByProductId.isEmpty()) {
			return;
		}
		List<Product2> toUpdate = new List<Product2>();
		for (Id productId : committedByProductId.keySet()) {
			toUpdate.add(new Product2(Id = productId, Committed__c = committedByProductId.get(productId)));
		}
		Database.SaveResult[] saveResults = Database.update(toUpdate, false);
		for (Integer i = 0; i < saveResults.size(); i++) {
			if (saveResults[i].isSuccess()) {
				result.productsCommittedUpdated++;
				continue;
			}
			result.productsCommittedFailed++;
			result.errors.add(
				'Product2 ' + toUpdate[i].Id + ' Committed__c: ' + joinErrors(saveResults[i].getErrors())
			);
		}
	}

	private static String resolveStatus(SyncResult result) {
		if (!result.hasProblems()) {
			return Constants.INTEGRATION_STATUS_PROCESSED;
		}
		if (result.rowsUpserted == 0 && result.productsCommittedUpdated == 0) {
			return Constants.INTEGRATION_STATUS_FAILED;
		}
		return Constants.INTEGRATION_STATUS_PARTIALLY_PROCESSED;
	}

	private static String describeItem(InventoryRow row) {
		return 'Item ' + row.netsuiteItemId
			+ (String.isBlank(row.netsuiteItemName) ? '' : ' (' + row.netsuiteItemName + ')');
	}

	private static String joinErrors(List<Database.Error> errors) {
		List<String> parts = new List<String>();
		for (Database.Error err : errors) {
			parts.add(err.getStatusCode() + ' - ' + err.getMessage());
		}
		return String.join(parts, '; ');
	}
}
