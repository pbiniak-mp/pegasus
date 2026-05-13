public with sharing class QuoteService {

	private static final String CLASS_NAME = 'QuoteService';
	private static final String ERR_ASSIGN_NUMBERS = 'Failed to assign Quote Numbers';
	private static final String ERR_NO_SEQUENCE = 'Quote_Sequence__c org default record not found';
	private static final String ERR_APPLY_GLOBAL_DISCOUNT = 'Failed to apply Global Discount to Quote Line Items';
	private static final String ERR_SYNC_PRICE_PER_WATT = 'Failed to sync Price Per Watt to Opportunity';

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

			if (newDiscount != null && newDiscount > 0 && newDiscount != oldDiscount) {
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
	}

	public static void syncPricePerWattToOpportunity(List<Quote> newList, Map<Id, Quote> oldMap) {
		if (newList == null || newList.isEmpty() || oldMap == null) return;

		Set<Id> presentedQuoteIds = new Set<Id>();
		for (Quote q : newList) {
			Quote oldQuote = oldMap.get(q.Id);
			String oldStatus = oldQuote != null ? oldQuote.Status : null;
			if (q.Status == Constants.QUOTE_STATUS_PRESENTED
				&& q.Status != oldStatus
				&& q.OpportunityId != null) {
				presentedQuoteIds.add(q.Id);
			}
		}

		if (presentedQuoteIds.isEmpty()) return;

		List<Quote> refreshed = QuoteSelector.getPricePerWattByIds(presentedQuoteIds);
		Map<Id, Opportunity> oppsById = new Map<Id, Opportunity>();
		for (Quote q : refreshed) {
			if (q.OpportunityId == null) continue;
			oppsById.put(q.OpportunityId, new Opportunity(
				Id = q.OpportunityId,
				Price_Per_Watt__c = q.Price_Per_Watt__c
			));
		}

		if (oppsById.isEmpty()) return;

		try {
			update oppsById.values();
		} catch (Exception e) {
			BoltErrorLogger.logError(
				CLASS_NAME,
				'syncPricePerWattToOpportunity',
				ERR_SYNC_PRICE_PER_WATT + ': ' + e.getMessage(),
				e.getStackTraceString(),
				Constants.SOURCE_TYPE_APEX,
				Constants.SEVERITY_ERROR,
				UserInfo.getUserId(),
				null
			);
			throw e;
		}
	}

	public class QuoteServiceException extends Exception {}
}
