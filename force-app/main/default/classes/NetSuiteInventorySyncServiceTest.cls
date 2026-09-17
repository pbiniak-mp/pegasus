@IsTest
private class NetSuiteInventorySyncServiceTest {

	// Test-only ids: External_Id__c, NetSuite_ID__c and Product_Name_External__c are
	// unique fields, so they must never collide with real NetSuite ids in the org.
	private static final String ITEM_BY_ID = 'TNS-ITEM-1';
	private static final String ITEM_BY_ID_NAME = 'TEST-SKU-BY-ID';
	private static final String ITEM_BY_NAME = 'TNS-ITEM-2';
	private static final String ITEM_BY_NAME_NAME = 'TEST-SKU-NAME-ONLY';
	private static final String ITEM_CONFLICT_OWNER = 'TNS-ITEM-3';
	private static final String CONFLICT_NAME = 'TEST-SKU-CONFLICT';
	private static final String ITEM_UNKNOWN = 'TNS-ITEM-404';
	private static final String LOC_OFFLINE = 'TNS-LOC-2';
	private static final String LOC_CONSIGNED = 'TNS-LOC-12';
	private static final String LOC_UNKNOWN = 'TNS-LOC-404';

	private static final Integer BULK_ITEMS = 50;
	private static final Integer BULK_LOCATIONS = 12;

	@TestSetup
	static void setup() {
		insert new List<Product2>{
			new Product2(Name = 'Test By Id', External_Id__c = ITEM_BY_ID),
			new Product2(Name = 'Test By Name', Product_Name_External__c = ITEM_BY_NAME_NAME),
			new Product2(Name = 'Test Conflict Owner', External_Id__c = ITEM_CONFLICT_OWNER, Product_Name_External__c = CONFLICT_NAME)
		};
		insert new List<Warehouse_Location__c>{
			new Warehouse_Location__c(Name = 'Test Offline', NetSuite_ID__c = LOC_OFFLINE, Type__c = 'Offline'),
			new Warehouse_Location__c(
				Name = 'Test Consigned',
				NetSuite_ID__c = LOC_CONSIGNED,
				Type__c = Constants.WAREHOUSE_LOCATION_TYPE_CONSIGNED
			)
		};
	}

	private static NetSuiteInventorySyncService.InventoryRow row(
		String itemId,
		String itemName,
		String locationId,
		Decimal onHand,
		Decimal committed
	) {
		NetSuiteInventorySyncService.InventoryRow r = new NetSuiteInventorySyncService.InventoryRow();
		r.netsuiteItemId = itemId;
		r.netsuiteItemName = itemName;
		r.netsuiteLocationId = locationId;
		r.onHandQty = onHand;
		r.committedQty = committed;
		return r;
	}

	private static NetSuiteInventorySyncService.SyncRequest request(List<NetSuiteInventorySyncService.InventoryRow> rows) {
		NetSuiteInventorySyncService.SyncRequest req = new NetSuiteInventorySyncService.SyncRequest();
		req.runId = 'NSINV-TEST';
		req.batchNumber = 1;
		req.batchCount = 1;
		req.items = rows;
		return req;
	}

	private static Product2 product(String name) {
		return [
			SELECT Id, On_Hand__c, Committed__c, Available__c, Consignment_Stock_On_Hand__c, Non_Consignment_Stock_On_Hand__c
			FROM Product2
			WHERE Name = :name
		];
	}

	private static String key(String itemId, String locationId) {
		return NetSuiteInventorySyncService.buildCompositeKey(itemId, locationId);
	}

	// ── resolution by External_Id__c ────────────────────────────────────

