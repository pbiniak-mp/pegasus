public inherited sharing class EmailMessageSelector {
	public static List<EmailMessage> getByRelatedId(Id relatedId) {
		return [
			SELECT Id,
				Subject,
				TextBody,
				HtmlBody,
				FromAddress,
				FromName,
				ToAddress,
				CcAddress,
				Status,
				MessageDate,
				CreatedDate,
				HasAttachment,
				Incoming
			FROM EmailMessage
			WHERE RelatedToId = :relatedId
			ORDER BY MessageDate DESC
		];
	}
}
