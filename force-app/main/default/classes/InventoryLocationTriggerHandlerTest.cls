@IsTest
private class InventoryLocationTriggerHandlerTest {

	private static final String PROD_NAME_A = 'ILTH Test Product A';
	private static final String PROD_NAME_B = 'ILTH Test Product B';
	private static final String WH_OFFLINE_NAME = 'ILTH Offline WH';
	private static final String WH_CONSIGNED_NAME = 'ILTH Consigned WH';
	private static final Integer BULK_SIZE = 200;

	@TestSetup
	static void setup() {
		insert new List<Product2>{
			new Product2(Name = PROD_NAME_A),
			new Product2(Name = PROD_NAME_B)
		};

		insert new List<Warehouse_Location__c>{
			new Warehouse_Location__c(Name = WH_OFFLINE_NAME, Type__c = 'Offline'),
			new Warehouse_Location__c(Name = WH_CONSIGNED_NAME, Type__c = Constants.WAREHOUSE_LOCATION_TYPE_CONSIGNED)
		};
	}

	private static Product2 getProduct(String name) {
		return [SELECT Id FROM Product2 WHERE Name = :name LIMIT 1];
	}

	private static Warehouse_Location__c getWarehouse(String name) {
		return [SELECT Id FROM Warehouse_Location__c WHERE Name = :name LIMIT 1];
	}

	private static Product2 reloadProduct(Id productId) {
		return [SELECT On_Hand__c, Consignment_Stock_On_Hand__c FROM Product2 WHERE Id = :productId];
	}

	// ── afterInsert ─────────────────────────────────────────────────────

	@IsTest
	static void testAfterInsert_singleRecord_updatesProduct() {
		Id productId = getProduct(PROD_NAME_A).Id;
		Id whConsignedId = getWarehouse(WH_CONSIGNED_NAME).Id;

		Test.startTest();
		insert new Inventory_Location__c(
			Product__c = productId,
			Location__c = whConsignedId,
			Quantity_On_Hand__c = 12
		);
		Test.stopTest();

		Product2 p = reloadProduct(productId);
		Assert.areEqual(12, p.On_Hand__c);
		Assert.areEqual(12, p.Consignment_Stock_On_Hand__c);
	}

	@IsTest
	static void testAfterInsert_mixedConsignedAndOffline_splitsSums() {
		Id productId = getProduct(PROD_NAME_A).Id;
		Id whOfflineId = getWarehouse(WH_OFFLINE_NAME).Id;
		Id whConsignedId = getWarehouse(WH_CONSIGNED_NAME).Id;

		Test.startTest();
		insert new List<Inventory_Location__c>{
			new Inventory_Location__c(Product__c = productId, Location__c = whOfflineId, Quantity_On_Hand__c = 6),
			new Inventory_Location__c(Product__c = productId, Location__c = whConsignedId, Quantity_On_Hand__c = 4),
			new Inventory_Location__c(Product__c = productId, Location__c = whConsignedId, Quantity_On_Hand__c = 3)
		};
		Test.stopTest();

		Product2 p = reloadProduct(productId);
		Assert.areEqual(13, p.On_Hand__c);
		Assert.areEqual(7, p.Consignment_Stock_On_Hand__c);
	}

	// ── afterUpdate ─────────────────────────────────────────────────────

	@IsTest
	static void testAfterUpdate_quantityChange_recalculatesProduct() {
		Id productId = getProduct(PROD_NAME_A).Id;
		Id whConsignedId = getWarehouse(WH_CONSIGNED_NAME).Id;
		Inventory_Location__c il = new Inventory_Location__c(
			Product__c = productId,
			Location__c = whConsignedId,
			Quantity_On_Hand__c = 5
		);
		insert il;

		Test.startTest();
		il.Quantity_On_Hand__c = 20;
		update il;
		Test.stopTest();

		Product2 p = reloadProduct(productId);
		Assert.areEqual(20, p.On_Hand__c);
		Assert.areEqual(20, p.Consignment_Stock_On_Hand__c);
	}

