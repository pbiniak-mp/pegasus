public inherited sharing class Product2Selector {

	public static List<Product2> getProductsByExternalIds(Set<String> externalIds) {
		return [
			SELECT
				Id,
				Name,
				Committed__c,
				External_Id__c,
				Product_Name_External__c
			FROM Product2
			WHERE External_Id__c IN :externalIds
		];
	}

	public static Product2 getProductByExternalId(String externalId) {
		List<Product2> products = getProductsByExternalIds(new Set<String>{ externalId });
		return products.isEmpty() ? null : products[0];
	}

	public static List<Product2> getProductsByNameExternal(Set<String> externalNames) {
		return [
			SELECT
				Id,
				Name,
				Committed__c,
				External_Id__c,
				Product_Name_External__c
			FROM Product2
			WHERE Product_Name_External__c IN :externalNames
		];
	}
}
