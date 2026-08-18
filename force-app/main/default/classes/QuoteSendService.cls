/**
 * Records the moment a Quote PDF goes out to the client.
 *
 * Salesforce cannot observe an email leaving Outlook, so the send is a deliberate
 * user action. What this class guarantees is that the declaration is complete:
 * who, when, which document, and the price on that document — captured together
 * in one write so the four can never disagree.
 */
public with sharing class QuoteSendService {

	private static final String CLASS_NAME = 'QuoteSendService';
	private static final String METHOD_MARK_AS_SENT = 'markAsSent';

	private static final String ERR_QUOTE_NOT_FOUND = 'Quote not found or not visible to you.';
	private static final String ERR_ALREADY_SENT = 'This Quote has already been marked as sent.';
	private static final String ERR_NO_DOCUMENT = 'Select the PDF that was sent to the client.';
	private static final String ERR_FOREIGN_DOCUMENT = 'That document is not attached to this Quote.';
	private static final String ERR_MARK_AS_SENT = 'Failed to mark Quote as sent';

	// Statuses that already mean the Quote left the building. Marking a Quote as
	// sent must never drag one of these backwards to Presented.
	private static final Set<String> POST_SEND_STATUSES = new Set<String>{
		'Presented',
		'Accepted',
		'Denied'
	};

	/**
	 * Stamps the send declaration onto the Quote and moves it to Presented, which
	 * is what engages the pricing lock.
	 *
	 * @param quoteId the Quote being sent
	 * @param contentVersionId the PDF the user is declaring as sent
	 */
	public static void markAsSent(Id quoteId, Id contentVersionId) {
		Quote quote = QuoteSelector.getQuoteForSend(quoteId);
		if (quote == null) {
			throw new QuoteSendException(ERR_QUOTE_NOT_FOUND);
		}
		if (quote.Sent_To_Client_At__c != null) {
			throw new QuoteSendException(ERR_ALREADY_SENT);
		}
		if (contentVersionId == null) {
			throw new QuoteSendException(ERR_NO_DOCUMENT);
		}
		if (!QuoteDocumentSelector.belongsToQuote(quoteId, contentVersionId)) {
			throw new QuoteSendException(ERR_FOREIGN_DOCUMENT);
		}

		Quote toUpdate = new Quote(
			Id = quote.Id,
			Sent_To_Client_At__c = Datetime.now(),
			Sent_To_Client_By__c = UserInfo.getUserId(),
			Sent_Quote_Document__c = String.valueOf(contentVersionId),
			Sent_Quote_Amount__c = quote.TotalPrice
		);

		// Only advance the status. A Quote already Accepted or Denied keeps its own.
		if (!POST_SEND_STATUSES.contains(quote.Status)) {
			toUpdate.Status = Constants.QUOTE_STATUS_PRESENTED;
		}

		try {
			update toUpdate;
		} catch (Exception e) {
			BoltErrorLogger.logError(
				CLASS_NAME,
				METHOD_MARK_AS_SENT,
				ERR_MARK_AS_SENT + ': ' + e.getMessage(),
				e.getStackTraceString(),
				Constants.SOURCE_TYPE_APEX,
				Constants.SEVERITY_ERROR,
				UserInfo.getUserId(),
				quoteId
			);
			throw e;
		}
	}

	public class QuoteSendException extends Exception {}
}
