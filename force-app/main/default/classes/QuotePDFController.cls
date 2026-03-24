public with sharing class QuotePDFController {
	public Quote quote { get; private set; }
	public Opportunity opp { get; private set; }
	public List<QuoteLineItem> lineItems { get; private set; }
	public Contact contact { get; private set; }

	public static final String EMPTY_STRING = '';
	public static final String DATE_FORMAT = 'MMMM dd, yyyy';

	public QuotePDFController(ApexPages.StandardController stdController) {
		Id quoteId = stdController.getId();
		quote = QuoteSelector.getQuoteById(quoteId);

		if (quote == null) return;

		opp = quote.Opportunity;

		contact = ContactSelector.getContactById(quote.ContactId);

		lineItems = QuoteLineItemSelector.getLineItemsByQuoteId(quoteId);
	}

	public String getFormattedDate() {
		return quote?.CreatedDate != null
			? quote.CreatedDate.format(DATE_FORMAT)
			: EMPTY_STRING;
	}

	public String getFormattedExpirationDate() {
		if (quote?.ExpirationDate == null) return EMPTY_STRING;
		Datetime dt = Datetime.newInstance(
			quote.ExpirationDate.year(),
			quote.ExpirationDate.month(),
			quote.ExpirationDate.day()
		);
		return dt.format(DATE_FORMAT);
	}

	public Decimal getTotalPrice() {
		Decimal total = 0;
		if (lineItems == null) return total;
		for (QuoteLineItem li : lineItems) {
			total += (li.TotalPrice != null ? li.TotalPrice : 0);
		}
		return total;
	}

	public Decimal getTotalAttachments() {
		Decimal total = 0;
		if (lineItems == null) return total;
		for (QuoteLineItem li : lineItems) {
			total += (li.Quantity != null ? li.Quantity : 0);
		}
		return total;
	}

}