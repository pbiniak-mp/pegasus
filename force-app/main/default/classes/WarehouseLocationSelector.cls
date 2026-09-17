public inherited sharing class WarehouseLocationSelector {

	public static List<Warehouse_Location__c> getByNetSuiteIds(Set<String> netSuiteIds) {
		return [
			SELECT
				Id,
				Name,
				NetSuite_ID__c,
				Type__c
			FROM Warehouse_Location__c
			WHERE NetSuite_ID__c IN :netSuiteIds
		];
	}
}
