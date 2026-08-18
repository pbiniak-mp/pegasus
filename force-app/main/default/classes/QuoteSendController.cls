/**
 * Backs the quoteSendToClient LWC.
 *
 * Runs `with sharing` and reads the Quote through QuoteSelector first, so the
 * running user's access to the record is the gate. Only once that passes does it
 * reach for QuoteDocumentSelector, which is deliberately `without sharing` in
 * order to list the Quote's PDFs without granting "Query All Files".
 */
public with sharing class QuoteSendController {

	@AuraEnabled(Cacheable=true)
	public static SendState getSendState(Id quoteId) {
		try {
			Quote quote = QuoteSelector.getQuoteForSend(quoteId);
			if (quote == null) {
				throw new QuoteSendService.QuoteSendException('Quote not found or not visible to you.');
			}

			Datetime lastPriceChange = QuoteDocumentSelector.getLastPriceChange(quoteId);
			List<ContentVersion> pdfs = QuoteDocumentSelector.getQuotePdfs(quoteId);

			return new SendState(quote, pdfs, lastPriceChange);
		} catch (Exception e) {
			throw new AuraHandledException(e.getMessage());
		}
	}

	@AuraEnabled
	public static void markAsSent(Id quoteId, String contentVersionId) {
		try {
			QuoteSendService.markAsSent(quoteId, (Id) contentVersionId);
		} catch (Exception e) {
			throw new AuraHandledException(e.getMessage());
		}
	}

	public class SendState {
		@AuraEnabled public Id quoteId { get; set; }
		@AuraEnabled public String quoteName { get; set; }
		@AuraEnabled public String quoteNumber { get; set; }
		@AuraEnabled public String revisionNumber { get; set; }
		@AuraEnabled public String status { get; set; }
		@AuraEnabled public Boolean sent { get; set; }
		@AuraEnabled public Datetime sentAt { get; set; }
		@AuraEnabled public String sentByName { get; set; }
		@AuraEnabled public String sentDocumentId { get; set; }
		@AuraEnabled public String sentDocumentTitle { get; set; }
		@AuraEnabled public Decimal sentAmount { get; set; }
		@AuraEnabled public Decimal currentAmount { get; set; }
		@AuraEnabled public Decimal pricePerWatt { get; set; }
		@AuraEnabled public Boolean amountDrifted { get; set; }
		@AuraEnabled public Datetime lastPriceChange { get; set; }
		@AuraEnabled public List<QuoteDocument> documents { get; set; }

		public SendState(Quote quote, List<ContentVersion> pdfs, Datetime lastPriceChange) {
			this.quoteId = quote.Id;
			this.quoteName = quote.Name;
			this.quoteNumber = quote.Quote_Number__c;
			this.revisionNumber = quote.Design_Revision__r != null
				? quote.Design_Revision__r.Revision_Number__c
				: null;
			this.status = quote.Status;
			this.sent = quote.Sent_To_Client_At__c != null;
			this.sentAt = quote.Sent_To_Client_At__c;
			this.sentByName = quote.Sent_To_Client_By__r != null
				? quote.Sent_To_Client_By__r.Name
				: null;
			this.sentDocumentId = quote.Sent_Quote_Document__c;
			this.sentAmount = quote.Sent_Quote_Amount__c;
			this.currentAmount = quote.TotalPrice;
			this.pricePerWatt = quote.Price_Per_Watt__c;
			this.lastPriceChange = lastPriceChange;

			// A sent Quote whose total no longer matches the figure that went out.
			// The pricing lock should prevent this, but surfacing it beats hiding it.
			this.amountDrifted = this.sent
				&& quote.Sent_Quote_Amount__c != null
				&& quote.TotalPrice != null
				&& quote.Sent_Quote_Amount__c != quote.TotalPrice;

			this.documents = new List<QuoteDocument>();
			for (ContentVersion cv : pdfs) {
				QuoteDocument doc = new QuoteDocument(cv, lastPriceChange);
				this.documents.add(doc);
				if (doc.contentVersionId == this.sentDocumentId) {
					this.sentDocumentTitle = doc.title;
				}
			}
		}
	}

	public class QuoteDocument {
		@AuraEnabled public String contentVersionId { get; set; }
		@AuraEnabled public String contentDocumentId { get; set; }
		@AuraEnabled public String title { get; set; }
		@AuraEnabled public Datetime createdDate { get; set; }
		@AuraEnabled public String createdByName { get; set; }
		@AuraEnabled public Integer contentSize { get; set; }
		@AuraEnabled public Boolean stale { get; set; }

		public QuoteDocument(ContentVersion cv, Datetime lastPriceChange) {
			this.contentVersionId = cv.Id;
			this.contentDocumentId = cv.ContentDocumentId;
			this.title = cv.Title;
			this.createdDate = cv.CreatedDate;
			this.createdByName = cv.CreatedBy != null ? cv.CreatedBy.Name : null;
			this.contentSize = cv.ContentSize;

			// Generated before the current price was set, so the figures printed on
			// it are not the figures on this record. Two PDFs a couple of hours
			// apart under one Quote number is exactly how this goes wrong.
			this.stale = lastPriceChange != null && cv.CreatedDate < lastPriceChange;
		}
	}
}
