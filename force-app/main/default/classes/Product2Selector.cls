public inherited sharing class Product2Selector {

	public static List<Product2> getProductsByExternalIds(Set<String> externalIds) {
		return [
			SELECT
				Id,
				Committed__c,
				External_Id__c
			FROM Product2
			WHERE External_Id__c IN :externalIds
		];
	}

	public static Product2 getProductByExternalId(String externalId) {
		List<Product2> products = getProductsByExternalIds(new Set<String>{ externalId });
		return products.isEmpty() ? null : products[0];
	}
}
