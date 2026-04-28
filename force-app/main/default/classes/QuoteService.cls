public with sharing class QuoteService {

	private static final String CLASS_NAME = 'QuoteService';
	private static final String ERR_ASSIGN_NUMBERS = 'Failed to assign Quote Numbers';
	private static final String ERR_NO_SEQUENCE = 'Quote_Sequence__c org default record not found';

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

	public class QuoteServiceException extends Exception {}
}
