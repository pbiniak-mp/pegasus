public with sharing class ModuleCoverageService {
	private static final String CLASS_NAME = 'ModuleCoverageService';
	private static final String ERR_UPDATE_PRODUCTS = 'Failed to update Product2 Avg SKU Per Module from Opportunity Line Items';
	private static final Integer RATIO_SCALE = 2;

	/**
	 * Recalculates Product2.Avg_SKU_Per_Module__c for the supplied products.
	 *
	 * For each product the new value is the average of OpportunityLineItem.SKU_Per_Module__c
	 * across all qualifying line items (see OpportunityLineItemSelector). Products with no
	 * qualifying line items are reset to null, so a product that loses its history is cleared.
	 * Only records whose value actually changes are updated, to avoid needless DML.
	 *
	 * The passed products MUST include the current Avg_SKU_Per_Module__c value so the change
	 * comparison is correct (the batch start query selects it).
	 */
	public static void recalculateAverageSkuPerModule(List<Product2> products) {
		if (products == null || products.isEmpty()) return;

		Map<Id, Product2> productById = new Map<Id, Product2>(products);

		Map<Id, Decimal> avgByProduct = new Map<Id, Decimal>();
		for (AggregateResult ar : OpportunityLineItemSelector.getAverageSkuPerModuleByProduct(productById.keySet())) {
			Id productId = (Id) ar.get('Product2Id');
			Decimal avgRatio = (Decimal) ar.get('avgRatio');
			if (avgRatio != null) {
				avgRatio = avgRatio.setScale(RATIO_SCALE, System.RoundingMode.HALF_UP);
			}
			avgByProduct.put(productId, avgRatio);
		}

		List<Product2> toUpdate = new List<Product2>();
		for (Product2 product : products) {
			Decimal newAvg = avgByProduct.get(product.Id); // null when no qualifying line items
			if (newAvg != product.Avg_SKU_Per_Module__c) {
				toUpdate.add(new Product2(Id = product.Id, Avg_SKU_Per_Module__c = newAvg));
			}
		}

		if (toUpdate.isEmpty()) return;

		try {
			update toUpdate;
		} catch (Exception e) {
			BoltErrorLogger.logError(
				CLASS_NAME,
				'recalculateAverageSkuPerModule',
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
