public with sharing class EmailActivityListController {

	@AuraEnabled(Cacheable=true)
	public static List<EmailMessage> getEmailsForRecord(Id recordId) {
		try {
			return EmailMessageSelector.getByRelatedId(recordId);
		} catch (Exception e) {
			throw new AuraHandledException(e.getMessage());
		}
	}
}
