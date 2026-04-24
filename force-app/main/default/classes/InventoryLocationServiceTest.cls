@IsTest
private class InventoryLocationServiceTest {

	private static final String PROD_NAME_A = 'IL Test Product A';
	private static final String PROD_NAME_B = 'IL Test Product B';
	private static final String WH_OFFLINE_NAME = 'IL Test Offline WH';
	private static final String WH_CONSIGNED_NAME = 'IL Test Consigned WH';

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
		return [SELECT Id, Type__c FROM Warehouse_Location__c WHERE Name = :name LIMIT 1];
	}

	private static Inventory_Location__c insertLocation(Id productId, Id warehouseId, Decimal qty) {
		TriggerHandler.bypass(Constants.INVENTORY_LOCATION_HANDLER_NAME);
		try {
			Inventory_Location__c il = new Inventory_Location__c(
				Product__c = productId,
				Location__c = warehouseId,
				Quantity_On_Hand__c = qty
			);
			insert il;
			return il;
		} finally {
			TriggerHandler.clearBypass(Constants.INVENTORY_LOCATION_HANDLER_NAME);
		}
	}

	// ── collectAffectedProductIds ───────────────────────────────────────

	@IsTest
	static void testCollectAffectedProductIds_insert_gathersNonNullProducts() {
		Id productId = getProduct(PROD_NAME_A).Id;
		List<Inventory_Location__c> newList = new List<Inventory_Location__c>{
			new Inventory_Location__c(Product__c = productId, Quantity_On_Hand__c = 5),
			new Inventory_Location__c(Product__c = null, Quantity_On_Hand__c = 2)
		};

		Set<Id> result = InventoryLocationService.collectAffectedProductIds(newList, null);

		Assert.areEqual(1, result.size(), 'Only non-null Product__c should be collected on insert');
		Assert.isTrue(result.contains(productId), 'Product A should be present');
	}

	@IsTest
	static void testCollectAffectedProductIds_delete_gathersNonNullProducts() {
		Id productAId = getProduct(PROD_NAME_A).Id;
		Id warehouseId = getWarehouse(WH_OFFLINE_NAME).Id;

		Inventory_Location__c il1 = insertLocation(productAId, warehouseId, 3);
		Inventory_Location__c il2 = insertLocation(null, warehouseId, 7);

		Map<Id, Inventory_Location__c> oldMap = new Map<Id, Inventory_Location__c>(
			[SELECT Id, Product__c FROM Inventory_Location__c WHERE Id IN :new List<Id>{ il1.Id, il2.Id }]
		);

		Set<Id> result = InventoryLocationService.collectAffectedProductIds(null, oldMap);

		Assert.areEqual(1, result.size(), 'Only non-null Product__c should be collected on delete');
		Assert.isTrue(result.contains(productAId), 'Product A should be present');
	}

	@IsTest
	static void testCollectAffectedProductIds_update_quantityChanged() {
		Id productAId = getProduct(PROD_NAME_A).Id;
		Id warehouseId = getWarehouse(WH_OFFLINE_NAME).Id;
		Inventory_Location__c il = insertLocation(productAId, warehouseId, 10);

		Map<Id, Inventory_Location__c> oldMap = new Map<Id, Inventory_Location__c>{
			il.Id => new Inventory_Location__c(Id = il.Id, Product__c = productAId, Location__c = warehouseId, Quantity_On_Hand__c = 10)
		};
		List<Inventory_Location__c> newList = new List<Inventory_Location__c>{
			new Inventory_Location__c(Id = il.Id, Product__c = productAId, Location__c = warehouseId, Quantity_On_Hand__c = 20)
		};

		Set<Id> result = InventoryLocationService.collectAffectedProductIds(newList, oldMap);

		Assert.areEqual(1, result.size());
		Assert.isTrue(result.contains(productAId));
	}

	@IsTest
	static void testCollectAffectedProductIds_update_productChanged_collectsOldAndNew() {
		Id productAId = getProduct(PROD_NAME_A).Id;
		Id productBId = getProduct(PROD_NAME_B).Id;
		Id warehouseId = getWarehouse(WH_OFFLINE_NAME).Id;
		Inventory_Location__c il = insertLocation(productAId, warehouseId, 5);

		Map<Id, Inventory_Location__c> oldMap = new Map<Id, Inventory_Location__c>{
			il.Id => new Inventory_Location__c(Id = il.Id, Product__c = productAId, Location__c = warehouseId, Quantity_On_Hand__c = 5)
		};
		List<Inventory_Location__c> newList = new List<Inventory_Location__c>{
			new Inventory_Location__c(Id = il.Id, Product__c = productBId, Location__c = warehouseId, Quantity_On_Hand__c = 5)
		};

		Set<Id> result = InventoryLocationService.collectAffectedProductIds(newList, oldMap);

		Assert.areEqual(2, result.size(), 'Both old and new product should be collected on product reassignment');
		Assert.isTrue(result.contains(productAId));
		Assert.isTrue(result.contains(productBId));
	}

	@IsTest
	static void testCollectAffectedProductIds_update_locationChanged() {
		Id productAId = getProduct(PROD_NAME_A).Id;
		Id whOfflineId = getWarehouse(WH_OFFLINE_NAME).Id;
		Id whConsignedId = getWarehouse(WH_CONSIGNED_NAME).Id;
		Inventory_Location__c il = insertLocation(productAId, whOfflineId, 5);

		Map<Id, Inventory_Location__c> oldMap = new Map<Id, Inventory_Location__c>{
			il.Id => new Inventory_Location__c(Id = il.Id, Product__c = productAId, Location__c = whOfflineId, Quantity_On_Hand__c = 5)
		};
		List<Inventory_Location__c> newList = new List<Inventory_Location__c>{
			new Inventory_Location__c(Id = il.Id, Product__c = productAId, Location__c = whConsignedId, Quantity_On_Hand__c = 5)
		};

		Set<Id> result = InventoryLocationService.collectAffectedProductIds(newList, oldMap);

		Assert.areEqual(1, result.size());
		Assert.isTrue(result.contains(productAId));
	}

	@IsTest
	static void testCollectAffectedProductIds_update_noRelevantChange_returnsEmpty() {
		Id productAId = getProduct(PROD_NAME_A).Id;
		Id warehouseId = getWarehouse(WH_OFFLINE_NAME).Id;
		Inventory_Location__c il = insertLocation(productAId, warehouseId, 5);

		Map<Id, Inventory_Location__c> oldMap = new Map<Id, Inventory_Location__c>{
			il.Id => new Inventory_Location__c(Id = il.Id, Product__c = productAId, Location__c = warehouseId, Quantity_On_Hand__c = 5)
		};
		List<Inventory_Location__c> newList = new List<Inventory_Location__c>{
			new Inventory_Location__c(Id = il.Id, Product__c = productAId, Location__c = warehouseId, Quantity_On_Hand__c = 5)
		};

		Set<Id> result = InventoryLocationService.collectAffectedProductIds(newList, oldMap);

		Assert.isTrue(result.isEmpty(), 'No relevant field change should result in empty set');
	}

	// ── recalculateProductOnHand ────────────────────────────────────────

	@IsTest
	static void testRecalculate_sumsAllIntoOnHand_andConsignedOnlyIntoConsignment() {
		Id productAId = getProduct(PROD_NAME_A).Id;
		Id whOfflineId = getWarehouse(WH_OFFLINE_NAME).Id;
		Id whConsignedId = getWarehouse(WH_CONSIGNED_NAME).Id;

		insertLocation(productAId, whOfflineId, 7);
		insertLocation(productAId, whConsignedId, 3);
		insertLocation(productAId, whConsignedId, 5);

		Test.startTest();
		InventoryLocationService.recalculateProductOnHand(new Set<Id>{ productAId });
		Test.stopTest();

		Product2 p = [SELECT On_Hand__c, Consignment_Stock_On_Hand__c FROM Product2 WHERE Id = :productAId];
		Assert.areEqual(15, p.On_Hand__c, 'On_Hand__c should sum all locations');
		Assert.areEqual(8, p.Consignment_Stock_On_Hand__c, 'Consignment_Stock_On_Hand__c should sum only Consigned locations');
	}

	@IsTest
	static void testRecalculate_productWithNoInventory_setsZero() {
		Id productAId = getProduct(PROD_NAME_A).Id;

		Test.startTest();
		InventoryLocationService.recalculateProductOnHand(new Set<Id>{ productAId });
		Test.stopTest();

		Product2 p = [SELECT On_Hand__c, Consignment_Stock_On_Hand__c FROM Product2 WHERE Id = :productAId];
		Assert.areEqual(0, p.On_Hand__c);
		Assert.areEqual(0, p.Consignment_Stock_On_Hand__c);
	}

	@IsTest
	static void testRecalculate_nullLocation_addsToOnHandNotConsignment() {
		Id productAId = getProduct(PROD_NAME_A).Id;
		insertLocation(productAId, null, 4);

		Test.startTest();
		InventoryLocationService.recalculateProductOnHand(new Set<Id>{ productAId });
		Test.stopTest();

		Product2 p = [SELECT On_Hand__c, Consignment_Stock_On_Hand__c FROM Product2 WHERE Id = :productAId];
		Assert.areEqual(4, p.On_Hand__c);
		Assert.areEqual(0, p.Consignment_Stock_On_Hand__c, 'Null Location should not count toward Consignment');
	}

	@IsTest
	static void testRecalculate_nullQuantity_treatedAsZero() {
		Id productAId = getProduct(PROD_NAME_A).Id;
		Id whConsignedId = getWarehouse(WH_CONSIGNED_NAME).Id;
		insertLocation(productAId, whConsignedId, null);
		insertLocation(productAId, whConsignedId, 6);

		Test.startTest();
		InventoryLocationService.recalculateProductOnHand(new Set<Id>{ productAId });
		Test.stopTest();

		Product2 p = [SELECT On_Hand__c, Consignment_Stock_On_Hand__c FROM Product2 WHERE Id = :productAId];
		Assert.areEqual(6, p.On_Hand__c);
		Assert.areEqual(6, p.Consignment_Stock_On_Hand__c);
	}

	@IsTest
	static void testRecalculate_nullSet_isNoOp() {
		Test.startTest();
		Integer dmlBefore = Limits.getDmlStatements();
		InventoryLocationService.recalculateProductOnHand(null);
		Integer dmlAfter = Limits.getDmlStatements();
		Test.stopTest();
		Assert.areEqual(dmlBefore, dmlAfter, 'Null set should not issue any DML');
	}

	@IsTest
	static void testRecalculate_emptySet_isNoOp() {
		Test.startTest();
		Integer dmlBefore = Limits.getDmlStatements();
		InventoryLocationService.recalculateProductOnHand(new Set<Id>());
		Integer dmlAfter = Limits.getDmlStatements();
		Test.stopTest();
		Assert.areEqual(dmlBefore, dmlAfter, 'Empty set should not issue any DML');
	}

	@IsTest
	static void testRecalculate_multipleProducts_aggregatedCorrectlyPerProduct() {
		Id productAId = getProduct(PROD_NAME_A).Id;
		Id productBId = getProduct(PROD_NAME_B).Id;
		Id whOfflineId = getWarehouse(WH_OFFLINE_NAME).Id;
		Id whConsignedId = getWarehouse(WH_CONSIGNED_NAME).Id;

		insertLocation(productAId, whOfflineId, 10);
		insertLocation(productAId, whConsignedId, 5);
		insertLocation(productBId, whConsignedId, 2);
		insertLocation(productBId, whConsignedId, 3);

		Test.startTest();
		InventoryLocationService.recalculateProductOnHand(new Set<Id>{ productAId, productBId });
		Test.stopTest();

		Map<Id, Product2> byId = new Map<Id, Product2>(
			[SELECT Id, On_Hand__c, Consignment_Stock_On_Hand__c FROM Product2 WHERE Id IN :new List<Id>{ productAId, productBId }]
		);
		Assert.areEqual(15, byId.get(productAId).On_Hand__c);
		Assert.areEqual(5, byId.get(productAId).Consignment_Stock_On_Hand__c);
		Assert.areEqual(5, byId.get(productBId).On_Hand__c);
		Assert.areEqual(5, byId.get(productBId).Consignment_Stock_On_Hand__c);
	}

	@IsTest
	static void testRecalculate_usesSingleSoqlAndSingleDml() {
		Id productAId = getProduct(PROD_NAME_A).Id;
		Id whConsignedId = getWarehouse(WH_CONSIGNED_NAME).Id;
		insertLocation(productAId, whConsignedId, 11);

		Test.startTest();
		Integer soqlBefore = Limits.getQueries();
		Integer dmlBefore = Limits.getDmlStatements();
		InventoryLocationService.recalculateProductOnHand(new Set<Id>{ productAId });
		Integer soqlAfter = Limits.getQueries();
		Integer dmlAfter = Limits.getDmlStatements();
		Test.stopTest();

		Assert.areEqual(1, soqlAfter - soqlBefore, 'Should issue exactly one SOQL');
		Assert.areEqual(1, dmlAfter - dmlBefore, 'Should issue exactly one DML');
	}
}
