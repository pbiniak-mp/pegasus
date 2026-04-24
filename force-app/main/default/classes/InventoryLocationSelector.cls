public inherited sharing class InventoryLocationSelector {

	public static List<Inventory_Location__c> getByProductIds(Set<Id> productIds) {
		return [
			SELECT
				Id,
				Product__c,
				Quantity_On_Hand__c,
				Location__c,
				Location__r.Type__c
			FROM Inventory_Location__c
			WHERE Product__c IN :productIds
		];
	}
}
