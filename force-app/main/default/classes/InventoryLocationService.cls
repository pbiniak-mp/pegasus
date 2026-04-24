public with sharing class InventoryLocationService {
	private static final String CLASS_NAME = 'InventoryLocationService';
	private static final String ERR_UPDATE_PRODUCTS = 'Failed to update Product2 On Hand totals from Inventory Locations';

	public static Set<Id> collectAffectedProductIds(
		List<Inventory_Location__c> newList,
		Map<Id, Inventory_Location__c> oldMap
	) {
		Set<Id> productIds = new Set<Id>();
		Boolean isInsert = oldMap == null && newList != null;
		Boolean isDelete = newList == null && oldMap != null;

		if (isInsert) {
			for (Inventory_Location__c il : newList) {
				if (il.Product__c != null) {
					productIds.add(il.Product__c);
				}
			}
			return productIds;
		}

		if (isDelete) {
			for (Inventory_Location__c il : oldMap.values()) {
				if (il.Product__c != null) {
					productIds.add(il.Product__c);
				}
			}
			return productIds;
		}

		for (Inventory_Location__c il : newList) {
			Inventory_Location__c oldIl = oldMap.get(il.Id);
			Boolean qtyChanged = oldIl.Quantity_On_Hand__c != il.Quantity_On_Hand__c;
			Boolean productChanged = oldIl.Product__c != il.Product__c;
			Boolean locationChanged = oldIl.Location__c != il.Location__c;

			if (qtyChanged || productChanged || locationChanged) {
				if (il.Product__c != null) {
					productIds.add(il.Product__c);
				}
				if (productChanged && oldIl.Product__c != null) {
					productIds.add(oldIl.Product__c);
				}
			}
		}
		return productIds;
	}

	public static void recalculateProductOnHand(Set<Id> productIds) {
		if (productIds == null || productIds.isEmpty()) return;

		Map<Id, Decimal> totalByProduct = new Map<Id, Decimal>();
		Map<Id, Decimal> consignedByProduct = new Map<Id, Decimal>();
		for (Id productId : productIds) {
			totalByProduct.put(productId, Constants.INVENTORY_LOCATION_DEFAULT_ON_HAND);
			consignedByProduct.put(productId, Constants.INVENTORY_LOCATION_DEFAULT_ON_HAND);
		}

		for (Inventory_Location__c il : InventoryLocationSelector.getByProductIds(productIds)) {
			Decimal qty = il.Quantity_On_Hand__c != null
				? il.Quantity_On_Hand__c
				: Constants.INVENTORY_LOCATION_DEFAULT_ON_HAND;

			totalByProduct.put(il.Product__c, totalByProduct.get(il.Product__c) + qty);

			String locationType = il.Location__r != null ? il.Location__r.Type__c : null;
			if (locationType == Constants.WAREHOUSE_LOCATION_TYPE_CONSIGNED) {
				consignedByProduct.put(il.Product__c, consignedByProduct.get(il.Product__c) + qty);
			}
		}

		List<Product2> toUpdate = new List<Product2>();
		for (Id productId : productIds) {
			toUpdate.add(new Product2(
				Id = productId,
				On_Hand__c = totalByProduct.get(productId),
				Consignment_Stock_On_Hand__c = consignedByProduct.get(productId)
			));
		}

		try {
			update toUpdate;
		} catch (Exception e) {
			BoltErrorLogger.logError(
				CLASS_NAME,
				'recalculateProductOnHand',
				ERR_UPDATE_PRODUCTS + ': ' + e.getMessage(),
				e.getStackTraceString(),
				Constants.SOURCE_TYPE_APEX,
				Constants.SEVERITY_ERROR,
				UserInfo.getUserId(),
				null
			);
			throw e;
		}
	}
}