	@IsTest
	static void testAfterUpdate_productReassigned_recalculatesBothProducts() {
		Id productAId = getProduct(PROD_NAME_A).Id;
		Id productBId = getProduct(PROD_NAME_B).Id;
		Id whConsignedId = getWarehouse(WH_CONSIGNED_NAME).Id;
		Inventory_Location__c il = new Inventory_Location__c(
			Product__c = productAId,
			Location__c = whConsignedId,
			Quantity_On_Hand__c = 9
		);
		insert il;

		Test.startTest();
		il.Product__c = productBId;
		update il;
		Test.stopTest();

		Product2 pA = reloadProduct(productAId);
		Product2 pB = reloadProduct(productBId);
		Assert.areEqual(0, pA.On_Hand__c, 'Old product should drop to zero');
		Assert.areEqual(0, pA.Consignment_Stock_On_Hand__c);
		Assert.areEqual(9, pB.On_Hand__c);
		Assert.areEqual(9, pB.Consignment_Stock_On_Hand__c);
	}

	@IsTest
	static void testAfterUpdate_locationChangedOfflineToConsigned_movesConsignmentBalance() {
		Id productId = getProduct(PROD_NAME_A).Id;
		Id whOfflineId = getWarehouse(WH_OFFLINE_NAME).Id;
		Id whConsignedId = getWarehouse(WH_CONSIGNED_NAME).Id;
		Inventory_Location__c il = new Inventory_Location__c(
			Product__c = productId,
			Location__c = whOfflineId,
			Quantity_On_Hand__c = 10
		);
		insert il;

		Product2 before = reloadProduct(productId);
		Assert.areEqual(10, before.On_Hand__c);
		Assert.areEqual(0, before.Consignment_Stock_On_Hand__c);

		Test.startTest();
		il.Location__c = whConsignedId;
		update il;
		Test.stopTest();

		Product2 updated = reloadProduct(productId);
		Assert.areEqual(10, updated.On_Hand__c);
		Assert.areEqual(10, updated.Consignment_Stock_On_Hand__c);
	}

	// ── afterDelete ─────────────────────────────────────────────────────

	@IsTest
	static void testAfterDelete_recalculatesRemainingTotal() {
		Id productId = getProduct(PROD_NAME_A).Id;
		Id whConsignedId = getWarehouse(WH_CONSIGNED_NAME).Id;
		Inventory_Location__c il1 = new Inventory_Location__c(Product__c = productId, Location__c = whConsignedId, Quantity_On_Hand__c = 4);
		Inventory_Location__c il2 = new Inventory_Location__c(Product__c = productId, Location__c = whConsignedId, Quantity_On_Hand__c = 6);
		insert new List<Inventory_Location__c>{ il1, il2 };

		Test.startTest();
		delete il2;
		Test.stopTest();

		Product2 p = reloadProduct(productId);
		Assert.areEqual(4, p.On_Hand__c);
		Assert.areEqual(4, p.Consignment_Stock_On_Hand__c);
	}

	// ── afterUndelete ───────────────────────────────────────────────────

	@IsTest
	static void testAfterUndelete_recalculatesAfterRestore() {
		Id productId = getProduct(PROD_NAME_A).Id;
		Id whConsignedId = getWarehouse(WH_CONSIGNED_NAME).Id;
		Inventory_Location__c il = new Inventory_Location__c(
			Product__c = productId,
			Location__c = whConsignedId,
			Quantity_On_Hand__c = 8
		);
		insert il;
		delete il;

		Test.startTest();
		undelete il;
		Test.stopTest();

		Product2 p = reloadProduct(productId);
		Assert.areEqual(8, p.On_Hand__c);
		Assert.areEqual(8, p.Consignment_Stock_On_Hand__c);
	}

	// ── irrelevant update ───────────────────────────────────────────────

