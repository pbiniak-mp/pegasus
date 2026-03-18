public with sharing class QuoteSavePDFController {
	public static final String PDF_EXTENSION = '.pdf';

	private final Quote quote;
	public Boolean showSuccess { get; private set; }
	public Boolean showError { get; private set; }
	public String savedFileName { get; private set; }
	public String errorMessage { get; private set; }

	public QuoteSavePDFController(ApexPages.StandardController stdController) {
		this.quote = QuoteSelector.getQuoteById(stdController.getId());
		this.showSuccess = false;
		this.showError = false;
	}

	public PageReference savePDF() {
		try {
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
		PageReference quotePage = new ApexPages.StandardController(quote).view();
		quotePage.setRedirect(true);
		return quotePage;
	}
}