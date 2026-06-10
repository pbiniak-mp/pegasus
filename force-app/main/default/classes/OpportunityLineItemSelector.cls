public inherited sharing class OpportunityLineItemSelector {

	/**
	 * Average SKU-per-Module ratio grouped by Product2, for the given products.
	 * Feeds Product2.Avg_SKU_Per_Module__c, the denominator of Module Coverage.
	 *
	 * The set of opportunities that contributes to the average is defined entirely by
	 * the WHERE clause below. The Module Coverage report displays the already-averaged
	 * value and cannot re-scope it, so to limit the average (e.g. only Closed Won, or
	 * only recent opportunities) add the condition here — that is the single source of truth.
	 */
	public static List<AggregateResult> getAverageSkuPerModuleByProduct(Set<Id> productIds) {
		return [
			SELECT Product2Id, AVG(SKU_Per_Module__c) avgRatio
			FROM OpportunityLineItem
			WHERE Product2Id IN :productIds
			AND SKU_Per_Module__c != NULL
			GROUP BY Product2Id
		];
	}
}
