public with sharing class DesignRevisionQuotesController {

	@AuraEnabled(Cacheable=true)
	public static List<QuoteWrapper> getQuotesByRevision(Id revisionId) {
		try {
			List<Quote> quotes = QuoteSelector.getQuotesByDesignRevisionId(revisionId);
			List<QuoteWrapper> result = new List<QuoteWrapper>();
			for (Quote q : quotes) {
				result.add(new QuoteWrapper(q));
			}
			return result;
		} catch (Exception e) {
			throw new AuraHandledException(e.getMessage());
		}
	}

	public class QuoteWrapper {
		@AuraEnabled public Id id { get; set; }
		@AuraEnabled public String name { get; set; }
		@AuraEnabled public String status { get; set; }
		@AuraEnabled public String quoteType { get; set; }
		@AuraEnabled public Decimal grandTotal { get; set; }
		@AuraEnabled public String recordUrl { get; set; }

		public QuoteWrapper(Quote q) {
			this.id = q.Id;
			this.name = q.Name;
			this.status = q.Status;
			this.quoteType = q.Quote_Type__c;
			this.grandTotal = q.Quote_Grand_Total__c;
			this.recordUrl = '/lightning/r/Quote/' + q.Id + '/view';
		}
	}
}
