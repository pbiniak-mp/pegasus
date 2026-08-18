/**
 * Reads the PDFs attached to a Quote, plus the Quote's price-change history.
 *
 * Deliberately `without sharing`. ContentDocumentLink is only visible to users who
 * were granted a share on the file itself, so a designer opening a Quote whose PDF
 * was saved by somebody else would otherwise see an empty list. The alternative —
 * handing out "Query All Files" — grants far more than this one screen needs.
 *
 * Callers MUST confirm the running user can see the Quote before calling anything
 * here; QuoteSendController does that through the sharing-aware QuoteSelector.
 */
public without sharing class QuoteDocumentSelector {

	private static final String PDF_SUFFIX = '.pdf';
	private static final String FIELD_GRAND_TOTAL = 'GrandTotal';

	/**
	 * Latest version of every PDF linked to the Quote, oldest first.
	 *
	 * @param quoteId the Quote whose files are wanted
	 * @return the latest ContentVersion of each linked PDF
	 */
	public static List<ContentVersion> getQuotePdfs(Id quoteId) {
		if (quoteId == null) return new List<ContentVersion>();

		Set<Id> documentIds = new Set<Id>();
		for (ContentDocumentLink link : [
			SELECT ContentDocumentId
			FROM ContentDocumentLink
			WHERE LinkedEntityId = :quoteId
		]) {
			documentIds.add(link.ContentDocumentId);
		}
		if (documentIds.isEmpty()) return new List<ContentVersion>();

		return [
			SELECT Id,
				Title,
				FileExtension,
				ContentSize,
				ContentDocumentId,
				CreatedDate,
				CreatedBy.Name
			FROM ContentVersion
			WHERE ContentDocumentId IN :documentIds
				AND IsLatest = true
				AND FileExtension = 'pdf'
			ORDER BY CreatedDate ASC
		];
	}

	/**
	 * When the Quote's total last moved. Used to flag a PDF that was generated
	 * before the current price, which is exactly how two conflicting documents
	 * end up in circulation under one Quote number.
	 *
	 * @param quoteId the Quote to inspect
	 * @return the timestamp of the most recent GrandTotal change, or null if none
	 */
	public static Datetime getLastPriceChange(Id quoteId) {
		if (quoteId == null) return null;

		List<QuoteHistory> history = [
			SELECT CreatedDate
			FROM QuoteHistory
			WHERE QuoteId = :quoteId
				AND Field = :FIELD_GRAND_TOTAL
			ORDER BY CreatedDate DESC
			LIMIT 1
		];
		return history.isEmpty() ? null : history[0].CreatedDate;
	}

	/**
	 * Confirms a ContentVersion really is one of this Quote's PDFs, so a crafted
	 * Id cannot be stamped onto the record as the document that was sent.
	 *
	 * @param quoteId the Quote the document must belong to
	 * @param contentVersionId the document being declared as sent
	 * @return true when the document is attached to the Quote
	 */
	public static Boolean belongsToQuote(Id quoteId, Id contentVersionId) {
		if (quoteId == null || contentVersionId == null) return false;
		for (ContentVersion cv : getQuotePdfs(quoteId)) {
			if (cv.Id == contentVersionId) return true;
		}
		return false;
	}
}
