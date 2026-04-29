public with sharing class QuotePDFController {
	public Quote quote { get; private set; }
	public Opportunity opp { get; private set; }
	public List<QuoteLineItem> lineItems { get; private set; }
	public Contact contact { get; private set; }

	public static final String EMPTY_STRING = '';
	public static final String DATE_FORMAT = 'MMMM dd, yyyy';
	public static final String FREIGHT_TBD = 'TBD';

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

	public String getDollarPerWatt() {
		if (quote == null || quote.Design_Revision__r == null) return EMPTY_STRING;
		Decimal kw = quote.Design_Revision__r.Project_Wattage_kW__c;
		if (kw == null || kw == 0) return EMPTY_STRING;
		Decimal totalPrice = getTotalPrice();
		if (totalPrice == null || totalPrice == 0) return EMPTY_STRING;
		Decimal watts = kw * 1000;
		Decimal dpw = (totalPrice / watts).setScale(2, System.RoundingMode.HALF_UP);
		return '$ ' + dpw.format();
	}

	public String getFormattedFreight() {
		if (quote == null || quote.ShippingHandling == null || quote.ShippingHandling == 0) {
			return FREIGHT_TBD;
		}
		return '$ ' + quote.ShippingHandling.setScale(2).format();
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