	@IsTest
	static void syncByExternalIdUpsertsRowsWithLookupsAndProductTotals() {
		Test.startTest();
		NetSuiteInventorySyncService.SyncResult result = NetSuiteInventorySyncService.sync(request(
			new List<NetSuiteInventorySyncService.InventoryRow>{
				row(ITEM_BY_ID, ITEM_BY_ID_NAME, LOC_OFFLINE, 100, 5),
				row(ITEM_BY_ID, ITEM_BY_ID_NAME, LOC_CONSIGNED, 40, 3)
			}
		));
		Test.stopTest();

		Product2 p = product('Test By Id');
		List<Inventory_Location__c> rows = [
			SELECT Composite_Key__c, Product__c, Location__r.NetSuite_ID__c, Quantity_On_Hand__c,
				NetSuite_Item_ID__c, NetSuite_Location_ID__c
			FROM Inventory_Location__c
			ORDER BY Quantity_On_Hand__c DESC
		];

		Assert.areEqual(Constants.INTEGRATION_STATUS_PROCESSED, result.status);
		Assert.areEqual(2, result.rowsReceived);
		Assert.areEqual(2, result.rowsUpserted);
		Assert.areEqual(0, result.rowsSkipped);
		Assert.areEqual(1, result.productsCommittedUpdated);

		Assert.areEqual(2, rows.size());
		Assert.areEqual(key(ITEM_BY_ID, LOC_OFFLINE), rows[0].Composite_Key__c);
		Assert.areEqual(p.Id, rows[0].Product__c, 'Product__c is resolved from External_Id__c');
		Assert.areEqual(LOC_OFFLINE, rows[0].Location__r.NetSuite_ID__c, 'Location__c is resolved from NetSuite_ID__c');
		Assert.areEqual(ITEM_BY_ID, rows[0].NetSuite_Item_ID__c);
		Assert.areEqual(LOC_OFFLINE, rows[0].NetSuite_Location_ID__c);

		Assert.areEqual(140, p.On_Hand__c, 'On hand is rolled up by the Inventory_Location__c trigger');
		Assert.areEqual(40, p.Consignment_Stock_On_Hand__c);
		Assert.areEqual(100, p.Non_Consignment_Stock_On_Hand__c);
		Assert.areEqual(8, p.Committed__c, 'Committed is the sum of committedQty across locations');
		Assert.areEqual(132, p.Available__c);
	}

	@IsTest
	static void syncRerunOverwritesQuantitiesWithoutDuplicatingRows() {
		NetSuiteInventorySyncService.sync(request(new List<NetSuiteInventorySyncService.InventoryRow>{
			row(ITEM_BY_ID, ITEM_BY_ID_NAME, LOC_OFFLINE, 100, 5),
			row(ITEM_BY_ID, ITEM_BY_ID_NAME, LOC_CONSIGNED, 40, 3)
		}));

		Test.startTest();
		NetSuiteInventorySyncService.sync(request(new List<NetSuiteInventorySyncService.InventoryRow>{
			row(ITEM_BY_ID, ITEM_BY_ID_NAME, LOC_OFFLINE, 0, 0),
			row(ITEM_BY_ID, ITEM_BY_ID_NAME, LOC_CONSIGNED, 25, 0)
		}));
		Test.stopTest();

		Product2 p = product('Test By Id');
		Assert.areEqual(2, [SELECT COUNT() FROM Inventory_Location__c], 'Upsert by Composite_Key__c must not duplicate rows');
		Assert.areEqual(25, p.On_Hand__c, 'Zero rows in the full snapshot clear stock that is gone');
		Assert.areEqual(25, p.Consignment_Stock_On_Hand__c);
		Assert.areEqual(0, p.Committed__c);
	}

	@IsTest
	static void syncWithoutCommittedQtyLeavesCommittedUntouched() {
		Product2 before = product('Test By Id');
		update new Product2(Id = before.Id, Committed__c = 77);

		Test.startTest();
		NetSuiteInventorySyncService.SyncResult result = NetSuiteInventorySyncService.sync(request(
			new List<NetSuiteInventorySyncService.InventoryRow>{ row(ITEM_BY_ID, ITEM_BY_ID_NAME, LOC_OFFLINE, 10, null) }
		));
		Test.stopTest();

		Assert.areEqual(0, result.productsCommittedUpdated);
		Assert.areEqual(77, product('Test By Id').Committed__c);
	}

	@IsTest
	static void syncNullOnHandDefaultsToZero() {
		NetSuiteInventorySyncService.sync(request(
			new List<NetSuiteInventorySyncService.InventoryRow>{ row(ITEM_BY_ID, ITEM_BY_ID_NAME, LOC_OFFLINE, null, 0) }
		));

		Assert.areEqual(0, [SELECT Quantity_On_Hand__c FROM Inventory_Location__c].Quantity_On_Hand__c);
	}

	// ── name fallback ───────────────────────────────────────────────────

