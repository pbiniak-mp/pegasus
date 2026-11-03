public inherited sharing class LeadSelector {
	/**
	 * Returns the Leads with the given Ids (Id and OwnerId only).
	 * Sharing follows the calling class; the guest-facing file service runs
	 * it in system mode on purpose because the guest cannot read the Lead.
	 */
	public static List<Lead> getOwnersByIds(Set<Id> leadIds) {
		return [SELECT Id, OwnerId FROM Lead WHERE Id IN :leadIds];
	}
}
