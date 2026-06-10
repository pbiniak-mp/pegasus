/**
 * Refreshes Product2.Avg_SKU_Per_Module__c (the denominator of Module Coverage) across the
 * whole catalogue. Iterating every Product2 keeps the field self-healing: products that gained
 * opportunity history get a value, products that lost it are reset to null. The heavy lifting
 * (aggregate query + selective update) lives in ModuleCoverageService.
 *
 * Scheduled nightly via ModuleCoverageScheduler.
 */
public with sharing class ModuleCoverageBatch implements Database.Batchable<SObject> {

	public Database.QueryLocator start(Database.BatchableContext bc) {
		return Database.getQueryLocator([
			SELECT Id, Avg_SKU_Per_Module__c
			FROM Product2
		]);
	}

	public void execute(Database.BatchableContext bc, List<Product2> scope) {
		ModuleCoverageService.recalculateAverageSkuPerModule(scope);
	}

	public void finish(Database.BatchableContext bc) {
		// No post-processing required.
	}
}