	@IsTest
	static void syncFallsBackToProductNameExternalCaseInsensitively() {
		Test.startTest();
		NetSuiteInventorySyncService.SyncResult result = NetSuiteInventorySyncService.sync(request(
			new List<NetSuiteInventorySyncService.InventoryRow>{
				row(ITEM_BY_NAME, ITEM_BY_NAME_NAME.toLowerCase(), LOC_OFFLINE, 7, 2)
			}
		));
		Test.stopTest();

		Product2 p = product('Test By Name');
		Assert.areEqual(Constants.INTEGRATION_STATUS_PROCESSED, result.status);
		Assert.areEqual(1, result.rowsUpserted);
		Assert.areEqual(1, result.resolvedByName.size(), 'Name matches are reported so External_Id__c can be fixed');
		Assert.isTrue(result.resolvedByName[0].contains(ITEM_BY_NAME));
		Assert.isTrue(result.resolvedByName[0].contains('External_Id__c = blank'));
		Assert.areEqual(p.Id, [SELECT Product__c FROM Inventory_Location__c].Product__c);
		Assert.areEqual(7, p.On_Hand__c);
		Assert.areEqual(2, p.Committed__c);
	}

	@IsTest
	static void syncRejectsNameMatchOnProductAlreadyMatchedById() {
		Test.startTest();
		NetSuiteInventorySyncService.SyncResult result = NetSuiteInventorySyncService.sync(request(
			new List<NetSuiteInventorySyncService.InventoryRow>{
				row(ITEM_CONFLICT_OWNER, 'Owner', LOC_OFFLINE, 10, 0),
				row('TNS-ITEM-OTHER', CONFLICT_NAME, LOC_OFFLINE, 999, 0)
			}
		));
		Test.stopTest();

		Assert.areEqual(Constants.INTEGRATION_STATUS_PARTIALLY_PROCESSED, result.status);
		Assert.areEqual(1, result.rowsUpserted);
		Assert.areEqual(1, result.rowsSkipped);
		Assert.isTrue(result.skipped[0].contains('TNS-ITEM-OTHER'));
		Assert.isTrue(result.skipped[0].contains('already matched by External_Id__c'));
		Assert.areEqual(10, product('Test Conflict Owner').On_Hand__c, 'The other item must not add its stock');
	}

	// ── unresolved rows ─────────────────────────────────────────────────

	@IsTest
	static void syncSkipsUnknownProductWithoutWritingOrphans() {
		Test.startTest();
		NetSuiteInventorySyncService.SyncResult result = NetSuiteInventorySyncService.sync(request(
			new List<NetSuiteInventorySyncService.InventoryRow>{
				row(ITEM_UNKNOWN, 'TEST-SKU-UNKNOWN', LOC_OFFLINE, 5, 1),
				row(ITEM_UNKNOWN, 'TEST-SKU-UNKNOWN', LOC_CONSIGNED, 6, 0)
			}
		));
		Test.stopTest();

		Assert.areEqual(Constants.INTEGRATION_STATUS_FAILED, result.status, 'Nothing in the batch could be applied');
		Assert.areEqual(0, [SELECT COUNT() FROM Inventory_Location__c], 'No orphan Inventory_Location__c rows');
		Assert.areEqual(2, result.rowsSkipped);
		Assert.areEqual(1, result.skipped.size(), 'One line per unresolved item, not per location');
		Assert.isTrue(result.skipped[0].contains(ITEM_UNKNOWN));
		Assert.isTrue(result.skipped[0].contains('TEST-SKU-UNKNOWN'));
		Assert.isTrue(result.skipped[0].contains('(2 rows skipped)'));
	}

	@IsTest
	static void syncMixedBatchIsPartiallyProcessed() {
		Test.startTest();
		NetSuiteInventorySyncService.SyncResult result = NetSuiteInventorySyncService.sync(request(
			new List<NetSuiteInventorySyncService.InventoryRow>{
				row(ITEM_BY_ID, ITEM_BY_ID_NAME, LOC_OFFLINE, 10, 1),
				row(ITEM_UNKNOWN, 'TEST-SKU-UNKNOWN', LOC_OFFLINE, 5, 1)
			}
		));
		Test.stopTest();

		Assert.areEqual(Constants.INTEGRATION_STATUS_PARTIALLY_PROCESSED, result.status);
		Assert.areEqual(1, result.rowsUpserted);
		Assert.areEqual(1, result.rowsSkipped);
		Assert.areEqual(10, product('Test By Id').On_Hand__c);
	}

