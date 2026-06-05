public with sharing class QuoteService {

	private static final String CLASS_NAME = 'QuoteService';
	private static final String ERR_ASSIGN_NUMBERS = 'Failed to assign Quote Numbers';
	private static final String ERR_NO_SEQUENCE = 'Quote_Sequence__c org default record not found';
	private static final String ERR_APPLY_GLOBAL_DISCOUNT = 'Failed to apply Global Discount to Quote Line Items';

	public static void applyAccountDefaultDiscount(List<Quote> newList) {
		if (newList == null || newList.isEmpty()) return;

		// The Account default discount applies to Material and Extra Quotes only.
		// Stamp Quotes must never inherit it.
		Set<Id> opportunityIds = new Set<Id>();
		for (Quote q : newList) {
			if (eligibleForAccountDiscount(q)) {
				opportunityIds.add(q.OpportunityId);
			}
		}

		if (opportunityIds.isEmpty()) return;

		Map<Id, Decimal> discountByOppId =
			QuoteSelector.getAccountDefaultDiscountByOpportunityIds(opportunityIds);
		if (discountByOppId.isEmpty()) return;

		for (Quote q : newList) {
			if (eligibleForAccountDiscount(q) && discountByOppId.containsKey(q.OpportunityId)) {
				q.Global_Discount__c = discountByOppId.get(q.OpportunityId);
			}
		}
	}

	private static Boolean eligibleForAccountDiscount(Quote q) {
		return q.OpportunityId != null
			&& q.Global_Discount__c == null
			&& q.Quote_Type__c != Constants.QUOTE_TYPE_STAMP;
	}

	public static void assignQuoteNumbers(List<Quote> newList) {
		if (newList == null || newList.isEmpty()) return;

		Quote_Sequence__c sequence = QuoteSequenceSelector.getOrgDefaultForUpdate();
		if (sequence == null) {
			throw new QuoteServiceException(ERR_NO_SEQUENCE);
		}

		Long lastNumber = sequence.Last_Number__c != null ? sequence.Last_Number__c.longValue() : 0L;
		List<Quote> toUpdate = new List<Quote>();
		for (Quote q : newList) {
			lastNumber++;
			toUpdate.add(new Quote(Id = q.Id, Quote_Number__c = String.valueOf(lastNumber)));
		}

		sequence.Last_Number__c = lastNumber;

		TriggerHandler.bypass(Constants.QUOTE_HANDLER_NAME);
		try {
			update toUpdate;
			update sequence;
		} catch (Exception e) {
			BoltErrorLogger.logError(
				CLASS_NAME,
				'assignQuoteNumbers',
				ERR_ASSIGN_NUMBERS + ': ' + e.getMessage(),
				e.getStackTraceString(),
				Constants.SOURCE_TYPE_APEX,
				Constants.SEVERITY_ERROR,
				UserInfo.getUserId(),
				null
			);
			throw e;
		} finally {
			TriggerHandler.clearBypass(Constants.QUOTE_HANDLER_NAME);
		}
	}

	public static void applyGlobalDiscount(List<Quote> newList, Map<Id, Quote> oldMap) {
		if (newList == null || newList.isEmpty() || oldMap == null) return;

		Map<Id, Decimal> discountByQuoteId = new Map<Id, Decimal>();
		for (Quote q : newList) {
			Decimal newDiscount = q.Global_Discount__c;
			Decimal oldDiscount = oldMap.get(q.Id) != null ? oldMap.get(q.Id).Global_Discount__c : null;

			// Apply on any change, including a reset to 0. Only a null (cleared) value is skipped.
			if (newDiscount != null && newDiscount != oldDiscount) {
				discountByQuoteId.put(q.Id, newDiscount);
			}
		}

		if (discountByQuoteId.isEmpty()) return;

		List<QuoteLineItem> lineItems = QuoteLineItemSelector.getLineItemsForDiscountUpdate(discountByQuoteId.keySet());
		if (lineItems.isEmpty()) return;

		List<QuoteLineItem> toUpdate = new List<QuoteLineItem>();
		for (QuoteLineItem qli : lineItems) {
			Decimal discount = discountByQuoteId.get(qli.QuoteId);
			if (qli.Discount != discount) {
				toUpdate.add(new QuoteLineItem(Id = qli.Id, Discount = discount));
			}
		}

		if (toUpdate.isEmpty()) return;

		TriggerHandler.bypass(Constants.QUOTE_LINE_ITEM_HANDLER_NAME);
		try {
			update toUpdate;
		} catch (Exception e) {
			BoltErrorLogger.logError(
				CLASS_NAME,
				'applyGlobalDiscount',
				ERR_APPLY_GLOBAL_DISCOUNT + ': ' + e.getMessage(),
				e.getStackTraceString(),
				Constants.SOURCE_TYPE_APEX,
				Constants.SEVERITY_ERROR,
				UserInfo.getUserId(),
				null
			);
			throw e;
		} finally {
			TriggerHandler.clearBypass(Constants.QUOTE_LINE_ITEM_HANDLER_NAME);
		}

		// The Quote Line Item updates above ran with the QLI trigger bypassed, so the
		// Opportunity amounts/Price Per Watt won't recalc on their own. Re-sync them here.
		recalculateOpportunityForQuotes(discountByQuoteId.keySet());
	}

	/**
	 * beforeInsert: auto-activates the first Quote of each (Design Revision, Quote Type)
	 * combination. Operates in-memory on Trigger.new — no DML required.
	 *
	 * @param newList the Quotes being inserted (Trigger.new)
	 */
	public static void autoActivateIfFirst(List<Quote> newList) {
		if (newList == null || newList.isEmpty()) return;

		Set<Id> drIds = new Set<Id>();
		for (Quote q : newList) {
			if (q.Design_Revision__c != null) {
				drIds.add(q.Design_Revision__c);
			}
		}
		if (drIds.isEmpty()) return;

		Set<String> existingCombos = new Set<String>();
		for (AggregateResult ar : QuoteSelector.countByDRAndType(drIds)) {
			existingCombos.add(comboKey((Id) ar.get('drId'), (String) ar.get('quoteType')));
		}

		Set<String> activatedInTransaction = new Set<String>();
		for (Quote q : newList) {
			if (q.Design_Revision__c == null || q.Quote_Type__c == null) continue;
			String combo = comboKey(q.Design_Revision__c, q.Quote_Type__c);
			if (!existingCombos.contains(combo) && !activatedInTransaction.contains(combo)) {
				q.Active__c = true;
				activatedInTransaction.add(combo);
			}
		}
	}

	/**
	 * afterInsert: recalculates Opportunity amounts when an active Quote was inserted
	 * under an active Design Revision.
	 *
	 * @param newList the Quotes that were inserted (Trigger.new)
	 */
	public static void handleAfterInsert(List<Quote> newList) {
		if (newList == null || newList.isEmpty()) return;

		Set<Id> drIds = new Set<Id>();
		for (Quote q : newList) {
			if (q.Active__c == true && q.Design_Revision__c != null) {
				drIds.add(q.Design_Revision__c);
			}
		}

		Set<Id> oppIds = getActiveOpportunityIdsForRevisions(drIds);
		if (!oppIds.isEmpty()) {
			OpportunityAmountService.recalculate(oppIds);
		}
	}

	/**
	 * afterUpdate: handles activation (deactivating other active Quotes of the same type
	 * under the same Design Revision) and recalculates Opportunity amounts when a Quote's
	 * Active__c flag or active Quote amount changes.
	 *
	 * @param newList the updated Quotes (Trigger.new)
	 * @param oldMap the pre-update Quote state keyed by Id (Trigger.oldMap)
	 */
	public static void handleAfterUpdate(List<Quote> newList, Map<Id, Quote> oldMap) {
		if (newList == null || newList.isEmpty() || oldMap == null) return;

		List<Quote> newlyActivated = new List<Quote>();
		Set<Id> revisionsToRecalc = new Set<Id>();

		for (Quote q : newList) {
			Quote oldQuote = oldMap.get(q.Id);
			if (oldQuote == null) continue;

			Boolean activeChanged = q.Active__c != oldQuote.Active__c;
			Boolean amountChanged = q.TotalPrice != oldQuote.TotalPrice;

			if (activeChanged && q.Active__c == true) {
				newlyActivated.add(q);
			}
			// Recalc when activation toggles (either direction) or when an active
			// Quote's amount changes. Amount changes on inactive Quotes do not matter.
			if (q.Design_Revision__c != null && (activeChanged || (amountChanged && q.Active__c == true))) {
				revisionsToRecalc.add(q.Design_Revision__c);
			}
		}

		deactivateSupersededQuotes(newlyActivated);

		Set<Id> oppIds = getActiveOpportunityIdsForRevisions(revisionsToRecalc);
		if (!oppIds.isEmpty()) {
			OpportunityAmountService.recalculate(oppIds);
		}
	}

	/**
	 * afterDelete: recalculates Opportunity amounts when an active Quote under an active
	 * Design Revision is deleted. Does not auto-activate another Quote of the same type.
	 *
	 * @param oldList the deleted Quotes (Trigger.old)
	 */
	public static void handleAfterDelete(List<Quote> oldList) {
		if (oldList == null || oldList.isEmpty()) return;

		Set<Id> drIds = new Set<Id>();
		for (Quote q : oldList) {
			if (q.Active__c == true && q.Design_Revision__c != null) {
				drIds.add(q.Design_Revision__c);
			}
		}

		Set<Id> oppIds = getActiveOpportunityIdsForRevisions(drIds);
		if (!oppIds.isEmpty()) {
			OpportunityAmountService.recalculate(oppIds);
		}
	}

	/**
	 * Recalculates Opportunity amounts for the active Quotes among the given Ids whose
	 * parent Design Revision is active. Use when a Quote's TotalPrice changes without a
	 * direct Quote DML — e.g. Quote Line Item inserts/updates/deletes, or global-discount
	 * driven Quote Line Item updates (which bypass the Quote Line Item trigger).
	 *
	 * @param quoteIds the Quotes whose line items or totals changed
	 */
	public static void recalculateOpportunityForQuotes(Set<Id> quoteIds) {
		if (quoteIds == null || quoteIds.isEmpty()) return;

		Set<Id> drIds = new Set<Id>();
		for (Quote q : QuoteSelector.getActiveQuotesByIds(quoteIds)) {
			drIds.add(q.Design_Revision__c);
		}

		Set<Id> oppIds = getActiveOpportunityIdsForRevisions(drIds);
		if (!oppIds.isEmpty()) {
			OpportunityAmountService.recalculate(oppIds);
		}
	}

	private static void deactivateSupersededQuotes(List<Quote> newlyActivated) {
		if (newlyActivated.isEmpty()) return;

		Set<Id> drIds = new Set<Id>();
		Set<String> activatedCombos = new Set<String>();
		Set<Id> activatedIds = new Set<Id>();
		for (Quote q : newlyActivated) {
			if (q.Design_Revision__c == null || q.Quote_Type__c == null) continue;
			drIds.add(q.Design_Revision__c);
			activatedCombos.add(comboKey(q.Design_Revision__c, q.Quote_Type__c));
			activatedIds.add(q.Id);
		}
		if (drIds.isEmpty()) return;

		List<Quote> toDeactivate = new List<Quote>();
		for (Quote q : QuoteSelector.getActiveQuotesByDRIds(drIds)) {
			String combo = comboKey(q.Design_Revision__c, q.Quote_Type__c);
			if (activatedCombos.contains(combo) && !activatedIds.contains(q.Id)) {
				toDeactivate.add(new Quote(Id = q.Id, Active__c = false));
			}
		}
		if (toDeactivate.isEmpty()) return;

		TriggerHandler.bypass(Constants.QUOTE_HANDLER_NAME);
		try {
			update toDeactivate;
		} catch (Exception e) {
			throw e;
		} finally {
			TriggerHandler.clearBypass(Constants.QUOTE_HANDLER_NAME);
		}
	}

	private static Set<Id> getActiveOpportunityIdsForRevisions(Set<Id> drIds) {
		Set<Id> oppIds = new Set<Id>();
		if (drIds == null || drIds.isEmpty()) return oppIds;
		for (Design_Revision__c dr : DesignRevisionSelector.getDesignRevisionsByIds(drIds)) {
			if (dr.Is_Active__c == true && dr.Opportunity__c != null) {
				oppIds.add(dr.Opportunity__c);
			}
		}
		return oppIds;
	}

	private static String comboKey(Id drId, String quoteType) {
		return String.valueOf(drId) + '|' + quoteType;
	}

	public class QuoteServiceException extends Exception {}
}
