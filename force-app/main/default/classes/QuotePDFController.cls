public with sharing class QuotePDFController {
	public Quote quote { get; private set; }
	public Opportunity opp { get; private set; }
	public List<QuoteLineItem> lineItems { get; private set; }
	public Contact contact { get; private set; }

	// Discounted unit price shown on the PDF, derived from the authoritative
	// TotalPrice: round(TotalPrice / Quantity, 2). Keyed by QuoteLineItem Id.
	public Map<Id, Decimal> displayUnitPriceByLineId { get; private set; }

	// Line total shown on the PDF: displayUnitPrice * Quantity. Recomputed from
	// the rounded 2-decimal unit price (not Salesforce's full-precision TotalPrice)
	// so every line multiplies exactly as the customer will recalculate it.
	// PDF totals may therefore differ from Quote.TotalPrice by a few cents.
	public Map<Id, Decimal> displayCostTotalByLineId { get; private set; }

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

		buildDisplayUnitPrices();
	}

	private void buildDisplayUnitPrices() {
		displayUnitPriceByLineId = new Map<Id, Decimal>();
		displayCostTotalByLineId = new Map<Id, Decimal>();
		if (lineItems == null) return;
		for (QuoteLineItem li : lineItems) {
			Decimal displayPrice;
			if (li.TotalPrice == null || li.Quantity == null || li.Quantity == 0) {
				// Fallback: keep the catalog unit price when we can't derive it
				displayPrice = li.UnitPrice != null ? li.UnitPrice : 0;
			} else {
				displayPrice = (li.TotalPrice / li.Quantity)
					.setScale(2, System.RoundingMode.HALF_UP);
			}
			displayUnitPriceByLineId.put(li.Id, displayPrice);

			Decimal quantity = li.Quantity != null ? li.Quantity : 0;
			displayCostTotalByLineId.put(
				li.Id,
				(displayPrice * quantity).setScale(2, System.RoundingMode.HALF_UP)
			);
		}
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

	// Sums the recomputed display line totals so Sub Total / Racking Total /
	// $/Watt stay consistent with the line amounts printed on the PDF.
	public Decimal getTotalPrice() {
		Decimal total = 0;
		if (lineItems == null) return total;
		for (QuoteLineItem li : lineItems) {
			Decimal lineTotal = displayCostTotalByLineId.get(li.Id);
			total += (lineTotal != null ? lineTotal : 0);
		}
		return total;
	}

	public Decimal getGrandTotalDisplay() {
		Decimal total = getTotalPrice();
		if (quote != null && quote.Tax != null) total += quote.Tax;
		if (quote != null && quote.ShippingHandling != null) total += quote.ShippingHandling;
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