	@IsTest
	static void testAfterUpdate_irrelevantChange_doesNotAlterProductTotals() {
		Id productId = getProduct(PROD_NAME_A).Id;
		Id whConsignedId = getWarehouse(WH_CONSIGNED_NAME).Id;
		Inventory_Location__c il = new Inventory_Location__c(
			Product__c = productId,
			Location__c = whConsignedId,
			Quantity_On_Hand__c = 7
		);
		insert il;

		Product2 initial = reloadProduct(productId);
		Assert.areEqual(7, initial.On_Hand__c);
		Assert.areEqual(7, initial.Consignment_Stock_On_Hand__c);

		Product2 manualOverride = new Product2(
			Id = productId,
			On_Hand__c = 999,
			Consignment_Stock_On_Hand__c = 999
		);
		update manualOverride;

		Test.startTest();
		il.NetSuite_Item_ID__c = 'IRRELEVANT_CHANGE';
		update il;
		Test.stopTest();

		Product2 updated = reloadProduct(productId);
		Assert.areEqual(999, updated.On_Hand__c, 'Totals should not be recomputed on irrelevant field change');
		Assert.areEqual(999, updated.Consignment_Stock_On_Hand__c);
	}

	// ── bulk ────────────────────────────────────────────────────────────

	@IsTest
	static void testBulkInsert_aggregatesAcrossManyLocations() {
		Id productId = getProduct(PROD_NAME_A).Id;
		Id whOfflineId = getWarehouse(WH_OFFLINE_NAME).Id;
		Id whConsignedId = getWarehouse(WH_CONSIGNED_NAME).Id;

		List<Inventory_Location__c> toInsert = new List<Inventory_Location__c>();
		for (Integer i = 0; i < BULK_SIZE; i++) {
			Id whId = Math.mod(i, 2) == 0 ? whOfflineId : whConsignedId;
			toInsert.add(new Inventory_Location__c(
				Product__c = productId,
				Location__c = whId,
				Quantity_On_Hand__c = 1
			));
		}

		Test.startTest();
		insert toInsert;
		Test.stopTest();

		Product2 p = reloadProduct(productId);
		Assert.areEqual(BULK_SIZE, p.On_Hand__c, 'All bulk records should contribute to On_Hand__c');
		Assert.areEqual(BULK_SIZE / 2, p.Consignment_Stock_On_Hand__c, 'Only Consigned half should contribute to Consignment');
	}

	@IsTest
	static void testBulkUpdate_acrossMultipleProducts() {
		Id productAId = getProduct(PROD_NAME_A).Id;
		Id productBId = getProduct(PROD_NAME_B).Id;
		Id whConsignedId = getWarehouse(WH_CONSIGNED_NAME).Id;

		List<Inventory_Location__c> seeds = new List<Inventory_Location__c>();
		for (Integer i = 0; i < 100; i++) {
			seeds.add(new Inventory_Location__c(Product__c = productAId, Location__c = whConsignedId, Quantity_On_Hand__c = 1));
		}
		for (Integer i = 0; i < 100; i++) {
			seeds.add(new Inventory_Location__c(Product__c = productBId, Location__c = whConsignedId, Quantity_On_Hand__c = 1));
		}
		insert seeds;

		Test.startTest();
		for (Inventory_Location__c il : seeds) {
			il.Quantity_On_Hand__c = 2;
		}
		update seeds;
		Test.stopTest();

		Map<Id, Product2> byId = new Map<Id, Product2>(
			[SELECT Id, On_Hand__c, Consignment_Stock_On_Hand__c FROM Product2 WHERE Id IN :new List<Id>{ productAId, productBId }]
		);
		Assert.areEqual(200, byId.get(productAId).On_Hand__c);
		Assert.areEqual(200, byId.get(productAId).Consignment_Stock_On_Hand__c);
		Assert.areEqual(200, byId.get(productBId).On_Hand__c);
		Assert.areEqual(200, byId.get(productBId).Consignment_Stock_On_Hand__c);
	}

	// ── null Product__c ─────────────────────────────────────────────────

	@IsTest
	static void testAfterInsert_nullProduct_noRecalcAttempted() {
		Id whConsignedId = getWarehouse(WH_CONSIGNED_NAME).Id;

		Test.startTest();
		insert new Inventory_Location__c(
			Product__c = null,
			Location__c = whConsignedId,
			Quantity_On_Hand__c = 5
		);
		Test.stopTest();

		List<Product2> all = [SELECT On_Hand__c, Consignment_Stock_On_Hand__c FROM Product2];
		for (Product2 p : all) {
			Assert.isTrue(p.On_Hand__c == null || p.On_Hand__c == 0);
			Assert.isTrue(p.Consignment_Stock_On_Hand__c == null || p.Consignment_Stock_On_Hand__c == 0);
		}
	}
}