	@IsTest
	static void syncSkipsUnknownLocationButStillCountsItsCommitted() {
		Test.startTest();
		NetSuiteInventorySyncService.SyncResult result = NetSuiteInventorySyncService.sync(request(
			new List<NetSuiteInventorySyncService.InventoryRow>{
				row(ITEM_BY_ID, ITEM_BY_ID_NAME, LOC_OFFLINE, 10, 1),
				row(ITEM_BY_ID, ITEM_BY_ID_NAME, LOC_UNKNOWN, 50, 4)
			}
		));
		Test.stopTest();

		Assert.areEqual(Constants.INTEGRATION_STATUS_PARTIALLY_PROCESSED, result.status);
		Assert.areEqual(1, result.rowsUpserted);
		Assert.areEqual(1, result.rowsSkipped);
		Assert.isTrue(result.skipped[0].contains(LOC_UNKNOWN));
		Assert.areEqual(1, [SELECT COUNT() FROM Inventory_Location__c]);
		Product2 p = product('Test By Id');
		Assert.areEqual(10, p.On_Hand__c);
		Assert.areEqual(5, p.Committed__c, 'Committed is item-level and includes the unresolved location');
	}

	@IsTest
	static void syncSkipsBlankIdsAndCollapsesDuplicateRows() {
		Test.startTest();
		NetSuiteInventorySyncService.SyncResult result = NetSuiteInventorySyncService.sync(request(
			new List<NetSuiteInventorySyncService.InventoryRow>{
				row('', ITEM_BY_ID_NAME, LOC_OFFLINE, 1, 1),
				row(ITEM_BY_ID, ITEM_BY_ID_NAME, null, 1, 1),
				null,
				row(ITEM_BY_ID, ITEM_BY_ID_NAME, LOC_OFFLINE, 10, 2),
				row(' ' + ITEM_BY_ID + ' ', ITEM_BY_ID_NAME, LOC_OFFLINE, 20, 3)
			}
		));
		Test.stopTest();

		Assert.areEqual(5, result.rowsReceived);
		Assert.areEqual(4, result.rowsSkipped, '3 rows without ids + 1 replaced duplicate');
		Assert.areEqual(1, result.rowsUpserted);
		Product2 p = product('Test By Id');
		Assert.areEqual(20, p.On_Hand__c, 'The last duplicate row wins');
		Assert.areEqual(3, p.Committed__c, 'A duplicate row must not double-count committed');
	}

	// ── bulk ────────────────────────────────────────────────────────────

	@IsTest
	static void syncFullBatchOf50ItemsAcross12Locations() {
		List<Warehouse_Location__c> locations = new List<Warehouse_Location__c>();
		for (Integer l = 1; l <= BULK_LOCATIONS; l++) {
			locations.add(new Warehouse_Location__c(
				Name = 'Bulk Location ' + l,
				NetSuite_ID__c = 'TNS-BULK-LOC-' + l,
				Type__c = Math.mod(l, 4) == 0 ? Constants.WAREHOUSE_LOCATION_TYPE_CONSIGNED : 'Offline'
			));
		}
		insert locations;

		List<Product2> products = new List<Product2>();
		for (Integer i = 1; i <= BULK_ITEMS; i++) {
			products.add(new Product2(Name = 'Bulk Product ' + i, External_Id__c = 'TNS-BULK-ITEM-' + i));
		}
		insert products;

		List<NetSuiteInventorySyncService.InventoryRow> rows = new List<NetSuiteInventorySyncService.InventoryRow>();
		for (Integer i = 1; i <= BULK_ITEMS; i++) {
			for (Integer l = 1; l <= BULK_LOCATIONS; l++) {
				rows.add(row('TNS-BULK-ITEM-' + i, 'BULK-SKU-' + i, 'TNS-BULK-LOC-' + l, l, 1));
			}
		}

		Test.startTest();
		NetSuiteInventorySyncService.SyncResult result = NetSuiteInventorySyncService.sync(request(rows));
		Test.stopTest();

		Assert.areEqual(Constants.INTEGRATION_STATUS_PROCESSED, result.status);
		Assert.areEqual(BULK_ITEMS * BULK_LOCATIONS, result.rowsUpserted);
		Assert.areEqual(BULK_ITEMS, result.productsCommittedUpdated);

		// On hand per product = 1 + 2 + ... + 12 = 78; consigned locations 4, 8, 12 = 24.
		for (Product2 p : [
			SELECT On_Hand__c, Consignment_Stock_On_Hand__c, Committed__c
			FROM Product2
			WHERE External_Id__c LIKE 'TNS-BULK-ITEM-%'
		]) {
			Assert.areEqual(78, p.On_Hand__c);
			Assert.areEqual(24, p.Consignment_Stock_On_Hand__c);
			Assert.areEqual(BULK_LOCATIONS, p.Committed__c);
		}
	}
}
