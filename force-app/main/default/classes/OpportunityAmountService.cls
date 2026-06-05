public with sharing class OpportunityAmountService {

	private static final String TYPE_MATERIAL = Constants.QUOTE_TYPE_MATERIAL;
	private static final String TYPE_STAMP = Constants.QUOTE_TYPE_STAMP;
	private static final String TYPE_EXTRA = Constants.QUOTE_TYPE_EXTRA;
	private static final Decimal WATTS_PER_KW = 1000;

	/**
	 * Recalculates the Apex-managed amount fields on the given Opportunities by
	 * aggregating the active Quotes under each Opportunity's active Design Revision.
	 *
	 * - Amount_Material__c / Amount_Stamp__c / Amount_Extra__c: sum of active Quote
	 *   TotalPrice grouped by Quote_Type__c.
	 * - Price_Per_Watt__c: Amount_Material__c / (active DR Project_Wattage_kW__c * 1000),
	 *   guarded against division by zero / null (set to null in that case).
	 * - Quotes_Total__c is a formula field and is not written here.
	 *
	 * Opportunities with no active Design Revision are zeroed out (amounts = 0,
	 * Price_Per_Watt__c = null).
	 *
	 * @param opportunityIds the Opportunities whose amount fields should be recalculated
	 */
	public static void recalculate(Set<Id> opportunityIds) {
		if (opportunityIds == null || opportunityIds.isEmpty()) return;

		List<Opportunity> opps = OpportunitySelector.getActiveRevisionInfoByIds(opportunityIds);

		Map<Id, Id> drIdToOppId = new Map<Id, Id>();
		Map<Id, Decimal> oppIdToWattageKw = new Map<Id, Decimal>();
		Set<Id> activeDRIds = new Set<Id>();
		for (Opportunity opp : opps) {
			if (opp.Design_Revision__c == null) continue;
			drIdToOppId.put(opp.Design_Revision__c, opp.Id);
			oppIdToWattageKw.put(opp.Id, opp.Design_Revision__r.Project_Wattage_kW__c);
			activeDRIds.add(opp.Design_Revision__c);
		}

		// Initialise amounts at zero for every requested Opportunity so that
		// Opportunities with no active DR (or no active Quotes) are zeroed out.
		Map<Id, Map<String, Decimal>> oppAmounts = new Map<Id, Map<String, Decimal>>();
		for (Id oppId : opportunityIds) {
			oppAmounts.put(oppId, new Map<String, Decimal>{
				TYPE_MATERIAL => 0,
				TYPE_STAMP => 0,
				TYPE_EXTRA => 0
			});
		}

		if (!activeDRIds.isEmpty()) {
			List<Quote> activeQuotes = QuoteSelector.getActiveQuotesByDRIds(activeDRIds);
			for (Quote q : activeQuotes) {
				Id oppId = drIdToOppId.get(q.Design_Revision__c);
				if (oppId == null) continue;
				Map<String, Decimal> amounts = oppAmounts.get(oppId);
				if (amounts == null || q.Quote_Type__c == null || !amounts.containsKey(q.Quote_Type__c)) continue;
				Decimal quoteAmt = q.TotalPrice != null ? q.TotalPrice : 0;
				amounts.put(q.Quote_Type__c, amounts.get(q.Quote_Type__c) + quoteAmt);
			}
		}

		List<Opportunity> toUpdate = new List<Opportunity>();
		for (Id oppId : opportunityIds) {
			Map<String, Decimal> amounts = oppAmounts.get(oppId);
			Decimal material = amounts.get(TYPE_MATERIAL);
			Decimal stamp = amounts.get(TYPE_STAMP);
			Decimal extra = amounts.get(TYPE_EXTRA);

			toUpdate.add(new Opportunity(
				Id = oppId,
				Amount_Material__c = material,
				Amount_Stamp__c = stamp,
				Amount_Extra__c = extra,
				Price_Per_Watt__c = calculatePricePerWatt(material, oppIdToWattageKw.get(oppId))
			));
		}

		if (toUpdate.isEmpty()) return;

		try {
			update toUpdate;
		} catch (DmlException e) {
			throw e;
		} catch (Exception e) {
			throw e;
		}
	}

	private static Decimal calculatePricePerWatt(Decimal amountMaterial, Decimal wattageKw) {
		if (amountMaterial == null || amountMaterial == 0 || wattageKw == null || wattageKw == 0) {
			return null;
		}
		return amountMaterial / (wattageKw * WATTS_PER_KW);
	}
}
