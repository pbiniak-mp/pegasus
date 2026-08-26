/**
 * The single answer to "may this user publish a Quote to a client?".
 *
 * Both PDF entry points ask here before doing anything:
 *   QuoteSavePDFController - the Save Quote PDF button
 *   QuotePDFController     - the rendered page itself, so a hand-typed
 *                            /apex/QuotePDF?id=... URL is refused too
 *
 * The check is a custom permission rather than a profile so the grant lives in
 * exactly one place - the Quote_PDF_Generation permission set - and answering
 * "who can send a quote out" is one list of assignees. Note that a System
 * Administrator can assign that permission set to themselves; this is a
 * deliberate control over who publishes, not a barrier against admins.
 */
public inherited sharing class QuotePDFAccessService {

	public static final String PERMISSION_NAME = 'Generate_Quote_PDF';

	public static final String MSG_NO_PERMISSION =
		'You do not have permission to generate quote PDFs. ' +
		'Ask a Salesforce administrator for the "Quote PDF Generation" permission set.';

	/**
	 * Set from tests to exercise both sides of the gate without depending on a
	 * permission set assignment. Never assigned outside a test context.
	 */
	@TestVisible
	private static Boolean permissionOverride;

	public static Boolean canGeneratePDF() {
		if (permissionOverride != null) return permissionOverride;
		return FeatureManagement.checkPermission(PERMISSION_NAME);
	}
}
