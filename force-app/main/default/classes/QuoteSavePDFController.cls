public with sharing class QuoteSavePDFController {
	public static final String PDF_EXTENSION = '.pdf';

	private final Quote quote;
	public Boolean showSuccess { get; private set; }
	public Boolean showError { get; private set; }
	public String savedFileName { get; private set; }
	public String errorMessage { get; private set; }

	// Set when the running user lacks the Generate_Quote_PDF custom permission.
	// Kept apart from showError so the page can explain who to ask instead of
	// showing a failure the user cannot act on.
	public Boolean showNoPermission { get; private set; }
	public String noPermissionMessage {
		get { return QuotePDFAccessService.MSG_NO_PERMISSION; }
	}

	// Empty PDF labels blocking generation; rendered as a list on the page.
	public List<String> missingFields { get; private set; }
	public Boolean showIncomplete {
		get { return missingFields != null && !missingFields.isEmpty(); }
	}

	public QuoteSavePDFController(ApexPages.StandardController stdController) {
		this.quote = QuoteSelector.getQuoteById(stdController.getId());
		this.showSuccess = false;
		this.showError = false;
		this.showNoPermission = false;
		this.missingFields = new List<String>();
	}

	public PageReference savePDF() {
		try {
			// Answered before the completeness check, so an ungranted user gets
			// the one thing they can act on rather than a to-do list for a quote
			// they may not send. Nothing is rendered or filed either way.
			if (!QuotePDFAccessService.canGeneratePDF()) {
				this.showNoPermission = true;
				return null;
			}

			if (quote == null) {
				throw new QuotePDFValidationService.IncompleteQuoteException(
					QuotePDFValidationService.MSG_QUOTE_NOT_FOUND
				);
			}

			// A Quote with blanks on it must never reach the client as a PDF.
			this.missingFields = QuotePDFValidationService.getMissingFields(
				quote,
				ContactSelector.getContactById(quote.ContactId),
				QuoteLineItemSelector.getLineItemsByQuoteId(quote.Id)
			);
			if (!this.missingFields.isEmpty()) return null;

			PageReference pdfPage = Page.QuotePDF;
			pdfPage.getParameters().put('id', quote.Id);
			pdfPage.setRedirect(false);

			Blob pdfBlob;
			if (Test.isRunningTest()) {
				pdfBlob = Blob.valueOf('PDF_PLACEHOLDER');
			} else {
				pdfBlob = pdfPage.getContentAsPDF();
			}

			String dateStr = String.valueOf(Date.today()).replace('-', '_');
			String fileName = quote.Name + '_' + dateStr + PDF_EXTENSION;

			ContentVersion cv = new ContentVersion(
				Title = fileName,
				PathOnClient = fileName,
				VersionData = pdfBlob,
				FirstPublishLocationId = quote.Id
			);
			insert cv;

			this.savedFileName = fileName;
			this.showSuccess = true;
			return null;

		} catch (Exception e) {
			this.errorMessage = e.getMessage();
			this.showError = true;
			return null;
		}
	}

	public PageReference goToQuote() {
		if (quote == null) return null;
		PageReference quotePage = new ApexPages.StandardController(quote).view();
		quotePage.setRedirect(true);
		return quotePage;
	}
}