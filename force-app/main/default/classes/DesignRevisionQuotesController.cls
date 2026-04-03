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

	@AuraEnabled(Cacheable=true)
	public static List<Map<String, String>> getQuoteStatusPicklistValues() {
		List<Map<String, String>> options = new List<Map<String, String>>();
		for (Schema.PicklistEntry entry : Quote.Status.getDescribe().getPicklistValues()) {
			if (entry.isActive()) {
				options.add(new Map<String, String>{
					'label' => entry.getLabel(),
					'value' => entry.getValue()
				});
			}
		}
		return options;
	}

	@AuraEnabled
	public static void updateQuoteStatus(Id quoteId, String newStatus) {
		try {
			Quote q = new Quote(Id = quoteId, Status = newStatus);
			update q;
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
		@AuraEnabled public Date expirationDate { get; set; }

		public QuoteWrapper(Quote q) {
			this.id = q.Id;
			this.name = q.Name;
			this.status = q.Status;
			this.quoteType = q.Quote_Type__c;
			this.grandTotal = q.Quote_Grand_Total__c;
			this.recordUrl = '/lightning/r/Quote/' + q.Id + '/view';
			this.expirationDate = q.ExpirationDate;
		}
	}
}
